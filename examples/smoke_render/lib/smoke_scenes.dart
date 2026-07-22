import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/compressed_texture.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/ktx2_image.dart';
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

/// A deterministic anisotropic Gaussian splat cloud (degree-1 SH) for the
/// splat smoke scene. Built from a fixed seed, so the packed data and the
/// resulting depth sort are identical across runs and backends. Splats form
/// a fuzzy spherical shell so the corners stay the magenta clear.
GaussianSplats _splatCloud() {
  const count = 2500;
  final rng = math.Random(20260705);
  final data = SplatData.zeroed(count, shDegree: 1);
  for (var i = 0; i < count; i++) {
    // A point on a fuzzy spherical shell around the origin.
    final theta = rng.nextDouble() * 2 * math.pi;
    final phi = math.acos(2 * rng.nextDouble() - 1);
    final r = 0.45 + rng.nextDouble() * 0.65;
    final sinPhi = math.sin(phi);
    final p = i * 3, q = i * 4;
    data.positions[p] = r * sinPhi * math.cos(theta);
    data.positions[p + 1] = r * math.cos(phi);
    data.positions[p + 2] = r * sinPhi * math.sin(theta);
    // Anisotropic scales plus a yaw, so the covariance projection and the
    // 2D eigendecomposition see non-circular footprints at varied angles.
    final len = 0.05 + rng.nextDouble() * 0.055;
    data.scales[p] = len * 2.4;
    data.scales[p + 1] = len * 0.8;
    data.scales[p + 2] = len;
    final yaw = rng.nextDouble() * math.pi;
    data.rotations[q + 1] = math.sin(yaw / 2);
    data.rotations[q + 3] = math.cos(yaw / 2);
    // Hue rotation by height for many distinct colors (linear space).
    final h = (data.positions[p + 1] + 1.2) / 2.4;
    data.colors[p] = 0.5 + 0.5 * math.cos(6.28318 * h);
    data.colors[p + 1] = 0.5 + 0.5 * math.cos(6.28318 * (h + 0.33));
    data.colors[p + 2] = 0.5 + 0.5 * math.cos(6.28318 * (h + 0.66));
    data.opacities[i] = 0.55 + rng.nextDouble() * 0.4;
    // A gentle view-dependent tint (degree-1 SH), small so the base color
    // leads. Exercises the SH texture fetch and evaluation branch.
    for (var c = 0; c < 3; c++) {
      for (var ch = 0; ch < 3; ch++) {
        data.sh![(i * 3 + c) * 3 + ch] = (rng.nextDouble() - 0.5) * 0.3;
      }
    }
  }
  return GaussianSplats.fromData(data);
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

/// The skinned animated model preloaded by [loadSmokeModels], so the
/// synchronous [SmokeScene] setup closures can pose and add it.
Node? _skinnedModel;

/// Loads the skinned test model once. Call before pumping the
/// skinned_animation scene.
Future<void> loadSmokeModels() async {
  _skinnedModel ??= await Node.fromGlbAsset('assets_src/two_triangles.glb');
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
  // TODO(gles-swiftshader): the x86_64 SwiftShader GLES stack the Android
  // emulator uses (the CI android_gles job) mis-reads this custom vertex
  // attribute, so the material renders colorless (depth-only) there. It is
  // correct on every other backend: Metal, Vulkan, llvmpipe and ANGLE GLES,
  // WebGL2, and arm64 SwiftShader. Widening the attribute to a vec4 did not
  // help. Investigate the Impeller GLES custom-attribute path and file upstream
  // against SwiftShader if the fault is there.
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
  // A cuboid textured from an in-memory compressed KTX2 payload (mipped and
  // supercompressed), the shape an imported compressed texture takes. Covers
  // the whole compressed-texture path per backend: block encode, the device's
  // per-family transcode (or the rgba8 decode fallback), and the per-level
  // mip-chain upload. Run with --dart-define=SMOKE_FORCE_RGBA8_TEXTURES=true
  // to skip the compressed families and exercise the rgba8 decode fallback
  // (and its mip upload) on a device that supports compression.
  SmokeScene('compressed_texture', () {
    const size = 256;
    if (const bool.fromEnvironment('SMOKE_FORCE_RGBA8_TEXTURES')) {
      compressionFamilyPreference = [];
    }
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = (y * size + x) * 4;
        final checker = ((x >> 3) + (y >> 3)).isEven;
        pixels[i] = checker ? 235 : 30;
        pixels[i + 1] = checker ? 120 : 160;
        pixels[i + 2] = checker ? 40 : 220;
        pixels[i + 3] = 255;
      }
    }
    final texture = gpuTextureFromKtx2Texture(
      encodeImageToKtx2(
        pixels,
        size,
        size,
        generateMips: true,
        supercompress: true,
      ),
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorTexture = GpuTextureSource(texture)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.7
      ..vertexColorWeight = 0.0;
    final scene = Scene();
    scene.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material),
      )..localTransform = vm.Matrix4.rotationY(0.6) * vm.Matrix4.rotationX(0.3),
    );
    return (scene: scene, camera: _camera());
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
    final grid = _phaseGrid();
    scene.add(
      Node(mesh: Mesh(grid, material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.0, 0)),
    );
    // A thick-ribbon wireframe derived from the hero grid through the public
    // readback chain (extractMeshData, extractEdges, LineSegmentsGeometry),
    // floating above it. Covers the segment-expansion vertex shader and the
    // derivation pipeline on every backend within this one scene.
    scene.add(
      Node(
        mesh: Mesh(
          LineSegmentsGeometry(
            grid.extractMeshData().extractEdges(),
            width: 0.02,
            normalOffset: 0.01,
          ),
          UnlitMaterial()..baseColorFactor = vm.Vector4(0.2, 0.9, 1.0, 1.0),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.5, 0)),
    );
    return (scene: scene, camera: _shadowCamera());
  }),
  // Distance fog: a near and a far cuboid, the far one fading toward the fog
  // color, with height fog and sun in-scatter enabled so those branches of
  // ApplyFog run too. Geometry stays central so the corners keep the clear
  // color (the frame-sanity check). One scene covers the global per-fragment
  // fog path across backends.
  SmokeScene('fog', () {
    final scene = Scene();
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..color = vm.Vector3(0.55, 0.62, 0.78)
      ..density = 0.09
      ..height = 0.0
      ..heightFalloff = 0.2
      ..sunInScatter = 0.6
      ..sunInScatterExponent = 6.0
      // Blend the fog color toward the sky sampled in the view direction so the
      // env-sampling fog path is exercised too.
      ..skyColorInfluence = 0.7;
    scene.add(
      Node()..addComponent(
        DirectionalLightComponent(
          DirectionalLight(direction: vm.Vector3(-0.5, -0.4, -0.75)),
        ),
      ),
    );
    // A near cuboid (lightly fogged) and a far one (heavily fogged toward the
    // fog color), so the fog gradient is a clear visual-diff signal while the
    // corners stay the magenta clear.
    scene.add(_cuboid(vm.Vector4(0.85, 0.85, 0.88, 1.0), 0.0, 0.6));
    scene.add(
      _cuboid(vm.Vector4(0.85, 0.85, 0.88, 1.0), 0.0, 0.6)
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(-1.4, 0, -12)) *
            vm.Matrix4.rotationY(0.6) *
            vm.Matrix4.rotationX(0.3),
    );
    return (scene: scene, camera: _camera());
  }),
  // Auto exposure pinned at its upper clamp: the mostly-empty background
  // meters far below the reference luminance, so the adapted factor lands on
  // exp2(maxEv) during the startup snap frames and holds there on every
  // later frame, deterministically brightening the dimly-lit cuboid. Covers
  // the whole chain (seed, downsample, adaptation, resolve composite) with a
  // clamp-pinned value that is robust to small cross-backend metering
  // differences.
  SmokeScene('auto_exposure', () {
    final scene = Scene();
    scene.environmentIntensity = 0.4;
    scene.autoExposure.enabled = true;
    scene.add(_cuboid(vm.Vector4(0.30, 0.60, 0.85, 1.0), 0.0, 0.5));
    return (scene: scene, camera: _camera());
  }),
  // A procedural anisotropic splat cloud (degree-1 SH) composited around an
  // opaque cuboid, with a crop box carving one side. One scene covers the
  // splat path across backends, the vertex-stage data texture fetch, the EWA
  // covariance projection and 2D eigendecomposition, the background depth
  // sort, premultiplied translucent blending over opaque geometry, the SH
  // texture fetch and evaluation, and the crop branch. The surrounding
  // cuboid exercises the splat/mesh depth composite (occlusion both ways).
  SmokeScene('gaussian_splats', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.85, 0.75, 0.20, 1.0), 0.1, 0.5));
    final splats = SplatComponent(_splatCloud())
      // Exclude a slab off the -x side, so the crop branch culls real splats
      // while the central coverage the frame-sanity check samples stays high.
      ..setCropBox(
        vm.Matrix4.compose(
          vm.Vector3(-1.25, 0, 0),
          vm.Quaternion.identity(),
          vm.Vector3(0.6, 2.0, 2.0),
        ),
        mode: SplatCropMode.exclude,
      );
    scene.add(Node()..addComponent(splats));
    return (scene: scene, camera: _camera());
  }),
  // A skinned mesh (two bone-driven triangles) posed by seeking a paused
  // animation clip to a fixed mid-swing time, so the deformation is
  // deterministic. The only scene that draws through the skinned vertex
  // shader, whose joints texture rides in the vertex stage on top of the lit
  // fragment shader's full sampler set. On GLES that combination overflows
  // the per-stage texture-unit validation on drivers reporting the minimum
  // 16 fragment units (the skinned-draw crash on Windows ANGLE), so this
  // scene reproduces that crash on CI's GLES backends.
  SmokeScene('skinned_animation', () {
    final scene = Scene();
    final model = _skinnedModel!;
    scene.add(model);
    model
        .createAnimationClip(model.findAnimationByName('Metronome')!)
        .seek(0.4);
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0.8, 2.0, -6.5),
        target: vm.Vector3(0, 1.5, 0),
      ),
    );
  }),
];

