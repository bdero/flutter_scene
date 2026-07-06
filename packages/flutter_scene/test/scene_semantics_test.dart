// Covers scene accessibility: Camera.worldToScreen and the AABB screen
// projection (pure math, no GPU), and the SceneView semantics tree built
// from SemanticsComponents and widget surfaces (labels, focus rects,
// actions, visibility and occlusion filtering, traversal order).
//
// Scene construction touches the Flutter GPU context, so the widget-level
// tests skip cleanly when it is absent (matching the rest of the suite).
// Scene.render() itself early-returns without static resources; the
// semantics refresh runs from the scene painter regardless, so these tests
// exercise the real per-frame path.

import 'dart:typed_data';

import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/semantics.dart'
    show SemanticsAction, SemanticsNode, SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        Center,
        Directionality,
        Offset,
        Rect,
        Semantics,
        Size,
        SizedBox,
        TextDirection,
        Widget;
import 'package:flutter_scene/scene.dart';
// The projection helper is internal SceneView machinery; reach it directly.
import 'package:flutter_scene/src/widgets/scene_view_semantics.dart'
    show projectAabbToArea;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Scene? _tryScene() {
  try {
    return Scene();
  } catch (_) {
    return null;
  }
}

/// Builds a scene, or null without a GPU. The shader-bundle asset is not
/// loadable under `flutter test`, so pumped frames skip rendering (the
/// not-ready path); the semantics refresh runs from the scene painter
/// regardless.
Future<Scene?> _readyScene(WidgetTester tester) async => _tryScene();

/// A unit quad in the XY plane at z = 0 (two triangles, 0..1 UVs), enough
/// geometry for bounds and raycasts.
MeshGeometry _quad() => MeshGeometry.fromArrays(
  positions: Float32List.fromList([
    -0.5, -0.5, 0, //
    0.5, -0.5, 0, //
    0.5, 0.5, 0, //
    -0.5, 0.5, 0, //
  ]),
  texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
  indices: [0, 1, 2, 0, 2, 3],
);

Node _quadNode({String name = 'quad', Matrix4? transform}) => Node(
  name: name,
  localTransform: transform,
  mesh: Mesh(_quad(), UnlitMaterial()),
);

Aabb3 _unitBounds() =>
    Aabb3.minMax(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5));

Widget _host(Scene scene, {Camera? camera}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(
      width: 200,
      height: 200,
      child: SceneView(scene, camera: camera ?? PerspectiveCamera()),
    ),
  ),
);

