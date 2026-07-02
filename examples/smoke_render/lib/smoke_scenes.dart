import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
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

/// A slightly elevated view for the shadow scene, framed so the small
/// ground plane stays central and the corners remain the magenta clear.
PerspectiveCamera _shadowCamera() => PerspectiveCamera(
  position: vm.Vector3(2.6, 2.4, 3.0),
  target: vm.Vector3(0, 0.25, 0),
);

Node _cuboid(vm.Vector4 baseColor, double metallic, double roughness) {
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = baseColor
    ..metallicFactor = metallic
    ..roughnessFactor = roughness
    ..vertexColorWeight = 0.0;
  return Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material))
    ..localTransform = vm.Matrix4.rotationY(0.6) * vm.Matrix4.rotationX(0.3);
}

/// Custom-material assets pre-loaded by [loadSmokeMaterials], so the
/// synchronous [SmokeScene] setup closures can build a [PreprocessedMaterial].
gpu.ShaderLibrary? _materialsLibrary;
Map<String, Object?>? _materialsMetadata;

/// Loads the `buildMaterials` output (bundle plus parameter sidecar) once. Call
/// before pumping a scene that uses a custom material.
Future<void> loadSmokeMaterials() async {
  if (_materialsLibrary != null) return;
  _materialsLibrary = await gpu.loadShaderLibraryAsync(
    'build/shaderbundles/materials.shaderbundle',
  );
  final sidecar = await rootBundle.loadString(
    'build/shaderbundles/materials.fmat.json',
  );
  _materialsMetadata = (jsonDecode(sidecar) as Map).cast<String, Object?>();
}

/// Builds a `PreprocessedMaterial` for the named `.fmat`, resolving its
/// generated vertex variants from the sidecar's variant map (as the DataAssets
/// loader does), since these scenes build the material by hand.
PreprocessedMaterial _fmatMaterial(String name) {
  final metadata = (_materialsMetadata![name] as Map).cast<String, Object?>();
  final vertexMeta = (metadata['vertex'] as Map?)?.cast<String, Object?>();
  final vertexShaders = vertexMeta == null
      ? null
      : <String, gpu.Shader>{
          for (final e in vertexMeta.entries)
            e.key: _materialsLibrary![e.value as String]!,
        };
  return PreprocessedMaterial(
    fragmentShader: _materialsLibrary![name]!,
    metadata: metadata,
    vertexShaders: vertexShaders,
  );
}

/// A flat NxN grid in the XZ plane carrying a per-vertex `phase` custom
/// attribute, for the custom-material scene.
MeshGeometry _phaseGrid() {
  const n = 24; // cells per side; (n + 1)^2 vertices
  const size = 2.2;
  final vertexCount = (n + 1) * (n + 1);
  final positions = Float32List(vertexCount * 3);
  final phase = Float32List(vertexCount);
  var v = 0;
  for (var r = 0; r <= n; r++) {
    for (var c = 0; c <= n; c++) {
      positions[v * 3] = (c / n - 0.5) * size;
      positions[v * 3 + 2] = (r / n - 0.5) * size;
      phase[v] = (r + c) * 0.6;
      v++;
    }
  }
  final indices = <int>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final i0 = r * (n + 1) + c;
      final i2 = i0 + (n + 1);
      indices.addAll([i0, i2, i0 + 1, i0 + 1, i2, i2 + 1]);
    }
  }
  return MeshGeometry.fromArrays(positions: positions, indices: indices)
    ..setCustomAttribute('phase', phase, components: 1);
}

/// The smoke scene set. Mostly procedural for determinism; the final scenes
/// exercise a custom `.fmat` material compiled by the build hook.
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
  // A directional light casting a shadow from a floating cuboid onto a
  // ground plane. Exercises the ShadowPass (a depth-only shadow-map pass)
  // and the lit material's shadow sampling, which the other scenes don't.
  SmokeScene('directional_shadow', () {
    final scene = Scene();
    scene.add(
      Node()..addComponent(
        DirectionalLightComponent(
          DirectionalLight(
            direction: vm.Vector3(-0.4, -1.0, -0.35),
            castsShadow: true,
            shadowMaxDistance: 20.0,
          ),
        ),
      ),
    );
    // Ground plane (receiver), centered at the origin in the XZ plane.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.0, depth: 3.0),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.78, 0.78, 0.80, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      ),
    );
    // Caster, floating above the plane so its shadow reads as a distinct
    // blob (a stronger visual-diff signal than a shadow merged into the base).
    final caster = _cuboid(vm.Vector4(0.85, 0.45, 0.25, 1.0), 0.0, 0.6)
      ..localTransform =
          vm.Matrix4.translation(vm.Vector3(0, 1.0, 0)) *
          vm.Matrix4.rotationY(0.6);
    scene.add(caster);
    return (scene: scene, camera: _shadowCamera());
  }),
  // The single custom-material scene: one .fmat that customizes BOTH the
  // vertex stage (a world-space ripple, which also displaces the shadow) and
  // the fragment color (blended from a per-vertex attribute forwarded through a
  // varying). Covers the whole custom-material path end to end: the build hook,
  // the generated fragment and vertex variants, sidecar params, a custom
  // attribute, a custom varying, and the depth/shadow variant.
  SmokeScene('fmat_custom_material', () {
    final material = _fmatMaterial('CustomMaterial')
      ..parameters.setFloat('amplitude', 0.3);
    final scene = Scene();
    scene.add(
      Node()..addComponent(
        DirectionalLightComponent(
          DirectionalLight(
            direction: vm.Vector3(-0.4, -1.0, -0.35),
            castsShadow: true,
            shadowMaxDistance: 20.0,
          ),
        ),
      ),
    );
    // Ground receiver, to catch the rippled shadow.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.6, depth: 3.6),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.8, 0.8, 0.82, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      ),
    );
    // The custom-material hero: a grid carrying a per-vertex `phase` attribute,
    // rippled by the vertex stage and colored from the attribute. Floats above
    // the ground so its displaced shadow reads clearly.
    scene.add(
      Node(mesh: Mesh(_phaseGrid(), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.0, 0)),
    );
    return (scene: scene, camera: _shadowCamera());
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
