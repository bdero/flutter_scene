import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/radiance_layout.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/compressed_texture.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/half_float.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:smoke_render/synthetic_morph_glb.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Side length of the captured render, in logical pixels. Fixed for
/// determinism (independent of window size).
const int kSmokeSize = 512;

/// Distinctive background behind the scene so the sanity assertions can tell
/// rendered geometry from empty space.
const Color kSmokeClear = Color(0xFFFF00FF); // magenta

/// Key on the [RepaintBoundary] wrapping the scene, used by the integration
/// test to capture the rendered frame.
final GlobalKey smokeSceneKey = GlobalKey();

/// A deterministic smoke scene: a builder that produces a [Scene] and the
/// camera to view it from. No animation, no wall-clock input.
class SmokeScene {
  const SmokeScene(
    this.id,
    this.setup, {
    this.preload,
    this.warmupFrames = 0,
    this.fullCoverage = false,
  });

  final String id;
  final ({Scene scene, PerspectiveCamera camera}) Function() setup;
  final Future<void> Function()? preload;

  /// Frames to render before the capture, for a feature that converges over
  /// time instead of resolving in one frame.
  ///
  /// The capture loop always pumps its own settling frames, so this only
  /// raises the count. It is deterministic despite running on wall-clock
  /// time because every temporal blend here clamps its rate exponent at a
  /// 60 Hz cadence, and the smoke lanes render well below that.
  final int warmupFrames;

  /// Whether the scene geometry completely covers the viewport, meaning corners
  /// are geometry rather than the background clear color.
  final bool fullCoverage;
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

Node _directionalLightNode(vm.Vector3 direction, DirectionalLight light) =>
    Node()..addComponent(DirectionalLightComponent.aimed(light, direction));

void _configureAmbientOcclusion(Scene scene) {
  scene.ambientOcclusion
    ..enabled = true
    ..radius = 1.0
    ..bias = 0.0
    ..horizonAngle = 0.06
    ..intensity = 1.5
    ..power = 1.5
    ..detail = 0.5
    ..directLightAffect = 0.59
    ..sampleCount = 24
    ..halfResolution = false
    ..depthMipChain = true;
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
PhysicallyBasedMaterial? _layeredPhysicalMaterial;
PhysicallyBasedMaterial? _transmissionPhysicalMaterial;

/// Loads the `buildMaterials` output (bundle plus parameter sidecar) once. Call
/// before pumping a scene that uses a custom material.
Future<void> loadSmokeMaterials() async {
  if (_materialsLibrary != null) return;
  // These scenes build their materials by hand, so they resolve the compiled
  // bundle and its sidecar through the registry instead of loadFmatMaterial.
  final index = (await FmatMaterialRegistry.load())
      .resolve('assets/custom_material.fmat')
      .index;
  _materialsLibrary = await gpu.loadShaderLibraryAsync(
    index.shaderBundleAssetKey,
  );
  final sidecar = await rootBundle.loadString(index.sidecarAssetKey);
  _materialsMetadata = (jsonDecode(sidecar) as Map).cast<String, Object?>();
  _rawPairLibrary = await gpu.loadShaderLibraryAsync(
    await gpu.resolveShaderBundleKey('smoke'),
  );
  _layeredPhysicalMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.45, 0.08, 0.03, 1.0)
    ..metallicFactor = 0.1
    ..roughnessFactor = 0.45
    ..clearcoat = 0.9
    ..clearcoatRoughness = 0.12
    ..sheenColor = vm.Vector4(0.35, 0.08, 0.03, 1.0)
    ..sheenRoughness = 0.35
    ..anisotropy = 0.55
    ..anisotropyRotation = 0.4
    ..iridescence = 0.35
    ..iridescenceThicknessMinimum = 180.0
    ..iridescenceThicknessMaximum = 360.0;
  _transmissionPhysicalMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.72, 0.92, 1.0, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.08
    ..transmission = 0.78
    ..ior = 1.45
    ..thickness = 0.7
    ..attenuationColor = vm.Vector4(0.55, 0.85, 1.0, 1.0)
    ..attenuationDistance = 2.5
    ..dispersion = 0.25;
}

/// The hand-written shader pair pre-loaded by [loadSmokeMaterials], so the
/// synchronous scene setup can build a [ShaderMaterial] from both stages.
gpu.ShaderLibrary? _rawPairLibrary;

/// Builds a `PreprocessedMaterial` for the named `.fmat`, resolving its
/// generated vertex variants from the sidecar's variant map (as
/// `loadFmatMaterial` does), since these scenes build the material by hand.
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
    radianceCubeFragmentShader: _materialsLibrary!['${name}Cube'],
    metadata: metadata,
    vertexShaders: vertexShaders,
  );
}

/// The pre-baked environment preloaded by [loadPrebakedIbl].
EnvironmentMap? _prebakedIblEnvironment;

/// Linear radiance the pre-baked cubemap fixture fills [face] with at [level].
///
/// Six saturated hues, one per face, so a face-order or handedness mistake
/// puts a visibly wrong color in the reflection. The level ladder dims each
/// step of the roughness chain, so a mip-to-roughness mistake reads as the
/// wrong brightness on the wrong sphere.
vm.Vector3 _iblFaceColor(int face, int level) {
  final base = switch (face) {
    0 => vm.Vector3(1.60, 0.07, 0.07), // +X red
    1 => vm.Vector3(0.07, 1.15, 1.50), // -X cyan
    2 => vm.Vector3(1.60, 1.45, 0.45), // +Y warm white
    3 => vm.Vector3(0.05, 0.09, 0.60), // -Y deep blue
    4 => vm.Vector3(0.08, 1.30, 0.12), // +Z green
    _ => vm.Vector3(1.55, 0.60, 0.07), // -Z orange
  };
  return base * (1.0 - level * 0.1);
}

/// The L2 basis of `diffuse_sh.dart`, transcribed so the fixture's projection
/// lands in the domain the shader evaluates.
Float64List _shBasis(vm.Vector3 d) => Float64List.fromList([
  0.282095,
  0.488603 * d.y,
  0.488603 * d.z,
  0.488603 * d.x,
  1.092548 * d.x * d.y,
  1.092548 * d.y * d.z,
  0.315392 * (3.0 * d.z * d.z - 1.0),
  1.092548 * d.x * d.z,
  0.546274 * (d.x * d.x - d.y * d.y),
]);

