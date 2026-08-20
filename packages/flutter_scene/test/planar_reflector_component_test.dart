// Covers PlanarReflectorComponent: the world-plane derivation (headless),
// and (GPU-gated) render-scene registration, per-frame capture-pass
// composition in the primary view's graph, group sharing, layer masks, the
// recursion guard, and the default-off path.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('worldPlane', () {
    test('derives from the node transform with the local +Y default', () {
      final node = Node();
      final reflector = PlanarReflectorComponent();
      node.addComponent(reflector);

      node.position = Vector3(0, 2, 0);
      var plane = reflector.worldPlane();
      expect((plane.normal - Vector3(0, 1, 0)).length, lessThan(1e-6));
      expect(plane.constant, closeTo(-2.0, 1e-6));

      // Rotate the node 90 degrees about x: local +Y becomes world -Z.
      node.position = Vector3.zero();
      node.rotation = Quaternion.axisAngle(
        Vector3(1, 0, 0),
        90 * degrees2Radians,
      );
      plane = reflector.worldPlane();
      expect(plane.normal.x.abs(), lessThan(1e-6));
      expect(plane.normal.y.abs(), lessThan(1e-6));
      expect(plane.normal.z.abs(), closeTo(1.0, 1e-6));
    });

    test('an explicit local normal and non-uniform scale stay unit', () {
      final node = Node();
      final reflector = PlanarReflectorComponent(localNormal: Vector3(0, 0, 1));
      node.addComponent(reflector);
      node.scale = Vector3(3, 1, 0.25);
      final plane = reflector.worldPlane();
      expect(plane.normal.length, closeTo(1.0, 1e-6));
      expect(plane.normal.z, closeTo(1.0, 1e-6));
    });
  });

  if (!_gpuAvailable()) {
    test(
      'planar reflector suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  Node mirrorNode({
    Material? material,
    int reflectionGroupId = -1,
    int layerMask = kRenderLayerAll,
    Vector3? position,
  }) {
    final node = Node(
      mesh: Mesh(
        PlaneGeometry(width: 4, depth: 4),
        material ?? UnlitMaterial(),
      ),
    );
    if (position != null) node.position = position;
    node.addComponent(
      PlanarReflectorComponent(
        reflectionGroupId: reflectionGroupId,
        layerMask: layerMask,
      ),
    );
    return node;
  }

  // Renders one 64x64 frame of [scene] from a camera above the mirror plane.
  void renderFrame(Scene scene, {Camera? camera}) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    scene.render(
      camera ?? PerspectiveCamera(position: Vector3(0, 3, -6)),
      canvas,
      viewport: const ui.Rect.fromLTWH(0, 0, 64, 64),
      pixelRatio: 1.0,
    );
    recorder.endRecording().dispose();
  }

  test('mount and unmount register with the render scene', () async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    final node = mirrorNode();
    scene.add(node);
    final reflector = node.getComponent<PlanarReflectorComponent>()!;
    expect(scene.renderScene.planarReflectorComponents, [reflector]);
    scene.remove(node);
    expect(scene.renderScene.planarReflectorComponents, isEmpty);
  });

  test(
    'a visible reflector adds one capture pass to the primary view',
    () async {
      await Scene.initializeStaticResources();
      final scene = Scene();
      scene.add(mirrorNode());
      scene.add(
        Node(mesh: Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial()))
          ..position = Vector3(0, 1, 0),
      );

      renderFrame(scene);
      expect(scene.debugLastPlanarCapturePasses, hasLength(1));
      final pass = scene.debugLastPlanarCapturePasses.single;
      // Half resolution of the 64x64 view by default.
      expect(pass.dimensions, const ui.Size(32, 32));
      expect(pass.layerMask, kRenderLayerAll);
      // The recursion guard: the capture's own scene pass suppresses planar
      // sampling, so a capture never renders another capture.
      expect(pass.scenePass.debugSuppressesPlanarReflections, isTrue);
      expect(pass.scenePass.debugLayerMask, kRenderLayerAll);
    },
  );

  test(
    'the capture pass lands between the shadow pass and the scene pass',
    () async {
      await Scene.initializeStaticResources();
      final scene = Scene();
      scene.add(mirrorNode());
      scene.directionalLight = DirectionalLight(
        direction: Vector3(0, -1, 0.2),
        castsShadow: true,
      );

      Scene.debugAllowRenderGraphCapture = true;
      try {
        final capture = scene.captureRenderGraph();
        renderFrame(scene);
        final result = await capture;
        final names = result.passes.map((p) => p.name).toList();
        expect(names, contains('PlanarReflectionCapturePass'));
        final planarIndex = names.indexOf('PlanarReflectionCapturePass');
        final sceneIndex = names.indexOf('ScenePass');
        expect(planarIndex, lessThan(sceneIndex));
        final shadowIndex = names.indexOf('ShadowPass');
        if (shadowIndex >= 0) {
          expect(shadowIndex, lessThan(planarIndex));
        }
        // No nested capture passes: exactly one appears for one reflector.
        expect(
          names.where((name) => name == 'PlanarReflectionCapturePass'),
          hasLength(1),
        );
      } finally {
        Scene.debugAllowRenderGraphCapture = false;
      }
    },
  );

  test('a scene without reflectors builds no planar passes', () async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial())),
    );
    Scene.debugAllowRenderGraphCapture = true;
    try {
      final capture = scene.captureRenderGraph();
      renderFrame(scene);
      final result = await capture;
      expect(
        result.passes.map((p) => p.name),
        isNot(contains('PlanarReflectionCapturePass')),
      );
      expect(scene.debugLastPlanarCapturePasses, isEmpty);
    } finally {
      Scene.debugAllowRenderGraphCapture = false;
    }
  });

  test('co-planar reflectors sharing a group share one capture', () async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    scene.add(mirrorNode(reflectionGroupId: 7, position: Vector3(-2, 0, 0)));
    scene.add(mirrorNode(reflectionGroupId: 7, position: Vector3(2, 0, 0)));

    renderFrame(scene);
    expect(scene.debugLastPlanarCapturePasses, hasLength(1));
    expect(scene.debugLastPlanarCapturePasses.single.groupKey, 7);

    // Distinct groups (own captures) each get a pass.
    final scene2 = Scene();
    scene2.add(mirrorNode(position: Vector3(-2, 0, 0)));
    scene2.add(mirrorNode(position: Vector3(2, 0, 0)));
    renderFrame(scene2);
    expect(scene2.debugLastPlanarCapturePasses, hasLength(2));
  });

  test('the reflector layer mask reaches the capture scene pass', () async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    scene.add(mirrorNode(layerMask: 1 << 3));
    renderFrame(scene);
    final pass = scene.debugLastPlanarCapturePasses.single;
    expect(pass.layerMask, 1 << 3);
    expect(pass.scenePass.debugLayerMask, 1 << 3);
  });

  test(
    'hidden, off-mask, and behind-plane reflectors do not capture',
    () async {
      await Scene.initializeStaticResources();

      // Hidden node.
      final scene = Scene();
      final hidden = mirrorNode()..visible = false;
      scene.add(hidden);
      renderFrame(scene);
      expect(scene.debugLastPlanarCapturePasses, isEmpty);

      // The camera below the plane sees the mirror's back.
      final behind = Scene();
      behind.add(mirrorNode());
      renderFrame(
        behind,
        camera: PerspectiveCamera(
          position: Vector3(0, -3, -6),
          target: Vector3(0, -1, 0),
        ),
      );
      expect(behind.debugLastPlanarCapturePasses, isEmpty);

      // The view's layer mask excludes the mirror node's layer.
      final masked = Scene();
      final node = mirrorNode();
      node.layers = 1 << 2;
      masked.add(node);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      masked.renderViews(
        [
          RenderView(
            camera: PerspectiveCamera(position: Vector3(0, 3, -6)),
            layerMask: 1 << 5,
          ),
        ],
        canvas,
        region: const ui.Rect.fromLTWH(0, 0, 64, 64),
        pixelRatio: 1.0,
      );
      recorder.endRecording().dispose();
      expect(masked.debugLastPlanarCapturePasses, isEmpty);
    },
  );

  test('frames reach mirror materials and clear when capture stops', () async {
    await Scene.initializeStaticResources();
    final material = _MirrorProbeMaterial();
    final scene = Scene();
    final node = mirrorNode(material: material);
    scene.add(node);

    renderFrame(scene);
    final frame = material.planarReflectionFrame;
    expect(frame, isNotNull);
    expect(frame!.texture.width, 32);
    expect(frame.texture.height, 32);
    expect(
      frame.texture,
      same(scene.debugLastPlanarCapturePasses.single.output),
    );

    // Hiding the mirror stops the capture and clears the routed frame.
    node.visible = false;
    renderFrame(scene);
    expect(material.planarReflectionFrame, isNull);
  });

  test('probe captures never build planar passes', () async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    scene.add(mirrorNode());
    // Prime the debug list with a real frame first.
    renderFrame(scene);
    expect(scene.debugLastPlanarCapturePasses, hasLength(1));
    // An environment capture is a linear-color render; it must not rebuild
    // or replace the planar capture state.
    final passes = scene.debugLastPlanarCapturePasses;
    scene.captureEnvironment(position: Vector3(0, 1, 0), faceResolution: 16);
    expect(identical(scene.debugLastPlanarCapturePasses, passes), isTrue);
  });
}

// An unlit material that opts into planar reflection routing, standing in
// for a `.fmat` mirror material at the frame-distribution seam.
class _MirrorProbeMaterial extends UnlitMaterial {
  @override
  bool get usesPlanarReflection => true;
}
