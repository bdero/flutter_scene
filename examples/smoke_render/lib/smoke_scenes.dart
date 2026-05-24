import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Side length of the captured render, in logical pixels. Fixed for
/// determinism (independent of window size).
const double kSmokeSize = 512;

/// Distinctive background behind the scene so the sanity assertions can tell
/// rendered geometry from empty space.
const Color kSmokeClear = Color(0xFFFF00FF); // magenta

/// Key on the [RepaintBoundary] wrapping the scene, used by the integration
/// test to capture the rendered frame.
final GlobalKey smokeSceneKey = GlobalKey();

/// A deterministic smoke scene: a builder that produces a [Scene] and the
/// camera to view it from. No animation, no wall-clock input.
class SmokeScene {
  const SmokeScene(this.id, this.setup);

  final String id;
  final ({Scene scene, PerspectiveCamera camera}) Function() setup;
}

/// The fixed three-quarter view shared by the scenes.
PerspectiveCamera _camera() => PerspectiveCamera(
  position: vm.Vector3(3, 2, 4),
  target: vm.Vector3(0, 0, 0),
);

Node _cuboid(vm.Vector4 baseColor, double metallic, double roughness) {
  final material =
      PhysicallyBasedMaterial()
        ..baseColorFactor = baseColor
        ..metallicFactor = metallic
        ..roughnessFactor = roughness
        ..vertexColorWeight = 0.0;
  return Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material))
    ..localTransform = vm.Matrix4.rotationY(0.6) * vm.Matrix4.rotationX(0.3);
}

/// The smoke scene set. Kept small and procedural (no asset/model build hook)
/// so the captures are deterministic.
final List<SmokeScene> kSmokeScenes = <SmokeScene>[
  // Diffuse-ish PBR under the default studio IBL.
  SmokeScene('pbr_cuboid', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.85, 0.30, 0.20, 1.0), 0.1, 0.5));
    return (scene: scene, camera: _camera());
  }),
  // Low-roughness metallic: sensitive to IBL/reflections breaking (would go
  // dark or flat).
  SmokeScene('pbr_metallic', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.95, 0.95, 0.95, 1.0), 1.0, 0.15));
    return (scene: scene, camera: _camera());
  }),
  // Issue #134 regression: a negative-scale (mirrored) node must render
  // right-side-out, not inside-out.
  SmokeScene('mirrored_node', () {
    final scene = Scene();
    final node = _cuboid(vm.Vector4(0.20, 0.55, 0.90, 1.0), 0.1, 0.5)
      ..localTransform =
          vm.Matrix4.rotationY(0.6) *
          vm.Matrix4.rotationX(0.3) *
          vm.Matrix4.diagonal3Values(-1.0, 1.0, 1.0);
    scene.add(node);
    return (scene: scene, camera: _camera());
  }),
];

/// Renders one [SmokeScene] into a fixed-size [RepaintBoundary] over the
/// magenta clear.
class SmokeSceneView extends StatefulWidget {
  const SmokeSceneView(this.scene, {super.key});

  final SmokeScene scene;

  @override
  State<SmokeSceneView> createState() => _SmokeSceneViewState();
}

class _SmokeSceneViewState extends State<SmokeSceneView> {
  late final Scene _scene;
  late final PerspectiveCamera _camera;

  @override
  void initState() {
    super.initState();
    final setup = widget.scene.setup();
    _scene = setup.scene;
    _camera = setup.camera;

    // The first paint happens before flutter_scene's static resources finish
    // loading and is skipped; this view is otherwise static, so trigger one
    // repaint when initialization completes so the scene actually renders.
    Scene.initializeStaticResources().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: smokeSceneKey,
      child: SizedBox(
        width: kSmokeSize,
        height: kSmokeSize,
        child: Container(
          color: kSmokeClear,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SmokePainter(_scene, _camera),
          ),
        ),
      ),
    );
  }
}

class _SmokePainter extends CustomPainter {
  _SmokePainter(this.scene, this.camera);

  final Scene scene;
  final PerspectiveCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