/// Projects the fixture's base level onto the engine's irradiance-domain
/// spherical harmonics, so the diffuse ambient carries the same per-face
/// colors the reflections do.
List<vm.Vector3> _iblDiffuseSh() {
  const samples = 16; // per face axis
  // Lambertian band factors over pi (A_l / pi), the convention the shader's
  // coefficients already fold in.
  const bandFactor = <double>[
    1.0,
    2.0 / 3.0,
    2.0 / 3.0,
    2.0 / 3.0,
    0.25,
    0.25,
    0.25,
    0.25,
    0.25,
  ];
  final sh = [
    for (var i = 0; i < kDiffuseShCoefficientCount; i++) vm.Vector3.zero(),
  ];
  var weightSum = 0.0;
  for (var face = 0; face < 6; face++) {
    final radiance = _iblFaceColor(face, 0);
    for (var y = 0; y < samples; y++) {
      for (var x = 0; x < samples; x++) {
        final u = (x + 0.5) / samples, v = (y + 0.5) / samples;
        final s = 2.0 * u - 1.0, t = 2.0 * v - 1.0;
        // A cube texel's solid angle, falling off with the cube-to-sphere
        // stretch; summed over all six faces it integrates to 4 pi.
        final weight = math.pow(1.0 + s * s + t * t, -1.5).toDouble();
        weightSum += weight;
        final basis = _shBasis(radianceCubeFaceDirection(face, u, v));
        for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
          sh[i].addScaled(radiance, basis[i] * weight);
        }
      }
    }
  }
  final norm = 4.0 * math.pi / weightSum;
  for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
    sh[i].scale(norm * bandFactor[i]);
  }
  return sh;
}

/// The pre-baked environment fixture: a KTX2 float16 cubemap whose eight mip
/// levels are the engine's eight roughness bands, plus the diffuse
/// coefficients in the file's own key/value metadata.
///
/// Built here rather than committed. The smallest face size the radiance
/// layout accepts is [kMinRadianceCubeSize], so even a solid-color bake is a
/// few megabytes of binary, and the engine ships no supercompressor to shrink
/// it. Generating it with the engine's own KTX2 writer keeps the provenance in
/// one readable place, the way the compressed_texture scene builds its payload.
///
/// TODO(ibl-ktx2-zstd): the payload is stored uncompressed, so the loader's
/// zstd supercompression branch goes unrendered. Emit the levels zstd-framed
/// once the engine carries a compressor (it ships only the decoder today),
/// which also shrinks the fixture enough to commit as a file.
Uint8List _prebakedIblKtx2() {
  const size = kMinRadianceCubeSize;
  const vkFormatRgba16Sfloat = 97;
  final levels = <Ktx2Level>[];
  for (var level = 0; level < kPrefilterBandCount; level++) {
    final levelSize = math.max(1, size >> level);
    final texels = levelSize * levelSize;
    final payload = Uint8List(texels * 8 * 6);
    final view = ByteData.sublistView(payload);
    final alpha = floatToHalfBits(1.0);
    for (var face = 0; face < 6; face++) {
      final rgb = _iblFaceColor(face, level);
      final r = floatToHalfBits(rgb.x);
      final g = floatToHalfBits(rgb.y);
      final b = floatToHalfBits(rgb.z);
      var offset = face * texels * 8;
      for (var i = 0; i < texels; i++) {
        view.setUint16(offset, r, Endian.little);
        view.setUint16(offset + 2, g, Endian.little);
        view.setUint16(offset + 4, b, Endian.little);
        view.setUint16(offset + 6, alpha, Endian.little);
        offset += 8;
      }
    }
    levels.add(Ktx2Level(data: payload));
  }
  return writeKtx2(
    Ktx2Texture(
      vkFormat: vkFormatRgba16Sfloat,
      typeSize: 2,
      pixelWidth: size,
      pixelHeight: size,
      faceCount: 6,
      levels: levels,
      keyValues: {kDiffuseShKtx2Key: encodeDiffuseShSidecar(_iblDiffuseSh())},
      levelAlignment: 4,
    ),
  );
}

/// Loads the pre-baked environment once. Call before pumping the prebaked_ibl
/// scene.
Future<void> loadPrebakedIbl() async {
  _prebakedIblEnvironment ??= await EnvironmentMap.fromKtx2Bytes(
    _prebakedIblKtx2(),
  );
}

/// A camera-facing unit quad carrying a UV1 set, the channel a lightmap
/// samples by default.
MeshGeometry _lightmapQuad() => MeshGeometry.fromArrays(
  positions: Float32List.fromList([
    -0.5, -0.5, 0, //
    0.5, -0.5, 0,
    0.5, 0.5, 0,
    -0.5, 0.5, 0,
  ]),
  normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
  texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
  texCoords1: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
  indices: <int>[0, 1, 2, 0, 2, 3],
);

/// Lightmaps sample raw linear radiance, so no mip chain (which would average
/// an RGBM alpha into nonsense) and no wrap at the edges.
const TextureSampling _lightmapSampling = TextureSampling(
  mipmaps: false,
  addressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// A low-dynamic-range bake: a two-axis radiance gradient with a checker in
/// blue, so a swapped UV axis, the wrong UV set, or a dropped intensity are
/// all visible at a glance.
Texture2D _gradientLightmap() {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final u = x / (size - 1), v = y / (size - 1);
      pixels[i] = (30 + 210 * u).round();
      pixels[i + 1] = (30 + 210 * (1.0 - v)).round();
      pixels[i + 2] = ((x >> 3) + (y >> 3)).isEven ? 220 : 50;
      pixels[i + 3] = 255;
    }
  }
  return Texture2D.fromPixels(
    pixels,
    size,
    size,
    content: TextureContent.data,
    sampling: _lightmapSampling,
  );
}

