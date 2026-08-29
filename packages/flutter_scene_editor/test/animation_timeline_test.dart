import 'dart:ui';

import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_editor/src/panels/animation_panel.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

// Mirror of the private layout constants in animation_panel.dart.
const double _rulerTop = 18;
const double _rowHeight = 22;

double _laneRowCenterY() => _rulerTop + _rowHeight / 2;

/// A controller over a fresh document: one node plus a 1s translation
/// animation with keys at t = 0 and t = 1.
Future<(EditorController, LocalId)> pumpScene() async {
  await Scene.initializeStaticResources();
  final document = SceneDocument();
  final nodeId = document.newId();
  document.addNode(NodeSpec(id: nodeId, name: 'Box'), root: true);
  final controller = await EditorController.open(EditorSession(document));
  await controller.run('createAnimation', {});
  final animationId = document.animations.keys.single;
  for (final time in const [0.0, 1.0]) {
    await controller.run('setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': nodeId.toToken(),
      'property': 'translation',
      'time': time,
    });
  }
  addTearDown(controller.dispose);
  return (controller, animationId);
}

Future<(EditorController, LocalId)> pumpTimeline(WidgetTester tester) async {
  final (controller, animationId) = await pumpScene();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 200,
          child: AnimationTimeline(
            controller: controller,
            animation: controller.document.animations[animationId]!,
            duration: controller.previewDuration(animationId),
            selectedKey: null,
            draggingKey: false,
            dragFromTime: null,
            onTapLane: (_) {},
            onScrub: (_) {},
            onSelectKey: (_) {},
            onDragKeyStart: (_) {},
            onDragKeyUpdate: (_) {},
            onDragKeyEnd: () {},
            onDoubleTapLane: (_, __) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (controller, animationId);
}

/// Pumps the full [AnimationPanel] (its own timeline state, key handling and
/// transport) instead of the bare [AnimationTimeline], so gesture-driven key
/// edits in the panel state run end to end.
Future<(EditorController, LocalId)> pumpPanel(WidgetTester tester) async {
  final (controller, animationId) = await pumpScene();

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
  return (controller, animationId);
}

double _painterField(WidgetTester tester, String field) {
  final custom = tester
      .widgetList<CustomPaint>(
        find.byWidgetPredicate((widget) => widget is CustomPaint),
      )
      .firstWhere(
        (custom) => custom.painter?.runtimeType.toString() == '_TimelinePainter',
      );
  return (((custom.painter as dynamic).noSuchMethod(
    Invocation.getter(Symbol(field)),
  )) as num)
      .toDouble();
}

void main() {
  // Pure view-math coverage — runs anywhere, no GPU needed.
  group('TimelineViewport', () {
    const laneWidth = 472.0;

    test('defaults to fit-to-clip', () {
      final viewport = TimelineViewport(laneWidth: laneWidth, duration: 1);
      expect(viewport.pxPerSecond, closeTo(472, 0.01));
      expect(viewport.maxScroll, 0);
      expect(viewport.scroll, 0);
    });

    test('zooms out past fit so empty time past the clip is reachable', () {
      const fit = TimelineViewport(laneWidth: laneWidth, duration: 1);
      // The pre-fix behavior clamped here and scrolling appeared dead.
      final zoomedOut = fit.scaledBy(0.5);
      expect(zoomedOut, lessThan(fit.pxPerSecond));
      expect(
        TimelineViewport(laneWidth: laneWidth, duration: 1, zoomPx: zoomedOut)
            .pxPerSecond,
        closeTo(zoomedOut, 0.01),
      );
    });

    test('zoom floor keeps long clips fittable', () {
      // A 60s clip fits at ~7.9px/s — below the absolute floor; fit must
      // stay reachable rather than being pushed up to the floor.
      final viewport = TimelineViewport(laneWidth: laneWidth, duration: 60);
      expect(viewport.pxPerSecond, viewport.fitPxPerSecond);
      expect(
        viewport.fitPxPerSecond,
        lessThan(TimelineViewport.minPxPerSecond),
      );
    });

    test('zoom ceiling caps magnification', () {
      const fit = TimelineViewport(laneWidth: laneWidth, duration: 1);
      expect(fit.scaledBy(100), TimelineViewport.maxPxPerSecond);
    });

    test('scroll stays inside the pannable range at every scale', () {
      for (final zoom in [null, 20.0, 50.0, 292.0, 472.0, 600.0]) {
        final viewport = TimelineViewport(
          laneWidth: laneWidth,
          duration: 1,
          zoomPx: zoom,
          scroll: -1234,
        );
        expect(viewport.scroll, inInclusiveRange(0, viewport.maxScroll));
      }
    });

    test('anchor-preserving scroll keeps the anchor time centered', () {
      const fit = TimelineViewport(laneWidth: laneWidth, duration: 1);
      const anchorTime = 0.4;
      final next = fit.scaledBy(1.3);
      final scrolled = fit.scrollForAnchor(anchorTime, next);
      expect((scrolled + laneWidth / 2) / next, closeTo(anchorTime, 1e-6));
    });
  });

  if (!_gpuAvailable()) {
    test(
      'animation timeline zoom and clip extension',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  Future<void> zoomWithWheel(
    WidgetTester tester,
    int pointerId,
    Offset delta,
  ) async {
    await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final pointer = TestPointer(pointerId, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(AnimationTimeline)));
    await tester.sendEventToBinding(pointer.scroll(delta));
    await tester.pump();
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  testWidgets('ctrl+wheel expands the timeline past the clip end', (
    tester,
  ) async {
    final (controller, animationId) = await pumpTimeline(tester);
    // 600px wide minus the 120px label column and padding → 472px of lane
    // for a 1s clip.
    expect(controller.previewDuration(animationId), 1.0);
    final fit = _painterField(tester, 'pxPerSecond');
    expect(fit, closeTo(472.0, 0.5));

    // Ctrl+wheel down (the natural "shrink" gesture) must scale below fit —
    // previously it clamped at fit and did nothing at all.
    await zoomWithWheel(tester, 1, const Offset(0, 240));

    final zoomedOut = _painterField(tester, 'pxPerSecond');
    expect(zoomedOut, lessThan(fit * 0.7));
  });

  testWidgets('double-clicking a lane past the clip end extends its duration', (
    tester,
  ) async {
    final (controller, animationId) = await pumpTimeline(tester);

    // Zoom out so there is visible empty space beyond the 1s clip.
    await zoomWithWheel(tester, 2, const Offset(0, 240));
    final pxPerSecond = _painterField(tester, 'pxPerSecond');

    // Double-click a lane row past the clip's end (t ≈ 1.3s).
    final target = Offset(120 + 1.3 * pxPerSecond, _laneRowCenterY());
    await tester.tapAt(target);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(target);
    await tester.pump();

    expect(controller.previewDuration(animationId), greaterThan(1.0));
    expect(controller.previewDuration(animationId), closeTo(1.3, 0.05));
  });

  testWidgets('plain wheel pans once the timeline is zoomed in', (
    tester,
  ) async {
    await pumpTimeline(tester);

    // Zoom in first so there is something to pan through.
    await zoomWithWheel(tester, 3, const Offset(0, -480));
    expect(_painterField(tester, 'scrollPx'), 0.0);

    final pointer = TestPointer(3, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(AnimationTimeline)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump();
    expect(_painterField(tester, 'scrollPx'), greaterThan(0.0));
  });

  testWidgets('trackpad pinch zooms the timeline', (tester) async {
    await pumpTimeline(tester);
    final fit = _painterField(tester, 'pxPerSecond');

    final center = tester.getCenter(find.byType(AnimationTimeline));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 2.0);
    await gesture.panZoomEnd();

    expect(_painterField(tester, 'pxPerSecond'), greaterThan(fit));
  });

  testWidgets('dragging a keyframe diamond retimes it', (tester) async {
    final (controller, animationId) = await pumpPanel(tester);
    List<double> times() => channelTimes(
      controller.document,
      controller.document.animations[animationId]!.channels.single,
    );
    expect(times(), [0.0, 1.0]);

    // Fit mode: a 600px pane with a 1s clip gives 472 lane px/s, so the
    // t = 1s diamond sits at x = 120 + 472 = 592 in the timeline's own
    // coordinate space (the panel wraps the timeline below its keybar).
    final timelineRect = tester.getRect(find.byType(AnimationTimeline));
    final start = timelineRect.topLeft + Offset(592, _laneRowCenterY());
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    // Small steps keep the pan-start pointer (which sits at the point the
    // gesture was accepted, a few px in) inside the diamond's 12px hit reach,
    // while the total accumulates toward −236px ⇒ −0.5s.
    for (var i = 0; i < 59; i++) {
      await gesture.moveBy(const Offset(-4, 0));
      await tester.pump();
    }
    await gesture.up();
    // The commit runs as a controller command; settle until it lands.
    await tester.pumpAndSettle();

    final moved = times();
    expect(moved.length, 2);
    expect(moved, contains(closeTo(0.0, 1e-4)));
    expect(moved, contains(closeTo(0.5, 0.04)));
    expect(moved.any((t) => (t - 1.0).abs() < 1e-3), isFalse);
  });

  testWidgets('resizing the pane rescales the timeline at the same zoom', (
    tester,
  ) async {
    final (controller, _) = await pumpPanel(tester);
    final before = _painterField(tester, 'pxPerSecond');
    expect(before, closeTo(472.0, 0.5));

    // Zoom out through the pill so the scale is user-locked to an absolute
    // value (previously this froze the timeline from following the pane).
    // Out, not in: the 600 px/s ceiling would clip the ratio we assert below.
    await tester.tap(find.byIcon(Icons.zoom_out_map));
    await tester.pump();
    final zoomed = _painterField(tester, 'pxPerSecond');
    expect(zoomed, lessThan(before));

    // Widen the pane 600 → 900 (lane 472 → 772): the timeline must stretch
    // too, keeping the same zoom percentage (px per second × lane ratio).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 320,
            child: AnimationPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    final widened = _painterField(tester, 'pxPerSecond');
    expect(widened / zoomed, closeTo(772 / 472, 0.01));
  });
}