/// The node's rect in global (test surface) coordinates, composed through
/// its ancestor transforms.
Rect _globalRect(SemanticsNode node) {
  var rect = node.rect;
  for (
    SemanticsNode? current = node;
    current != null;
    current = current.parent
  ) {
    final transform = current.transform;
    if (transform != null) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  return rect;
}

/// Pumps twice: the first frame's paint refreshes the snapshot and its
/// post-frame callback schedules the semantics update the second frame
/// flushes.
Future<void> _settleSemantics(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Camera.worldToScreen', () {
    test('round-trips screenPointToRay', () {
      final camera = PerspectiveCamera(
        position: Vector3(1, 2, -6),
        target: Vector3(0.5, 0, 1),
      );
      const viewSize = Size(320, 240);
      const screen = Offset(70, 180);
      final ray = camera.screenPointToRay(screen, viewSize);
      final world = ray.origin + ray.direction * 0.35;
      final projected = camera.worldToScreen(world, viewSize);
      expect(projected, isNotNull);
      expect(projected!.dx, closeTo(screen.dx, 1e-2));
      expect(projected.dy, closeTo(screen.dy, 1e-2));
    });

    test('returns null behind the camera', () {
      final camera = PerspectiveCamera(
        position: Vector3(0, 0, -5),
        target: Vector3.zero(),
      );
      expect(
        camera.worldToScreen(Vector3(0, 0, -10), const Size(100, 100)),
        isNull,
      );
    });
  });

  group('projectAabbToArea', () {
    final camera = PerspectiveCamera(
      position: Vector3(0, 0, -5),
      target: Vector3.zero(),
    );
    const area = Rect.fromLTWH(0, 0, 200, 200);

    test('centers a symmetric box in the view', () {
      final rect = projectAabbToArea(_unitBounds(), camera, area);
      expect(rect, isNotNull);
      expect(rect!.center.dx, closeTo(100, 1e-3));
      expect(rect.center.dy, closeTo(100, 1e-3));
      expect(rect.width, greaterThan(0));
    });

    test('offsets by the view area origin', () {
      const offsetArea = Rect.fromLTWH(50, 30, 200, 200);
      final rect = projectAabbToArea(_unitBounds(), camera, offsetArea)!;
      expect(rect.center.dx, closeTo(150, 1e-3));
      expect(rect.center.dy, closeTo(130, 1e-3));
    });

    test('returns null fully behind the camera', () {
      final rect = projectAabbToArea(
        Aabb3.minMax(Vector3(-0.5, -0.5, -8), Vector3(0.5, 0.5, -7)),
        camera,
        area,
      );
      expect(rect, isNull);
    });

    test('returns the whole area when crossing the camera plane', () {
      final rect = projectAabbToArea(
        Aabb3.minMax(Vector3(-0.5, -0.5, -6), Vector3(0.5, 0.5, 0)),
        camera,
        area,
      );
      expect(rect, area);
    });
  });

  testWidgets('SemanticsComponent exposes a projected, actionable node', (
    tester,
  ) async {
    final scene = await _readyScene(tester);
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final handle = tester.ensureSemantics();
    var tapped = false;
    final node = Node(name: 'switch');
    node.addComponent(
      SemanticsComponent(
        label: 'Power switch',
        button: true,
        onTap: () => tapped = true,
        boundsOverride: _unitBounds(),
      ),
    );
    scene.add(node);

    await tester.pumpWidget(_host(scene));
    await _settleSemantics(tester);

    final finder = find.semantics.byLabel('Power switch');
    expect(finder, findsOne);
    expect(
      finder.found.single,
      matchesSemantics(
        label: 'Power switch',
        isButton: true,
        hasTapAction: true,
      ),
    );

    // The 200x200 view is centered on the default 800x600 test surface, and
    // a camera-facing symmetric box projects to the view center.
    final dpr = tester.view.devicePixelRatio;
    final rect = _globalRect(finder.found.single);
    expect(rect.center.dx, closeTo(400 * dpr, 1.0));
    expect(rect.center.dy, closeTo(300 * dpr, 1.0));

    tester.semantics.tap(finder);
    expect(tapped, isTrue);
    handle.dispose();
  });

  testWidgets('invisible and behind-camera nodes drop out of the tree', (
    tester,
  ) async {
    final scene = await _readyScene(tester);
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final handle = tester.ensureSemantics();
    final visible = Node(name: 'visible')
      ..addComponent(
        SemanticsComponent(label: 'Front', boundsOverride: _unitBounds()),
      );
    final behind =
        Node(
          name: 'behind',
          localTransform: Matrix4.translation(Vector3(0, 0, -10)),
        )..addComponent(
          SemanticsComponent(label: 'Behind', boundsOverride: _unitBounds()),
        );
    scene.add(visible);
    scene.add(behind);

    await tester.pumpWidget(_host(scene));
    await _settleSemantics(tester);

    expect(find.semantics.byLabel('Front'), findsOne);
    expect(find.semantics.byLabel('Behind'), findsNothing);

    visible.visible = false;
    await _settleSemantics(tester);
    expect(find.semantics.byLabel('Front'), findsNothing);

    visible.visible = true;
    await _settleSemantics(tester);
    expect(find.semantics.byLabel('Front'), findsOne);
    handle.dispose();
  });

  testWidgets('sortOrder controls traversal order', (tester) async {
    final scene = await _readyScene(tester);
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final handle = tester.ensureSemantics();
    final bounds = Aabb3.minMax(
      Vector3(-0.2, -0.2, -0.2),
      Vector3(0.2, 0.2, 0.2),
    );
    // Registered first but sorted last, and vice versa.
    final first =
        Node(
          name: 'first',
          localTransform: Matrix4.translation(Vector3(-1, 0, 0)),
        )..addComponent(
          SemanticsComponent(
            label: 'Second in order',
            sortOrder: 2,
            boundsOverride: bounds,
          ),
        );
    final second =
        Node(
          name: 'second',
          localTransform: Matrix4.translation(Vector3(1, 0, 0)),
        )..addComponent(
          SemanticsComponent(
            label: 'First in order',
            sortOrder: 1,
            boundsOverride: bounds,
          ),
        );
    scene.add(first);
    scene.add(second);

    await tester.pumpWidget(_host(scene));
    await _settleSemantics(tester);

    final labels = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.label)
        .where((label) => label.isNotEmpty)
        .toList();
    expect(
      labels.indexOf('First in order'),
      lessThan(labels.indexOf('Second in order')),
    );
    handle.dispose();
  });

  testWidgets('occlusionHiding drops a node behind scene geometry', (
    tester,
  ) async {
    final scene = await _readyScene(tester);
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final handle = tester.ensureSemantics();
    // Camera on +Z looking at the origin; a wall between them occludes the
    // gauge at the origin.
    final camera = PerspectiveCamera(
      position: Vector3(0, 0, 5),
      target: Vector3.zero(),
    );
    final gauge = _quadNode(name: 'gauge')
      ..addComponent(SemanticsComponent(label: 'Gauge', occlusionHiding: true));
    final wall = _quadNode(
      name: 'wall',
      transform: Matrix4.translation(Vector3(0, 0, 2))
        ..scaleByVector3(Vector3(3, 3, 1)),
    );
    scene.add(gauge);
    scene.add(wall);

    await tester.pumpWidget(_host(scene, camera: camera));
    await _settleSemantics(tester);
    expect(find.semantics.byLabel('Gauge'), findsNothing);

    wall.visible = false;
    await _settleSemantics(tester);
    expect(find.semantics.byLabel('Gauge'), findsOne);

    // Without the opt-in the occluded node stays focusable.
    wall.visible = true;
    gauge.getComponents<SemanticsComponent>().first.occlusionHiding = false;
    await _settleSemantics(tester);
    expect(find.semantics.byLabel('Gauge'), findsOne);
    handle.dispose();
  });

  testWidgets('explicit SemanticsProperties pass through', (tester) async {
    final scene = await _readyScene(tester);
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final handle = tester.ensureSemantics();
    var increased = 0;
    final node = Node(name: 'slider');
    node.addComponent(
      SemanticsComponent(
        boundsOverride: _unitBounds(),
        properties: SemanticsProperties(
          label: 'Volume',
          value: '40%',
          increasedValue: '50%',
          textDirection: TextDirection.ltr,
          onIncrease: () => increased++,
        ),
      ),
    );
    scene.add(node);

    await tester.pumpWidget(_host(scene));
    await _settleSemantics(tester);

    final finder = find.semantics.byLabel('Volume');
    expect(finder, findsOne);
    expect(finder.found.single.value, '40%');
    tester.semantics.performAction(finder, SemanticsAction.increase);
    expect(increased, 1);
    handle.dispose();
  });

  testWidgets('widget surface semantics join the tree and dispatch actions', (
    tester,
  ) async {
    final scene = await _readyScene(tester);
    if (scene == null) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final handle = tester.ensureSemantics();
    var pressed = false;
    final node = Node(name: 'panel');
    node.addComponent(
      WidgetComponent(
        size: const Size(100, 100),
        child: Center(
          child: Semantics(
            label: 'Panel button',
            button: true,
            onTap: () => pressed = true,
            child: const SizedBox(width: 50, height: 50),
          ),
        ),
      ),
    );
    scene.add(node);

    await tester.pumpWidget(_host(scene));
    await _settleSemantics(tester);

    final finder = find.semantics.byLabel('Panel button');
    expect(finder, findsOne);

    // The surface faces the default camera head-on and is centered, so the
    // button's projected rect is centered on the view (and the test
    // surface).
    final dpr = tester.view.devicePixelRatio;
    final rect = _globalRect(finder.found.single);
    expect(rect.center.dx, closeTo(400 * dpr, 1.0));
    expect(rect.center.dy, closeTo(300 * dpr, 1.0));

    tester.semantics.tap(finder);
    expect(pressed, isTrue);

    // Hiding the surface's node removes the subtree from semantics.
    node.visible = false;
    await _settleSemantics(tester);
    expect(find.semantics.byLabel('Panel button'), findsNothing);
    handle.dispose();
  });
}
