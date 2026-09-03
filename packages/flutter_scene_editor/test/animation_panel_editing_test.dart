import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_editor/src/panels/animation_panel.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

/// A document with one node plus a fresh animation, a selection on the node,
/// and the full [AnimationPanel] pumped at 600×320.
Future<(EditorController, LocalId, LocalId)> pumpEditablePanel(
  WidgetTester tester,
) async {
  await Scene.initializeStaticResources();
  final document = SceneDocument();
  final nodeId = document.newId();
  document.addNode(NodeSpec(id: nodeId, name: 'Bone'), root: true);
  final session = EditorSession(document);
  final controller = await EditorController.open(session);
  addTearDown(controller.dispose);
  session.selection.selectOnly(nodeId);
  await controller.run('createAnimation', {});
  final animationId = document.animations.keys.single;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 320,
          child: AnimationPanel(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
  return (controller, animationId, nodeId);
}

/// The timeline painter's row list, read off the CustomPaint like
/// [_painterField] reads its scalars. Each entry answers `.title`
/// dynamically (the record type is private).
List<String> painterRowTitles(WidgetTester tester) {
  final custom = tester
      .widgetList<CustomPaint>(
        find.byWidgetPredicate((widget) => widget is CustomPaint),
      )
      .firstWhere(
        (custom) =>
            custom.painter?.runtimeType.toString() == '_TimelinePainter',
      );
  return [
    for (final row in (custom.painter as dynamic).rows as List)
      row.title as String,
  ];
}

void main() {
  if (!_gpuAvailable()) {
    test('animation panel editing', () {}, skip: 'Requires a GPU device.');
    return;
  }

  Future<void> key(
    EditorController controller,
    LocalId animationId,
    LocalId nodeId,
    String property,
    double time,
  ) => controller.run('setAnimationKeyframe', {
    'animationId': animationId.toToken(),
    'nodeId': nodeId.toToken(),
    'property': property,
    'time': time,
  });

  List<double> translationTimes(EditorController c, LocalId id, LocalId node) =>
      channelTimes(
        c.document,
        c.document.animations[id]!.channels.singleWhere(
          (ch) =>
              ch.target == node && ch.property == AnimationProperty.translation,
        ),
      );

  AnimationChannelSpec? channelOf(
    EditorController c,
    LocalId id,
    LocalId node,
    String property,
  ) {
    for (final ch in c.document.animations[id]!.channels) {
      if (ch.target == node && ch.property.name == property) return ch;
    }
    return null;
  }

  testWidgets('a bone\'s lanes stay in translation → rotation → scale order', (
    tester,
  ) async {
    final (controller, animationId, nodeId) = await pumpEditablePanel(tester);

    // Author in reverse order on purpose.
    await key(controller, animationId, nodeId, 'scale', 0.0);
    await key(controller, animationId, nodeId, 'rotation', 0.0);
    await key(controller, animationId, nodeId, 'translation', 0.0);
    await tester.pump();

    final titles = painterRowTitles(tester);
    expect(titles.first, 'Bone');
    expect(titles.skip(1).take(3), ['translation', 'rotation', 'scale']);
  });

  testWidgets('Keying an already-timelined node does not seed edge crystals', (
    tester,
  ) async {
    final (controller, animationId, nodeId) = await pumpEditablePanel(tester);

    // A clip ending at t=1 with nothing at t=0: the node is already on the
    // timeline, so Key captures only the playhead — it must NOT seed a t=0
    // crystal or touch the authored end.
    await key(controller, animationId, nodeId, 'translation', 1.0);
    expect(translationTimes(controller, animationId, nodeId), [1.0]);

    controller.seekPreview(0.5);
    await tester.pump();
    await tester.tap(find.text('Key'));
    await tester.pumpAndSettle();

    // Only the playhead capture landed; both edges stay as authored.
    final times = translationTimes(controller, animationId, nodeId);
    expect(times.map((t) => (t * 100).roundToDouble() / 100), [0.5, 1.0]);
    // rotation/scale were created for the playhead key alone — no edges.
    for (final property in ['rotation', 'scale']) {
      final channel = channelOf(controller, animationId, nodeId, property)!;
      expect(channelTimes(controller.document, channel), [0.5]);
    }

    // And a deliberate lift at t=1 keeps its pose through further Keying.
    await controller.run('setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': nodeId.toToken(),
      'property': 'translation',
      'time': 1.0,
      'translation': {'x': 0.0, 'y': 9.0, 'z': 0.0},
    });
    controller.seekPreview(0.25);
    await tester.pump();
    await tester.tap(find.text('Key'));
    await tester.pumpAndSettle();

    final channel = channelOf(controller, animationId, nodeId, 'translation')!;
    final times2 = channelTimes(controller.document, channel);
    expect(
      times2.map((t) => (t * 100).roundToDouble() / 100),
      [0.25, 0.5, 1.0],
    );
    final bytes = controller.document.payload(channel.keyframes)!.bytes!;
    final values = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    final endRow = times2.indexWhere((t) => (t - 1.0).abs() <= 1e-4);
    expect(values[endRow * 3 + 1], closeTo(9.0, 1e-4));
    expect(values[endRow * 3 + 0], closeTo(0.0, 1e-4));
    expect(values[endRow * 3 + 2], closeTo(0.0, 1e-4));
  });

  testWidgets('a fresh Key at the playhead starts a default 1s clip', (
    tester,
  ) async {
    final (controller, animationId, nodeId) = await pumpEditablePanel(tester);
    controller.selectPreviewAnimation(animationId);

    // The default playhead sits at t=0 and the clip has nothing yet. Keying
    // must capture the pose AND lay the default timeline: crystals at t=0
    // and t=1s on every property — never a lone t=0 crystal and a zero-length
    // clip.
    await tester.tap(find.text('Key'));
    await tester.pumpAndSettle();

    final translation = channelOf(
      controller,
      animationId,
      nodeId,
      'translation',
    )!;
    expect(
      channelTimes(controller.document, translation),
      [0.0, 1.0],
    );

    // The same 1s span opens on rotation and scale.
    for (final property in ['rotation', 'scale']) {
      final channel = channelOf(controller, animationId, nodeId, property)!;
      expect(channelTimes(controller.document, channel), [0.0, 1.0]);
    }
  });

  testWidgets('the lane ✕ removes the channel from the timeline', (
    tester,
  ) async {
    final (controller, animationId, nodeId) = await pumpEditablePanel(tester);

    await key(controller, animationId, nodeId, 'translation', 0.0);
    await key(controller, animationId, nodeId, 'rotation', 0.0);
    await key(controller, animationId, nodeId, 'rotation', 1.0);
    await tester.pump();

    // Translation sits above rotation; its ✕ is the first close icon.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(channelOf(controller, animationId, nodeId, 'translation'), isNull);
    expect(channelOf(controller, animationId, nodeId, 'rotation'), isNotNull);
  });

  testWidgets('each bone group carries an interpolation control', (
    tester,
  ) async {
    final (controller, animationId, nodeId) = await pumpEditablePanel(tester);

    await key(controller, animationId, nodeId, 'translation', 0.0);
    await key(controller, animationId, nodeId, 'translation', 1.0);
    await tester.pump();

    // One control per bone group, aligned with its header row.
    expect(find.byType(SegmentedButton), findsOneWidget);

    // Picking a mode applies to every channel of the group.
    await tester.tap(find.text('Step'));
    await tester.pumpAndSettle();
    expect(
      controller
          .document
          .animations[animationId]!
          .channels
          .single
          .interpolation,
      AnimationInterpolation.step,
    );
  });

  testWidgets('stop lands on the authored pose, never a stale capture', (
    tester,
  ) async {
    final document = SceneDocument();
    final nodeId = document.newId();
    document.addNode(NodeSpec(id: nodeId, name: 'Box'), root: true);
    final session = EditorSession(document);
    final controller = await EditorController.open(session);
    addTearDown(controller.dispose);
    await controller.run('createAnimation', {});
    final animationId = document.animations.keys.single;

    // Animated pose: lifted at t=0 while the authored rest pose stays flat.
    await controller.run('setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': nodeId.toToken(),
      'property': 'translation',
      'time': 0.0,
      'translation': {'x': 0.0, 'y': 5.0, 'z': 0.0},
    });
    controller.selectPreviewAnimation(animationId);
    controller.playPreview();
    await tester.pump(const Duration(milliseconds: 120));
    controller.pausePreview();
    final live = controller.liveNode(nodeId)!;
    expect(live.position.y, closeTo(5.0, 0.01));

    // The author reposes the node while paused — the authored pose changes.
    await controller.run('setNodeTransform', {
      'nodeId': nodeId.toToken(),
      'translation': {'x': 2.0, 'y': 7.0, 'z': 0.0},
    });

    controller.stopPreview();
    // Stop shows exactly what the Outliner shows (y=7), not the last
    // animated pose (5) and not the stale pre-pose capture (0).
    expect(controller.liveNode(nodeId)!.position.y, closeTo(7.0, 1e-4));
    expect(controller.liveNode(nodeId)!.position.x, closeTo(2.0, 1e-4));
  });

  testWidgets(
    'Key captures the visible live pose, never a stale document pose',
    (tester) async {
      final (controller, animationId, nodeId) = await pumpEditablePanel(tester);
      controller.selectPreviewAnimation(animationId);

      // Pose the node the way a gizmo drag does: only the live node moves,
      // while the document's transform (the rest pose the Outliner and
      // Inspector show — the model's origin) stays at the identity.
      controller.liveNode(nodeId)!.position = Vector3(0, 7, 0);
      await tester.pump();

      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      final channel = channelOf(
        controller,
        animationId,
        nodeId,
        'translation',
      )!;
      final bytes = controller.document.payload(channel.keyframes)!.bytes!;
      final values = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      // The key recorded y=7 — the node the user actually saw — not the
      // document origin the command would have re-read without values.
      expect(values[0], closeTo(0.0, 1e-4));
      expect(values[1], closeTo(7.0, 1e-4));
      expect(values[2], closeTo(0.0, 1e-4));
      // And the authored rest pose never moved.
      final trs = controller.document.nodes[nodeId]!.transform as TrsTransform;
      expect(trs.translation.y, closeTo(0.0, 1e-4));
    },
  );

  testWidgets(
  "a node joining the timeline is seeded at the clip's edges with its "
  'visible pose',
  (tester) async {
    // Two-node document: Alpha already animates; Bravo joins later.
    final document = SceneDocument();
    final nodeA = document.newId();
    final nodeB = document.newId();
    document.addNode(NodeSpec(id: nodeA, name: 'Alpha'), root: true);
    document.addNode(NodeSpec(id: nodeB, name: 'Bravo'), root: true);
    final session = EditorSession(document);
    final controller = await EditorController.open(session);
    addTearDown(controller.dispose);
    await controller.run('createAnimation', {});
    final animationId = document.animations.keys.single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 320,
            child: AnimationPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    // Alpha already carries a clip ending at 2s.
    await key(controller, animationId, nodeA, 'translation', 2.0);

    // Select the fresh node, pose it the way a gizmo drag does (live node
    // only), scrub mid-clip and press Key.
    controller.selection.selectOnly(nodeB);
    controller.seekPreview(1.0);
    controller.liveNode(nodeB)!.position = Vector3(0, 7, 0);
    await tester.pump();
    await tester.tap(find.text('Key'));
    await tester.pumpAndSettle();

    // Bravo was not on the timeline, so it is seeded at the clip's edges:
    // crystals at t=0 and the clip's end (2s), plus the playhead capture —
    // all rows carrying the visible pose (y=7), never the document origin.
    final channel = channelOf(
      controller,
      animationId,
      nodeB,
      'translation',
    )!;
    final times = channelTimes(controller.document, channel);
    expect(
      times.map((t) => (t * 100).roundToDouble() / 100),
      [0.0, 1.0, 2.0],
    );
    final bytes = controller.document.payload(channel.keyframes)!.bytes!;
    final values = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    for (var i = 0; i < times.length; i++) {
      expect(values[i * 3 + 1], closeTo(7.0, 1e-4));
    }

    // And Alpha's existing clip is untouched.
    final alphaChannel = channelOf(
      controller,
      animationId,
      nodeA,
      'translation',
    )!;
    expect(channelTimes(controller.document, alphaChannel), [2.0]);
  },
);

