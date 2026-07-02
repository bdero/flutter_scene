import 'dart:convert';

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

/// Builds a `PreprocessedMaterial` for the `VertexCurve` `.fmat` at the given
/// [curvature], resolving its generated vertex variants from the sidecar's
/// variant map (as the DataAssets loader does), since these scenes build the
/// material by hand.
PreprocessedMaterial _curveMaterial(double curvature) {
  final metadata = (_materialsMetadata!['VertexCurve'] as Map)
      .cast<String, Object?>();
  final vertexMeta = (metadata['vertex'] as Map?)?.cast<String, Object?>();
  final vertexShaders = vertexMeta == null
      ? null
      : <String, gpu.Shader>{
          for (final e in vertexMeta.entries)
            e.key: _materialsLibrary![e.value as String]!,
        };
  return PreprocessedMaterial(
    fragmentShader: _materialsLibrary!['VertexCurve']!,
    metadata: metadata,
    vertexShaders: vertexShaders,
  )..parameters.setFloat('curvature', curvature);
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
  // A custom .fmat material (the unlit toon) compiled by buildMaterials and
  // driven through PreprocessedMaterial. Exercises the whole custom-material
  // path end to end: the build hook, the generated shader, the sidecar, and
  // the type-checked runtime parameters.
  SmokeScene('fmat_toon', () {
    final shader = _materialsLibrary!['FmatToon']!;
    final metadata = (_materialsMetadata!['FmatToon'] as Map)
        .cast<String, Object?>();
    final material = PreprocessedMaterial(
      fragmentShader: shader,
      metadata: metadata,
    );
    material.parameters
      ..setColor('base_color', const Color(0xFFE0A030))
      ..setColor('rim_color', const Color(0xFF40C0FF))
      // Light toward the camera so the banded diffuse reads on the visible
      // faces.
      ..setVec3('light_direction', vm.Vector3(3.0, 2.0, 4.0))
      ..setFloat('band_count', 4.0)
      ..setFloat('ambient', 0.3)
      ..setFloat('rim_strength', 0.4)
      ..setFloat('rim_width', 0.35);
    final scene = Scene();
    scene.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material),
      )..localTransform = vm.Matrix4.rotationY(0.6) * vm.Matrix4.rotationX(0.3),
    );
    return (scene: scene, camera: _camera());
  }),
  // A custom .fmat material with a vertex { } stage: a lit material whose
  // Vertex() hook bends a tessellated plane down with horizontal distance from
  // the camera (the curved-world look). Exercises vertex-shader customization
  // end to end: the generated vertex variant is paired with the fragment and
  // its MaterialParams reach the vertex stage.
  SmokeScene('fmat_vertex_curve', () {
    final material = _curveMaterial(0.022);
    final scene = Scene();
    scene.add(
      Node()..addComponent(
        DirectionalLightComponent(
          DirectionalLight(direction: vm.Vector3(-0.4, -1.0, -0.35)),
        ),
      ),
    );
    // A tessellated plane so the per-vertex bend reads as a smooth curve rather
    // than moving only the corners.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.0, depth: 3.0, segmentsX: 48, segmentsZ: 48),
          material,
        ),
      ),
    );
    return (scene: scene, camera: _shadowCamera());
  }),
  // A vertex-displacing material under a shadow-casting light: a curved ground
  // receiver and a floating caster, both displaced by the curve. Exercises the
  // multi-pass vertex hook: the caster's depth in the shadow map is displaced
  // too, so its shadow lands under the displaced caster on the curved ground
  // rather than detaching to the flat position.
  SmokeScene('fmat_vertex_curve_shadow', () {
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
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.0, depth: 3.0, segmentsX: 48, segmentsZ: 48),
          _curveMaterial(0.02),
        ),
      ),
    );
    // Caster floating above, using the same curve material so it is displaced
    // and casts a shadow from its displaced position.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.6, 0.6, 0.6)),
          _curveMaterial(0.02),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.0, 0)),
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