/// A high-dynamic-range bake packed as RGBM, a radial hot spot peaking well
/// above 1.0. Only the decode branch can bring the core back, so a material
/// that reads it as plain linear radiance renders a dim, flat patch.
Texture2D _rgbmLightmap() {
  const size = 64;
  // The decode the lightmap shader applies is rgb * pow(a, 2.2) * 34.4932.
  const range = 34.4932;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final dx = x / (size - 1) - 0.5, dy = y / (size - 1) - 0.5;
      final falloff = math.exp(-24.0 * (dx * dx + dy * dy));
      final radiance = vm.Vector3(0.16, 0.10, 0.06)
        ..addScaled(vm.Vector3(3.2, 2.1, 0.9), falloff);
      final peak = math.max(math.max(radiance.x, radiance.y), radiance.z);
      // Quantize alpha upward so the reconstructed scale never clips a channel.
      final alpha = (math.pow(peak / range, 1.0 / 2.2) * 255.0).ceil().clamp(
        1,
        255,
      );
      final scale = math.pow(alpha / 255.0, 2.2).toDouble() * range;
      pixels[i] = (radiance.x / scale * 255.0).round().clamp(0, 255);
      pixels[i + 1] = (radiance.y / scale * 255.0).round().clamp(0, 255);
      pixels[i + 2] = (radiance.z / scale * 255.0).round().clamp(0, 255);
      pixels[i + 3] = alpha;
    }
  }
  return Texture2D.fromPixels(
    pixels,
    size,
    size,
    content: TextureContent.data,
    sampling: _lightmapSampling,
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

/// The skinned and morphed model preloaded by [loadMorphSkinnedModel], plus
/// the same model at rest weights beside it as the reference.
Node? _morphSkinnedModel;
Node? _morphSkinnedRest;

/// Imports the synthetic skinned and morphed GLB and pins its morph weights.
/// The bytes are built in code (see `synthetic_morph_glb.dart`), so the scene
/// needs no committed fixture. The clone keeps every weight at zero, so both
/// copies share one geometry and differ only by the morph blend.
Future<void> loadMorphSkinnedModel() async {
  if (_morphSkinnedModel != null) return;
  final model = await Node.fromGlbBytes(buildMorphSkinnedGlb());
  final rest = model.clone();
  rest.meshNodes.first.setMorphWeights(const [0.0, 0.0, 0.0]);
  final meshNode = model.meshNodes.first;
  meshNode.setMorphWeights(kMorphSkinnedWeights);
  final geometry = meshNode.mesh!.primitives.first.geometry;
  if (geometry is! MorphedSkinnedGeometry || !geometry.usesGpuMorphing) {
    throw StateError(
      'morph_skinned expects GPU-morphed skinned geometry, got '
      '${geometry.runtimeType}',
    );
  }
  _morphSkinnedRest = rest;
  _morphSkinnedModel = model;
}

/// The Draco-compressed KTX2-textured quads preloaded by [loadBasisuQuads].
Node? _basisuQuads;

/// Imports the compressed quads once. Call before pumping the basisu_textures
/// scene.
Future<void> loadBasisuQuads() async {
  _basisuQuads ??= await Node.fromGlbAsset('assets/basisu_quads_draco.glb');
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

class _NormalsProbePass extends CustomRenderPass {
  @override
  String get name => 'normals_probe';

  @override
  RenderStage get stage => RenderStage.afterScene;

  @override
  Set<RenderInput> get inputs => const {RenderInput.normals};

  @override
  void execute(RenderPassContext context) {}
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
  // Exercises the full-layout camera depth prepass requested by a custom
  // normals consumer. The matching plain meshes collapse into one synthetic
  // instanced draw.
  SmokeScene('depth_post', () {
    final scene = Scene();
    scene.depthOfField
      ..enabled = true
      ..focusDistance = 5.0
      ..fStop = 5.6
      ..quality = DepthOfFieldQuality.low;
    scene.addRenderPass(_NormalsProbePass());
    final geometry = CuboidGeometry(vm.Vector3(0.65, 0.65, 0.65));
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.25, 0.65, 0.90, 1.0)
      ..metallicFactor = 0.1
      ..roughnessFactor = 0.5
      ..vertexColorWeight = 0.0;
    for (var i = -1; i <= 1; i++) {
      scene.add(
        Node(mesh: Mesh(geometry, material))
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(i * 0.85, i.abs() * -0.25, i * -0.2),
          ),
      );
    }
    return (scene: scene, camera: _camera());
  }),
  // AO over broad surfaces with contact continuing through both horizontal
  // edges. This catches screen-axis bands and viewport-edge discontinuities.
  SmokeScene('ambient_occlusion_edge', () {
    final scene = Scene();
    _configureAmbientOcclusion(scene);
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.78, 0.76, 0.72, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 8.0, depth: 2.4), material))
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0, 0, -1.0)) *
            vm.Matrix4.rotationX(math.pi * 0.5),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(8.0, 0.35, 0.35)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.72, -0.82)),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0, 4.0),
        target: vm.Vector3(0, 0, -1.0),
      ),
    );
  }),
  // The ground-truth occlusion method with the visibility bitmask and
  // multi-bounce enabled. Exercises the horizon-slice shader, the uint
  // bitfield path (including the manual popcount on GLES/WebGL2), and the
  // albedo-tinted bounce in the material shader. A thin bar over a plane
  // checks the constant-thickness occluder model.
  SmokeScene('ambient_occlusion_gtao', () {
    final scene = Scene();
    _configureAmbientOcclusion(scene);
    scene.ambientOcclusion
      ..method = AmbientOcclusionMethod.groundTruth
      ..radius = 0.6
      ..intensity = 1.5
      ..sliceCount = 3
      ..stepsPerSlice = 6
      ..visibilityBitmask = true
      ..thickness = 0.35
      ..multiBounce = 1.0;
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.72, 0.5, 0.34, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 8.0, depth: 2.4), material))
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0, 0, -1.0)) *
            vm.Matrix4.rotationX(math.pi * 0.5),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(3.0, 0.12, 0.12)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.6, -0.9)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.8, 0.8, 0.8)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-1.6, -0.5, -1.1)),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0.4, 4.0),
        target: vm.Vector3(0, -0.2, -1.0),
      ),
    );
  }),
  // Screen-space indirect light: a sunlit red wall beside a white floor and
  // cuboid. The bitmask gather must bleed red bounce onto the floor and the
  // cuboid's wall-facing side. Guards the fp16 chain, the sector-delta
  // radiance credit, and the material composite across backends.
  SmokeScene('ssgi', () {
    final scene = Scene();
    scene.environmentIntensity = 0.15;
    scene.ambientOcclusion
      ..enabled = true
      ..method = AmbientOcclusionMethod.groundTruth
      ..radius = 1.4
      ..intensity = 1.0
      ..sliceCount = 3
      ..stepsPerSlice = 6
      ..visibilityBitmask = true
      ..thickness = 0.4
      ..indirectLight = 8.0
      ..halfResolution = false
      ..depthMipChain = true;
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.85, -0.7, 0.25),
        DirectionalLight(intensity: 3.0),
      ),
    );
    final white = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.85, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    final red = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.9, 0.05, 0.03, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 2.8, depth: 2.2), white)));
    // The red wall stands on the -x side, its sunlit face toward the floor.
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.2, 1.6, 2.2)), red))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-1.4, 0.8, 0)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.7, 0.9, 0.7)), white))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-0.3, 0.45, 0.2)),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(2.4, 2.3, 3.8),
        target: vm.Vector3(-0.45, 0.35, 0),
      ),
    );
  }),
  // Rect area lights via linearly transformed cosines: a warm wide panel and
  // a cool tall panel over a glossy plane. Guards the LTC atlas tiles, the
  // edge integration, and the stretched panel reflections across backends.
  // The world-space irradiance field, in the rig that makes bounce light
  // unmistakable: a small white room with an emissive red wall on one side
  // and an emissive green wall on the other, a white occluder between them,
  // and a dim key light so the room reads. Every colored texel on the white
  // floor and ceiling arrived through the probe field.
  //
  // The room is deliberately small relative to the probe spacing. Screen-space
  // injection only reaches the eight probes of the cell a surface sits in, so
  // a wall lights the probes within about a cell of it and spreads outward one
  // cell per frame through the scene-color feedback. That near-field reach is
  // what this scene measures; a bake is what fills a large room's interior.
  //
  // The walls are solids thicker than a probe spacing, per the field's content
  // rule.
  SmokeScene(
    'irradiance_field',
    () {
      final scene = Scene();
      // Nearly no environment light, so the colored term is the field's.
      scene.environmentIntensity = 0.02;
      scene.exposure = 1.3;
      scene.globalIllumination
        ..enabled = true
        ..volumeMode = IrradianceVolumeMode.fitScene
        ..resolution = vm.Vector3(10, 6, 10)
        ..intensity = 1.0
        ..hysteresis = 0.85
        ..visibility = 0.5
        ..injectionResolution = IrradianceInjectionResolution.quarter;
      scene.add(
        _directionalLightNode(
          vm.Vector3(0.1, -0.85, -0.5),
          DirectionalLight(intensity: 1.6),
        ),
      );
      PhysicallyBasedMaterial matte(
        double r,
        double g,
        double b, {
        vm.Vector4? emissive,
      }) => PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(r, g, b, 1.0)
        ..emissiveFactor = emissive ?? vm.Vector4.zero()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.95
        ..vertexColorWeight = 0.0;
      final white = matte(0.85, 0.85, 0.85);
      void box(vm.Vector3 size, vm.Vector3 at, PhysicallyBasedMaterial m) {
        scene.add(
          Node(mesh: Mesh(CuboidGeometry(size), m))
            ..localTransform = vm.Matrix4.translation(at),
        );
      }

      box(vm.Vector3(3.4, 0.3, 3.4), vm.Vector3(0, -0.15, 0), white);
      box(vm.Vector3(3.4, 2.0, 0.3), vm.Vector3(0, 1.0, -1.65), white);
      box(
        vm.Vector3(0.3, 2.0, 3.4),
        vm.Vector3(-1.65, 1.0, 0),
        matte(0.02, 0.02, 0.02, emissive: vm.Vector4(14.0, 0.45, 0.3, 1.0)),
      );
      box(
        vm.Vector3(0.3, 2.0, 3.4),
        vm.Vector3(1.65, 1.0, 0),
        matte(0.02, 0.02, 0.02, emissive: vm.Vector4(0.15, 4.0, 0.28, 1.0)),
      );
      box(vm.Vector3(0.7, 1.1, 1.1), vm.Vector3(0, 0.55, -0.2), white);
      return (
        scene: scene,
        camera: PerspectiveCamera(
          position: vm.Vector3(0, 2.4, 4.9),
          target: vm.Vector3(0, 0.35, 0),
        ),
      );
    },
    // The field converges over frames, and its first frame has no scene-color
    // history to scatter from.
    warmupFrames: 45,
  ),
  SmokeScene(
    'taa',
    () {
      final scene = Scene();
      scene.antiAliasingMode = AntiAliasingMode.taa;
      scene.temporalAntiAliasing
        ..sharpness = 0.4
        ..jitterScale = 1.0;
      scene.environmentIntensity = 0.4;
      final sphere = SphereGeometry(radius: 1.0);
      final shiny = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.9, 0.2, 0.2, 1.0)
        ..metallicFactor = 0.9
        ..roughnessFactor = 0.1;
      scene.add(Node(mesh: Mesh(sphere, shiny)));
      scene.add(
        _directionalLightNode(
          vm.Vector3(-0.4, -0.9, -0.3),
          DirectionalLight(intensity: 3.0),
        ),
      );
      return (
        scene: scene,
        camera: PerspectiveCamera(
          position: vm.Vector3(0, 1.2, 2.8),
          target: vm.Vector3(0, 0, 0),
        ),
      );
    },
    warmupFrames: 16,
    fullCoverage: true,
  ),
  SmokeScene('area_light', () {
    final scene = Scene();
    scene.environmentIntensity = 0.05;
    // Aims a node's local +Z (the panel emission axis) at [target].
    vm.Matrix4 aim(vm.Vector3 position, vm.Vector3 target) {
      final forward = (target - position).normalized();
      final right = vm.Vector3(0, 1, 0).cross(forward)..normalize();
      final up = forward.cross(right).normalized();
      return vm.Matrix4.columns(
        vm.Vector4(right.x, right.y, right.z, 0),
        vm.Vector4(up.x, up.y, up.z, 0),
        vm.Vector4(forward.x, forward.y, forward.z, 0),
        vm.Vector4(position.x, position.y, position.z, 1),
      );
    }

    final floor = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.08, 0.09, 1.0)
      ..metallicFactor = 0.3
      ..roughnessFactor = 0.2
      ..vertexColorWeight = 0.0;
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 4.4, depth: 3.4), floor)));
    final subject = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.8, 0.78, 0.75, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.4
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.7, 0.9, 0.7)), subject))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.45, 0)),
    );
    scene.add(
      Node()
        ..addComponent(
          RectAreaLightComponent(
            RectAreaLight(
              color: vm.Vector3(1.0, 0.7, 0.4),
              intensity: 8.0,
              width: 1.6,
              height: 1.0,
            ),
          ),
        )
        ..localTransform = aim(
          vm.Vector3(-1.4, 1.3, 1.0),
          vm.Vector3(0, 0.45, 0),
        ),
    );
    scene.add(
      Node()
        ..addComponent(
          RectAreaLightComponent(
            RectAreaLight(
              color: vm.Vector3(0.35, 0.55, 1.0),
              intensity: 6.0,
              width: 0.4,
              height: 1.8,
            ),
          ),
        )
        ..localTransform = aim(
          vm.Vector3(1.5, 1.1, -0.6),
          vm.Vector3(0, 0.45, 0),
        ),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 1.6, 3.6),
        target: vm.Vector3(0, 0.4, 0),
      ),
    );
  }),
  // Percentage-closer soft shadows plus screen-space contact shadows. The
  // tall pillar's shadow must sharpen at its base and widen with distance
  // (the PCSS blocker search), and the floating slab must catch a soft
  // screen-space contact patch beneath its near edge. Guards the blocker
  // search, the penumbra scaling, and the contact march across backends.
  SmokeScene('soft_shadows', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.55, -1.0, -0.3),
        DirectionalLight(
          castsShadow: true,
          shadowMaxDistance: 20.0,
          shadowFilter: DirectionalShadowFilter.pcss,
          angularRadius: 0.025,
          shadowSoftness: 0.28,
          contactShadows: true,
          contactShadowDistance: 0.6,
        ),
      ),
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.74, 0.70, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 4.0, depth: 3.2), material)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.16, 2.2, 0.16)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-0.5, 1.1, 0.2)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.1, 0.12, 0.8)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0.7, 0.1, -0.4)),
    );
    // Framed farther back than _shadowCamera: the plane here is wider, and
    // the narrow Android capture (412x512) otherwise crops the corners onto
    // it, tripping the corners-clear sanity check.
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(3.3, 3.1, 3.8),
        target: vm.Vector3(0, 0.2, 0),
      ),
    );
  }),
  // SMAA 1x over thin rotated bars, the classic aliasing torture test. The
  // edges must resolve smooth (not stair-stepped like none, not smeared
  // like fxaa). Guards the three-pass chain and the area/search texture
  // load across backends.
  SmokeScene('smaa', () {
    final scene = Scene();
    scene.antiAliasingMode = AntiAliasingMode.smaa;
    final dark = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.05, 0.05, 0.07, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.8
      ..vertexColorWeight = 0.0;
    final bright = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.92, 0.92, 0.9, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 3.4, depth: 2.8), bright)));
    for (var i = 0; i < 5; i++) {
      scene.add(
        Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.6, 0.03, 0.05)), dark))
          ..localTransform =
              vm.Matrix4.translation(vm.Vector3(0, 0.25 + i * 0.24, 0)) *
              vm.Matrix4.rotationY(0.35) *
              vm.Matrix4.rotationZ(0.04 + i * 0.05),
      );
    }
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0.5, 1.3, 4.0),
        target: vm.Vector3(0, 0.7, 0),
      ),
    );
  }),
  // A reflection probe inside a three-walled colored room: the glossy
  // centerpiece must mirror the correct wall color on each face (the
  // parallax-corrected box projection), not the studio environment.
  // Guards the scene capture, the prefilter of the captured cube, and the
  // probe cross-fade across backends.
  SmokeScene('reflection_probe', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.3, -1.0, -0.4),
        DirectionalLight(intensity: 2.0),
      ),
    );
    PhysicallyBasedMaterial wall(double r, double g, double b) =>
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(r, g, b, 1.0)
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.9
          ..vertexColorWeight = 0.0;
    // Floor and three walls (left red, right blue, back green).
    scene.add(
      Node(
        mesh: Mesh(PlaneGeometry(width: 4.0, depth: 4.0), wall(0.7, 0.7, 0.7)),
      ),
    );
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.1, 2.4, 4.0)),
          wall(0.8, 0.05, 0.05),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(-2.0, 1.2, 0)),
    );
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.1, 2.4, 4.0)),
          wall(0.05, 0.05, 0.8),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(2.0, 1.2, 0)),
    );
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(4.0, 2.4, 0.1)),
          wall(0.05, 0.7, 0.05),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.2, -2.0)),
    );
    // The glossy centerpiece reflecting the room through the probe.
    final mirror = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.95, 0.95, 1.0)
      ..metallicFactor = 1.0
      ..roughnessFactor = 0.08
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(SphereGeometry(radius: 0.55), mirror))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.8, 0.3)),
    );
    // The influence box stretches to include the exterior camera so the
    // probe fully applies; the parallax projection stays close enough to
    // the room that each wall color lands on the correct sphere face.
    scene.add(
      Node()
        ..addComponent(
          ReflectionProbeComponent(
            extents: vm.Vector3(2.5, 2.0, 4.6),
            blendDistance: 2.0,
          ),
        )
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.2, 1.5)),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0.5, 2.0, 6.0),
        target: vm.Vector3(0, 1.0, 0),
      ),
    );
  }),
  // A mirror floor driven by a PlanarReflectorComponent, reflecting an
  // L-shaped run of differently colored boxes capped by a cone. The
  // arrangement is asymmetric in both floor axes, so a handedness or
  // orientation error in the capture puts the wrong color on the wrong side
  // or stands the reflection upright. One reflection group at a pinned
  // capture scale.
  SmokeScene('planar_mirror', () {
    final scene = Scene();
    // The mirror surface goes fully rough under a live capture, so ambient
    // and sun both flatten it toward grey. Keep them low and make the
    // subjects emissive instead, since emission never reaches the floor
    // directly and the reflection is left to light it.
    scene.environmentIntensity = 0.18;
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.35, -1.0, -0.4),
        DirectionalLight(intensity: 1.0),
      ),
    );
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 4.6, depth: 4.6),
          _fmatMaterial('PlanarMirror')
            ..parameters.setFloat('reflectivity', 1.0),
        ),
      )..addComponent(
        PlanarReflectorComponent(resolutionScale: 0.5, reflectionGroupId: 0),
      ),
    );
    PhysicallyBasedMaterial subject(vm.Vector4 color) =>
        PhysicallyBasedMaterial()
          ..baseColorFactor = color
          ..emissiveFactor = color
          ..emissiveStrength = 1.6
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.4
          ..vertexColorWeight = 0.0;
    Node box(vm.Vector3 position, vm.Vector4 color) => Node(
      mesh: Mesh(CuboidGeometry(vm.Vector3(0.62, 0.62, 0.62)), subject(color)),
    )..localTransform = vm.Matrix4.translation(position);
    // The L's long arm runs across the floor in x, its short arm forward in z
    // off the left end, so left/right and near/far are both distinguishable.
    scene.add(
      box(vm.Vector3(-1.1, 0.32, -0.85), vm.Vector4(0.90, 0.20, 0.16, 1)),
    );
    scene.add(
      box(vm.Vector3(-0.2, 0.32, -0.85), vm.Vector4(0.20, 0.75, 0.30, 1)),
    );
    scene.add(
      box(vm.Vector3(0.7, 0.32, -0.85), vm.Vector4(0.20, 0.42, 0.95, 1)),
    );
    scene.add(
      box(vm.Vector3(-1.1, 0.32, 0.05), vm.Vector4(0.95, 0.78, 0.18, 1)),
    );
    // The cone caps the short arm, a silhouette a flipped capture cannot
    // disguise as a box.
    scene.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(bottomRadius: 0.3, topRadius: 0.0, height: 0.8),
          subject(vm.Vector4(0.95, 0.95, 0.97, 1)),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(-1.1, 0.4, 0.95)),
    );
    return (
      scene: scene,
      // A diagonal view down the L's bisector, so its two arms run to
      // opposite sides of the frame instead of stacking into one row.
      camera: PerspectiveCamera(
        position: vm.Vector3(-4.2, 2.8, 4.2),
        target: vm.Vector3(-0.2, 0.4, 0.05),
      ),
    );
  }, preload: loadSmokeMaterials),
  // Lens flares off the bloom chain: a single intense emissive card in a
  // dim scene must bloom and cast a ghost chain through the screen center
  // plus a halo ring. Guards the whole bloom pyramid (its only golden) and
  // the flare ghost/halo/dispersion math across backends.
  SmokeScene('lens_flare', () {
    final scene = Scene();
    scene.environmentIntensity = 0.05;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 1.0
      ..intensity = 0.5
      ..scatter = 0.6;
    scene.postProcess.bloom.lensFlare
      ..enabled = true
      ..intensity = 1.0
      ..ghostCount = 5
      ..ghostSpacing = 0.35
      ..haloRadius = 0.3
      ..haloIntensity = 0.5
      ..chromaticAberration = 0.02;
    final emissive = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.0, 0.0, 0.0, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.9, 0.7, 1.0)
      ..emissiveStrength = 16.0
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.3, 0.3, 0.05)), emissive))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-0.8, 0.9, 0)),
    );
    final ground = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.2, 0.2, 0.22, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 2.6, depth: 2.2), ground)));
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0.4, 1.0, 3.6),
        target: vm.Vector3(-0.1, 0.55, 0),
      ),
    );
  }),
  // Low-roughness metallic: sensitive to IBL/reflections breaking (would go
  // dark or flat).
  SmokeScene('pbr_metallic', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.95, 0.95, 0.95, 1.0), 1.0, 0.15));
    return (scene: scene, camera: _camera());
  }),
  // Scalar ior / specular factor / specular color on the standard shader
  // (folded into its dielectric F0, no physical variant): an ior 1.0 sphere
  // with no dielectric reflection, a high-ior sphere, and a tinted,
  // half-weight specular sphere. Sensitive to the fold drifting from the
  // physical shader's formula.
  SmokeScene('dielectric_specular', () {
    final scene = Scene();
    Node sphere(double x, PhysicallyBasedMaterial material) =>
        Node(mesh: Mesh(SphereGeometry(radius: 0.42), material))
          ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0, 0));
    PhysicallyBasedMaterial dielectric() => PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.12, 0.1, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.2
      ..vertexColorWeight = 0.0;
    scene.add(sphere(-0.95, dielectric()..ior = 1.0));
    scene.add(sphere(0.0, dielectric()..ior = 2.4));
    scene.add(
      sphere(
        0.95,
        dielectric()
          ..specular = 0.5
          ..specularColor = vm.Vector4(0.2, 0.6, 1.0, 1.0),
      ),
    );
    return (scene: scene, camera: _camera());
  }),
  // Layered physical shader with several factor-only lobes enabled.
  SmokeScene('physical_layered', () {
    final scene = Scene();
    scene.add(
      Node(mesh: Mesh(SphereGeometry(radius: 0.85), _layeredPhysicalMaterial!)),
    );
    return (scene: scene, camera: _camera());
  }, preload: loadSmokeMaterials),
  // Screen-space transmission over an opaque object, including depth-driven
  // volume attenuation and RGB dispersion.
  SmokeScene('physical_transmission', () {
    final scene = Scene();
    scene.add(
      _cuboid(vm.Vector4(0.95, 0.35, 0.08, 1.0), 0.0, 0.55)
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0, 0, -0.65)) *
            vm.Matrix4.rotationY(0.5),
    );
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.72),
          _transmissionPhysicalMaterial!,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0, 0.45)),
    );
    scene.add(
      Node(
        mesh: Mesh(SphereGeometry(radius: 0.5), _transmissionPhysicalMaterial!),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0.2, 0, -0.15)),
    );
    return (scene: scene, camera: _camera());
  }, preload: loadSmokeMaterials),
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
  // Two instanced meshes plus a plain mesh, all sharing a lit pipeline. The
  // instanced geometries occupy separate slices of one geometry buffer arena.
  // Covers hardware instancing, arena offsets, and engine-lighting bind
  // bookkeeping between instanced and non-instanced draws.
  SmokeScene('instanced_lighting', () {
    final scene = Scene();
    final arena = GeometryBufferArena(blockSizeInBytes: 1024 * 1024);
    final cubeData = CuboidGeometry(vm.Vector3(0.5, 0.5, 0.5))
        .extractMeshData();
    scene.add(
      _directionalLightNode(vm.Vector3(-0.4, -1.0, -0.35), DirectionalLight()),
    );
    // Non-instanced receiver, drawn from the same pipeline as the instances.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 4.0, depth: 4.0),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.78, 0.78, 0.80, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.6, 0)),
    );
    // Two separate instanced meshes, so the second one draws after a
    // same-pipeline run has already started.
    for (var mesh = 0; mesh < 2; mesh++) {
      final instanced = InstancedMesh(
        geometry: MeshGeometry.fromMeshData(
          cubeData,
          bufferArena: arena,
          retainCpuData: false,
        ),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = mesh == 0
              ? vm.Vector4(0.85, 0.35, 0.20, 1.0)
              : vm.Vector4(0.20, 0.55, 0.90, 1.0)
          ..metallicFactor = 0.1
          ..roughnessFactor = 0.45
          ..vertexColorWeight = 0.0,
      );
      for (var i = 0; i < 3; i++) {
        instanced.addInstance(
          vm.Matrix4.translation(
                vm.Vector3((i - 1) * 0.85, mesh * 0.75, mesh * 0.6 - 0.3),
              ) *
              vm.Matrix4.rotationY(0.5 + i * 0.3),
        );
      }
      scene.add(Node()..addComponent(InstancedMeshComponent(instanced)));
    }
    return (scene: scene, camera: _camera());
  }),
  // A directional light casting a shadow from a floating cuboid onto a
  // ground plane. Exercises the ShadowPass (a depth-only shadow-map pass)
  // and the lit material's shadow sampling, which the other scenes don't.
  SmokeScene('directional_shadow', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.4, -1.0, -0.35),
        DirectionalLight(castsShadow: true, shadowMaxDistance: 20.0),
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
  // Both shadow-catcher modes in one frame, two catcher planes side by side
  // under one shadow-casting sun, each with the same chiral caster above it.
  // One plane bakes its footprint cache, the other samples the atlas live,
  // so a flipped or offset cache diffs against its neighbor. The
  // catcher writes only the darkening, so the magenta clear reads through the
  // planes everywhere the shadow does not fall.
  SmokeScene('shadow_catcher', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.45, -1.0, -0.3),
        DirectionalLight(castsShadow: true, shadowMaxDistance: 20.0),
      ),
    );
    final casterMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.85, 0.45, 0.25, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.6
      ..vertexColorWeight = 0.0;
    // One catcher plane plus the L-shaped caster floating above it. The
    // caster's two arms make the shadow chiral, so a mirrored cache shows.
    void station(double x, ShadowCatcherMode mode) {
      scene.add(
        Node(
          mesh: Mesh(
            PlaneGeometry(width: 2.0, depth: 2.0),
            ShadowCatcherMaterial(
              shadowIntensity: 0.85,
              aoStrength: 0.0,
              softness: 0.05,
              fadeStart: 0.6,
              fadeEnd: 1.0,
              mode: mode,
            ),
          ),
        )..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0, 0)),
      );
      scene.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.9, 0.22, 0.28)),
            casterMaterial,
          ),
        )..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0.85, -0.1)),
      );
      scene.add(
        Node(
            mesh: Mesh(
              CuboidGeometry(vm.Vector3(0.28, 0.22, 0.7)),
              casterMaterial,
            ),
          )
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(x + 0.31, 0.85, 0.4),
          ),
      );
    }

    station(-1.15, ShadowCatcherMode.baked);
    station(1.15, ShadowCatcherMode.live);
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 3.0, 4.4),
        target: vm.Vector3(0, 0.3, 0),
      ),
    );
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
  // Two quads sampling KHR_texture_basisu KTX2 textures through the standard
  // glTF path, one a mipped zstd-supercompressed UASTC sRGB file with no
  // alpha, the other an ETC1S sRGB file whose alpha blob is drawn with alpha
  // blending, so the magenta clear reads through everywhere it thins.
  // The quads themselves arrive Draco-compressed, so one scene covers
  // compressed geometry import and Basis Universal transcode all the way to
  // pixels. Both materials are unlit, so the frame reads the decoded texels
  // rather than a lighting response.
  SmokeScene('basisu_textures', () {
    final scene = Scene();
    scene.add(_basisuQuads!);
    return (
      scene: scene,
      // Square on to the quads' front, which the root handedness flip puts on
      // the -z side, so the texels land unmirrored.
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0, -3.1),
        target: vm.Vector3.zero(),
      ),
    );
  }, preload: loadBasisuQuads),
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
      _directionalLightNode(
        vm.Vector3(-0.4, -1.0, -0.35),
        DirectionalLight(castsShadow: true, shadowMaxDistance: 20.0),
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
  }, preload: loadSmokeMaterials),
  // A projected box decal over a ground plane and one prop. The decal's
  // fragments unproject the opaque depth into the box's local space, so the
  // mark conforms to both the ground and the cuboid standing in it rather than
  // to the box's own faces. Its own correctness is a per-backend depth-precision
  // question, which is why it gets a scene of its own.
  SmokeScene('decal', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(vm.Vector3(-0.4, -1.0, -0.35), DirectionalLight()),
    );
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.6, depth: 3.6),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.78, 0.76, 0.72, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      ),
    );
    // A prop standing in the projection, so the mark climbs its side and top.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.7, 0.7, 0.7)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.30, 0.55, 0.85, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.6
            ..vertexColorWeight = 0.0,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0.55, 0.35, -0.35)),
    );
    scene.add(
      DecalNode(material: _fmatMaterial('Decal'))..project(
        point: vm.Vector3(0, 0.25, 0),
        normal: vm.Vector3(0, 1, 0),
        size: 2.2,
        depth: 1.6,
      ),
    );
    return (scene: scene, camera: _shadowCamera());
  }, preload: loadSmokeMaterials),
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
      _directionalLightNode(vm.Vector3(-0.5, -0.4, -0.75), DirectionalLight()),
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
  }, preload: loadSmokeModels),
  // A skinned mesh that is also morphed, held at fixed nonzero weights on
  // three targets, so the GPU morph texture path and the morph-before-skin
  // ordering both draw. The waist joint's bend carries the targets'
  // displacement with it, which is what separates the two orderings, and the
  // per-corner vertex colors make a twist or a flip read directly. The
  // second copy is the same mesh and skin at rest weights, so a morph that
  // stops blending collapses the pair into two identical shapes.
  // [loadMorphSkinnedModel] asserts the geometry took the GPU path.
  SmokeScene('morph_skinned', () {
    final scene = Scene();
    Node placed(Node model, double x) => Node()
      ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0, 0))
      ..add(model);
    scene.add(placed(_morphSkinnedRest!, -1.0));
    scene.add(placed(_morphSkinnedModel!, 1.0));
    return (
      scene: scene,
      // Imported glTF sits behind the root handedness flip, so the model's
      // front faces -z; the camera views it from there.
      camera: PerspectiveCamera(
        position: vm.Vector3(0.5, 2.0, -5.6),
        target: vm.Vector3(0, 0.9, 0),
      ),
    );
  }, preload: loadMorphSkinnedModel),

  // A hand-written vertex/fragment pair driven through ShaderMaterial, with no
  // engine vertex shader involved. The vertex stage displaces the grid along
  // its normal from a vertex-stage uniform block, so a backend that fails to
  // compile the pair, mismatches the described layout, or drops the vertex
  // uniform draws a flat or empty surface instead of a ripple.
  SmokeScene('raw_shader_pair', () {
    final material =
        ShaderMaterial(
          vertexShader: _rawPairLibrary!['RawPairVertex']!,
          fragmentShader: _rawPairLibrary!['RawPairFragment']!,
        )..setUniformBlockFromFloats('TintInfo', [
          0.45, 0.85, 1.0, 1.0, // crest
          0.04, 0.16, 0.42, 1.0, // trough
        ]);
    // Fixed time, so the frame is deterministic.
    material.setUniformBlock(
      'RippleInfo',
      ByteData.sublistView(Float32List.fromList([1.2, 0.3, 0.22, 1.0])),
      stage: ShaderStage.vertex,
    );

    const n = 48;
    const size = 3.0;
    final count = (n + 1) * (n + 1);
    final positions = Float32List(count * 3);
    final normals = Float32List(count * 3);
    var v = 0;
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        positions[v * 3] = (c / n - 0.5) * size;
        positions[v * 3 + 2] = (r / n - 0.5) * size;
        normals[v * 3 + 1] = 1.0;
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
    final scene = Scene()..environmentIntensity = 0.0;
    scene.add(
      Node(
        mesh: Mesh(
          MeshGeometry.fromArrays(
            positions: positions,
            normals: normals,
            indices: indices,
          ),
          material,
        ),
      ),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 2.6, 3.4),
        target: vm.Vector3.zero(),
      ),
    );
  }, preload: loadSmokeMaterials),

  // A pre-baked KTX2 radiance cubemap loaded straight from file bytes, with no
  // prefilter at load. Each cube face is a different saturated color and each
  // mip level is a dimmer step of the same ladder, so face order, handedness,
  // and the mip-to-roughness mapping are all readable off the reflections.
  // Head-on spheres put the +Z face at the center, the four side faces in a
  // ring, and -Z at the silhouette. Covers the cube-mip layout (Metal/Vulkan)
  // and the equirect band-atlas fallback (GLES/WebGL2) from one fixture.
  SmokeScene('prebaked_ibl', () {
    final scene = Scene()..environment = _prebakedIblEnvironment!;
    Node sphere(double x, double y, vm.Vector4 color, double roughness) => Node(
      mesh: Mesh(
        SphereGeometry(radius: 0.55),
        PhysicallyBasedMaterial()
          ..baseColorFactor = color
          ..metallicFactor = 1.0
          ..roughnessFactor = roughness
          ..vertexColorWeight = 0.0,
      ),
    )..localTransform = vm.Matrix4.translation(vm.Vector3(x, y, 0));
    // A tinted metal for the roughness sweep, so the neutral mirror stays
    // distinguishable from the smoothest of the three. World x runs right to
    // left on screen from a camera on +z, so the sweep is authored mirrored
    // and reads 0.0, 0.4, 0.9, mirror in the frame.
    final gold = vm.Vector4(0.95, 0.80, 0.45, 1.0);
    scene.add(sphere(0.75, 0.75, gold, 0.0));
    scene.add(sphere(-0.75, 0.75, gold, 0.4));
    scene.add(sphere(0.75, -0.75, gold, 0.9));
    scene.add(sphere(-0.75, -0.75, vm.Vector4(0.97, 0.97, 0.97, 1.0), 0.0));
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0, 4.2),
        target: vm.Vector3.zero(),
      ),
    );
  }, preload: loadPrebakedIbl),

  // A baked lightmap beside its control. The left quad takes its diffuse
  // ambient from the environment's spherical harmonics; the middle one, same
  // material otherwise, replaces that ambient with a bake on UV1 scaled by a
  // nonneutral intensity. The small right quad carries an RGBM-encoded bake,
  // so the decode branch renders too; its falloff lives in the alpha, so
  // reading it as plain linear radiance flattens the hot core into a
  // near-uniform bright patch.
  SmokeScene('baked_lightmap', () {
    final scene = Scene();
    final geometry = _lightmapQuad();
    PhysicallyBasedMaterial base() => PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.82, 0.82, 0.84, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.85
      ..vertexColorWeight = 0.0
      ..doubleSided = true;
    void quad(double x, double size, PhysicallyBasedMaterial material) {
      scene.add(
        Node(mesh: Mesh(geometry, material))
          ..localTransform =
              vm.Matrix4.translation(vm.Vector3(x, 0, 0)) *
              vm.Matrix4.diagonal3Values(size, size, size),
      );
    }

    // World x runs right to left on screen from a camera on +z, so the row is
    // authored mirrored and reads control, bake, RGBM bake in the frame.
    quad(1.35, 1.05, base());
    quad(
      0.05,
      1.05,
      base()
        ..lightmapTexture = _gradientLightmap()
        ..lightmapIntensity = 1.9,
    );
    quad(
      -1.35,
      0.75,
      base()
        ..lightmapTexture = _rgbmLightmap()
        ..lightmapRgbm = true,
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0, 5.4),
        target: vm.Vector3.zero(),
      ),
    );
  }),

  // Cascaded shadows down a long corridor, with the first split pinned and a
  // wide overlap. Splits land about five, ten, and seventeen units out, so
  // three hand-offs cross the near half of the corridor where there is screen
  // area to read them. A rail running the whole length casts one continuous
  // shadow stripe over all three, and the pillars sample each depth range; the
  // hand-offs must read as a smooth softening, not as stripes or a hard seam.
  SmokeScene('cascade_shaping', () {
    final scene = Scene();
    // A dim ambient, so the cast shadows carry real contrast against the sun
    // rather than washing out.
    scene.environmentIntensity = 0.3;
    scene.add(
      _directionalLightNode(
        // Grazing and pointed back toward the camera, so shadows are long and
        // fall in front of their casters instead of hiding behind them.
        vm.Vector3(-0.34, -0.62, 0.71),
        DirectionalLight(
          intensity: 3.5,
          castsShadow: true,
          shadowMaxDistance: 26.0,
          shadowCascadeCount: 4,
          firstCascadeFarBound: 5.0,
          cascadeOverlap: 0.3,
          // Below the default, so each cascade's own texel size is visible and
          // a hand-off has something to blend between.
          shadowMapResolution: 512,
          shadowSoftness: 0.06,
        ),
      ),
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.62, 0.61, 0.58, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    // A narrow strip rather than a broad field, so the frame corners stay the
    // magenta clear while the corridor runs to the horizon.
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 3.5, depth: 44.0), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0, -14.0)),
    );
    // The rail whose unbroken shadow crosses every hand-off.
    scene.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.14, 0.14, 32.0)), material),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0.95, 1.35, -10.0)),
    );
    final pillar = CuboidGeometry(vm.Vector3(0.24, 1.7, 0.24));
    for (var i = 0; i < 9; i++) {
      scene.add(
        Node(mesh: Mesh(pillar, material))
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(i.isEven ? 0.55 : -0.55, 0.85, 4.0 - i * 4.0),
          ),
      );
    }
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 3.2, 9.0),
        target: vm.Vector3(0, 0.5, -12.0),
      ),
    );
  }),

  // Per-instance custom attributes: one instanced grid whose `.fmat` declares a
  // vec4 tint and a float, each instance carrying its own values. The tint
  // sweeps red to blue across the grid and dark to bright along it, and the
  // float lifts each cube (vertex stage) while ramping its gloss (fragment
  // stage), so a mispacked instance record scrambles the gradient or flattens
  // the staircase. The light casts so the depth and shadow variants render
  // too; they bind no instance data and read zero (the documented contract),
  // so every cube's shadow sits in the flat unlifted grid while the cubes
  // themselves stair-step above it.
  SmokeScene('instance_attributes', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.35, -1.0, -0.45),
        DirectionalLight(
          intensity: 2.5,
          castsShadow: true,
          shadowMaxDistance: 20.0,
        ),
      ),
    );
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.8, depth: 3.8),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.62, 0.62, 0.62, 1.0)
            ..roughnessFactor = 0.9,
        ),
      ),
    );
    const n = 5;
    const spacing = 0.72;
    final grid = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(0.44, 0.44, 0.44)),
      material: _fmatMaterial('InstanceGrid'),
    );
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final u = col / (n - 1), v = row / (n - 1);
        final index = grid.addInstance(
          vm.Matrix4.translation(
            vm.Vector3((col - 2) * spacing, 0.22, (row - 2) * spacing),
          ),
        );
        grid.setInstanceAttribute(
          index,
          'tint',
          vm.Vector4(0.9 * u, 0.15 + 0.6 * v, 0.9 * (1.0 - u), 1.0),
        );
        grid.setInstanceAttribute(index, 'lift', (u + v) * 0.5);
      }
    }
    scene.add(Node()..addComponent(InstancedMeshComponent(grid)));
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 4.0, 4.2),
        target: vm.Vector3.zero(),
      ),
    );
  }, preload: loadSmokeMaterials),
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
        width: kSmokeSize.toDouble(),
        height: kSmokeSize.toDouble(),
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