testWidgets(
  'nodes hold their first-added position while channels are edited',
  (tester) async {
    // Two-node document; Alpha is keyed first, then Bravo.
    final document = SceneDocument();
    final nodeA = document.newId();
    final nodeB = document.newId();
    document.addNode(NodeSpec(id: nodeA, name: 'Alpha'), root: true);
    document.addNode(NodeSpec(id: nodeB, name: 'Bravo'), root: true);
    final session = EditorSession(document);
    final controller = await EditorController.open(session);
    addTearDown(controller.dispose);
    await controller.run('createAnimation', {});
    final animationId = document.animations.keys.single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 320,
            child: AnimationPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    // Alpha joins the timeline first, then Bravo — that order stays.
    await key(controller, animationId, nodeA, 'translation', 0.0);
    await key(controller, animationId, nodeB, 'translation', 0.0);
    await tester.pump();
    expect(
      painterRowTitles(tester),
      ['Alpha', 'translation', 'Bravo', 'translation'],
    );

    // Re-keying Alpha rewrites its existing channel without demoting it.
    await key(controller, animationId, nodeA, 'translation', 1.0);
    await tester.pump();
    expect(
      painterRowTitles(tester),
      ['Alpha', 'translation', 'Bravo', 'translation'],
    );

    // A brand-new channel for Alpha (rotation) lands under Alpha's block.
    await key(controller, animationId, nodeA, 'rotation', 1.0);
    await tester.pump();
   expect(
      painterRowTitles(tester),
      ['Alpha', 'translation', 'rotation', 'Bravo', 'translation'],
   );
  },
);
}