/// Renders one [SmokeScene] into a fixed-size [RepaintBoundary] over the
/// magenta clear.
/// The CPU/GPU noise parity probe (see `assets/noise_parity.fmat`). Not part
/// of [kSmokeScenes]; its test samples decoded pixel values numerically
/// instead of uploading a screenshot, so the frame never reaches the visual
/// diff service. Tone mapping and anti-aliasing are configured so the packed
/// bytes survive the display encode exactly.
({Scene scene, PerspectiveCamera camera}) buildNoiseParityScene() {
  final scene = Scene()
    ..toneMapping = ToneMappingMode.linear
    ..antiAliasingMode = AntiAliasingMode.none;
  // A camera-facing quad spanning world [-1, 1] in x/y; the material derives
  // its tile grid from world position, so no texture coordinates are needed.
  final quad = MeshGeometry.fromArrays(
    positions: Float32List.fromList([
      -1, -1, 0, 1, -1, 0, 1, 1, 0, //
      -1, -1, 0, 1, 1, 0, -1, 1, 0,
    ]),
  );
  scene.add(Node(mesh: Mesh(quad, _fmatMaterial('NoiseParity'))));
  // 45-degree vertical FOV at distance 2.6 sees a half-height of ~1.08, so
  // the quad fits with a small margin; the marker scan derives the tile
  // mapping from the frame, so exact framing does not matter.
  return (
    scene: scene,
    camera: PerspectiveCamera(
      position: vm.Vector3(0, 0, -2.6),
      target: vm.Vector3.zero(),
    ),
  );
}

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
