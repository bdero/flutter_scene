import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show debugPrint, internal, visibleForTesting;
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;
import 'package:vector_math/vector_math.dart';

import '../fmat/fmat_emitter.dart'
    show lightmapEntryName, radianceCubeEntryName;
import '../generated_assets/generated_asset_lookup.dart';
import '../generated_assets/generated_assets.dart';
import '../gpu/gpu.dart' as gpu;
import '../render/frame_transients.dart';
import 'engine_lighting.dart';
import 'physical_material.dart';
import 'physically_based_material.dart' show AlphaMode, TextureTransform;
import 'preprocessed_material.dart';

const _dataBundleKey =
    'packages/flutter_scene/flutter_scene/fmat/physical/physical.shaderbundle';
const _dataSidecarKey =
    'packages/flutter_scene/flutter_scene/fmat/physical/physical.fmat.json';

/// Nothing generated the bundle, which means the build ran without hooks.
const _missingMessage =
    'The physical material shaders are missing. flutter_scene\'s build hook '
    'compiles them during the build, so this is a build that ran without '
    'hooks. Rebuild with a Flutter version that runs package build hooks.';

/// A physical-bundle entry every build contains, used to tell a bundle this
/// engine can read from one it cannot.
@visibleForTesting
const String physicalBundleProbeName = 'PhysicalOpaque';

/// The bundle loaded, but this engine cannot unpack anything in it, which the
/// engine also reports per lookup as `Failed to unpack shader "..." from
/// bundle`.
@visibleForTesting
String physicalBundleUnusableMessage(String key) =>
    'The physical material shader bundle ($key) loaded but holds no shader this '
    'build can read, so every physically based material would silently draw '
    'nothing. Two things cause that. The build trims every bundle to the '
    'backends its target needs, and this one was trimmed for a different '
    'target than the one running (this app needs $currentShaderTarget), which '
    'happens when one $generatedAssetsEntry tree is shared by builds for '
    'different platforms. Or it was compiled by a different Flutter engine, '
    'which the bundle format is tied to. Both are fixed by rebuilding, so run '
    '`flutter clean`, delete $generatedAssetsEntry, and build again.';

Future<_PhysicalAssets>? _physicalAssetsFuture;
_PhysicalAssets? _physicalAssets;

final class _PhysicalAssets {
  const _PhysicalAssets(this.library, this.metadata);

  final gpu.ShaderLibrary library;
  final Map<String, Object?> metadata;
}

Future<_PhysicalAssets> _loadPhysicalAssets() =>
    _physicalAssetsFuture ??= _loadPhysicalAssetsAndResetOnFailure().then(
      (assets) => _physicalAssets = assets,
    );

Future<_PhysicalAssets> _loadPhysicalAssetsAndResetOnFailure() async {
  try {
    return await _loadPhysicalAssetsUncached();
  } catch (_) {
    _physicalAssetsFuture = null;
    _physicalAssets = null;
    rethrow;
  }
}

/// The physical bundle's keys: the data asset when the toolchain registered
/// one, then the app's own generated tree, then flutter_scene's, which its own
/// hook always fills. Null when nothing built it.
@visibleForTesting
Future<({String bundle, String sidecar})?> resolvePhysicalBundleKeys({
  AssetBundle? bundle,
}) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(
      bundle ?? rootBundle,
    );
    if (manifest.listAssets().contains(_dataBundleKey)) {
      return (bundle: _dataBundleKey, sidecar: _dataSidecarKey);
    }
  } catch (_) {
    // Nothing to scan; the generated trees below are the only source.
  }
  final index = await loadGeneratedAssetIndex(bundle);
  final generatedBundle = index.resolveFirstKey(
    GeneratedAssetFamily.material,
    'physical#shaderbundle',
    package: 'flutter_scene',
  );
  final generatedSidecar = index.resolveFirstKey(
    GeneratedAssetFamily.material,
    'physical#sidecar',
    package: 'flutter_scene',
  );
  if (generatedBundle == null || generatedSidecar == null) return null;
  return (bundle: generatedBundle, sidecar: generatedSidecar);
}

Future<_PhysicalAssets> _loadPhysicalAssetsUncached() async {
  final keys = await resolvePhysicalBundleKeys();
  if (keys == null) {
    final built = (await loadGeneratedAssetIndex()).targetsOf(
      GeneratedAssetFamily.material,
      'physical#shaderbundle',
      package: 'flutter_scene',
    );
    throw StateError(
      built.isEmpty
          ? _missingMessage
          : 'The physical material shaders were trimmed for '
                '${built.join(', ')}, but this app runs on '
                '$currentShaderTarget, and a bundle trimmed to one set of '
                'backends cannot be read by another. '
                'The build that should have produced it did not run or did not '
                'finish. Rebuild the app, and delete $generatedAssetsEntry '
                'first if it was written by an older flutter_scene.',
    );
  }
  final library = await gpu.loadShaderLibraryAsync(keys.bundle);
  if (library == null) {
    throw StateError(
      'Could not load the physical shader bundle "${keys.bundle}". It is '
      'compiled for the engine that built the app, so rebuild after changing '
      'Flutter versions.',
    );
  }
  // A bundle this engine cannot unpack still loads, with every lookup in it
  // returning null. Fail here rather than let the scene report itself ready and
  // then draw nothing.
  if (library[physicalBundleProbeName] == null) {
    throw StateError(physicalBundleUnusableMessage(keys.bundle));
  }
  final sidecar = jsonDecode(await rootBundle.loadString(keys.sidecar));
  return _PhysicalAssets(library, (sidecar as Map).cast<String, Object?>());
}

/// Loads the internal shader variants used by physically based materials.
@internal
Future<void> initializePhysicalMaterialResources() async {
  await _loadPhysicalAssets();
}

/// The loaded physical-bundle shader library and combined sidecar, for the
/// engine materials that ride the same bundle (the shadow catcher). Throws
/// until `Scene.initializeStaticResources()` has completed.
@internal
({gpu.ShaderLibrary library, Map<String, Object?> metadata})
requirePhysicalBundleAssets() {
  final assets = _physicalAssets;
  if (assets == null) {
    throw StateError(
      'Physical material resources are not ready. Await '
      'Scene.initializeStaticResources() before preparing materials.',
    );
  }
  return (library: assets.library, metadata: assets.metadata);
}

/// A prepared internal shader variant for [PhysicallyBasedMaterial].
@internal
class PhysicalMaterialVariant extends PreprocessedMaterial {
  PhysicalMaterialVariant._({
    required super.fragmentShader,
    required super.metadata,
    required this.transmissive,
    required this.lightmapped,
  });

  /// Whether this variant samples the captured scene color.
  final bool transmissive;

  /// Whether this variant reads its diffuse ambient from a baked lightmap.
  final bool lightmapped;

  @override
  bool get usesLightmapVariant => lightmapped;

  /// Creates a prepared variant from already-loaded static resources.
  ///
  /// [lightmapped] selects the entries that swap the SH diffuse ambient for a
  /// baked lightmap; only the opaque material ships them.
  static PhysicalMaterialVariant fromDescriptor(
    PhysicalMaterialDescriptor descriptor, {
    bool lightmapped = false,
  }) {
    final transmissive = descriptor.transmission > 0.0;
    final name = transmissive ? 'PhysicalTransmission' : 'PhysicalOpaque';
    final entry = lightmapped ? lightmapEntryName(name) : name;
    final assets = _physicalAssets;
    if (assets == null) {
      throw StateError(
        'Physical material resources are not ready. Await '
        'Scene.initializeStaticResources() before preparing materials.',
      );
    }
    gpu.Shader require(String name) {
      final shader = assets.library[name];
      if (shader == null) {
        throw StateError('Physical shader entry "$name" is missing.');
      }
      return shader;
    }

    // The sidecar is keyed by material, not by variant entry.
    final metadata = (assets.metadata[name] as Map).cast<String, Object?>();
    final material =
        PhysicalMaterialVariant._(
            fragmentShader: require(entry),
            metadata: metadata,
            transmissive: transmissive,
            lightmapped: lightmapped,
          )
          ..setShadowFragmentShader(require('${entry}Shadow'))
          ..setRadianceCubeFragmentShaders(
            require(radianceCubeEntryName(entry)),
            shadow: require(radianceCubeEntryName('${entry}Shadow')),
          );
    material.updateDescriptor(descriptor);
    return material;
  }

  /// Updates parameters without rebuilding the shader-backed material.
  void updateDescriptor(PhysicalMaterialDescriptor descriptor) {
    if ((descriptor.transmission > 0.0) != transmissive) {
      throw ArgumentError(
        'A physical material variant cannot change its transmission layout.',
      );
    }
    name = descriptor.name;
    doubleSided = descriptor.doubleSided;
    _reflectionRoughnessTexture = descriptor.metallicRoughnessTexture;
    _reflectionRoughnessFactor = descriptor.roughness;
    _isOpaque =
        !transmissive &&
        descriptor.alphaMode != AlphaMode.blend &&
        descriptor.baseColor.a >= 1.0;
    _apply(descriptor);
    configureDepthAlphaMask(
      texture: descriptor.alphaMode == AlphaMode.mask
          ? descriptor.baseColorTexture.source
          : null,
      transform: descriptor.baseColorTexture.transform,
      texCoord: descriptor.baseColorTexture.texCoord,
      cutoff: descriptor.alphaCutoff,
      alpha: descriptor.baseColor.a,
    );
  }

  bool _isOpaque = true;
  PhysicalTexture _reflectionRoughnessTexture = PhysicalTexture();
  double _reflectionRoughnessFactor = 1.0;

  PhysicalTexture _lightmapTexture = PhysicalTexture(texCoord: 1);
  double _lightmapIntensity = 1.0;
  bool _lightmapRgbm = false;

  /// Sets the baked lightmap this variant samples. Only meaningful when the
  /// variant was built with [lightmapped].
  void setLightmap(
    PhysicalTexture texture, {
    required double intensity,
    required bool rgbm,
  }) {
    _lightmapTexture = texture;
    _lightmapIntensity = intensity;
    _lightmapRgbm = rgbm;
  }

  @override
  void bindLightmap(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {
    final source = _lightmapTexture.source;
    EngineLightingUniforms.bindLightmap(
      pass,
      shader,
      transientsBuffer,
      texture: source?.sampledTexture,
      transform: _lightmapTexture.transform,
      texCoord: _lightmapTexture.texCoord,
      intensity: _lightmapIntensity,
      rgbm: _lightmapRgbm,
      sampler: source?.sampledSampler,
    );
  }

  @override
  gpu.Texture? get reflectionRoughnessTexture =>
      _reflectionRoughnessTexture.source?.sampledTexture;

  @override
  TextureTransform get reflectionRoughnessTextureTransform =>
      _reflectionRoughnessTexture.transform;

  @override
  int get reflectionRoughnessTextureTexCoord =>
      _reflectionRoughnessTexture.texCoord;

  @override
  gpu.SamplerOptions? get reflectionRoughnessTextureSampler =>
      _reflectionRoughnessTexture.source?.sampledSampler;

  @override
  double get reflectionRoughnessFactor => _reflectionRoughnessFactor;

  @override
  bool isOpaque() => _isOpaque;

  void _apply(PhysicalMaterialDescriptor d) {
    parameters
      ..setVec4('base_color_factor', d.baseColor)
      ..setFloat('metallic_factor', d.metallic)
      ..setFloat('roughness_factor', d.roughness)
      ..setFloat('normal_scale', d.normalScale)
      ..setFloat('occlusion_strength', d.occlusionStrength)
      ..setInt('alpha_mode', d.alphaMode.index)
      ..setFloat('alpha_cutoff', d.alphaCutoff)
      ..setVec3('emissive_factor', d.emissive.xyz)
      ..setFloat('emissive_strength', d.emissiveStrength)
      ..setFloat('specular_factor', d.specular)
      ..setVec3('specular_color_factor', d.specularColor.xyz)
      ..setFloat('ior', d.ior)
      ..setFloat('clearcoat', d.clearcoat)
      ..setFloat('clearcoat_roughness', d.clearcoatRoughness)
      ..setVec2('clearcoat_normal_scale', d.clearcoatNormalScale)
      ..setVec3('sheen_color', d.sheenColor.xyz)
      ..setFloat('sheen_roughness', d.sheenRoughness)
      ..setFloat('transmission', d.transmission)
      ..setFloat('diffuse_transmission', d.diffuseTransmission)
      ..setVec3('diffuse_transmission_color', d.diffuseTransmissionColor.xyz)
      ..setFloat('thickness', d.thickness)
      ..setVec3('attenuation_color', d.attenuationColor.xyz)
      ..setFloat(
        'attenuation_distance',
        d.attenuationDistance.isFinite
            ? math.max(d.attenuationDistance, 0.0001)
            : 1.0e20,
      )
      ..setFloat('dispersion', d.dispersion)
      ..setFloat('iridescence', d.iridescence)
      ..setFloat('iridescence_ior', d.iridescenceIor)
      ..setFloat('iridescence_thickness_minimum', d.iridescenceThicknessMinimum)
      ..setFloat('iridescence_thickness_maximum', d.iridescenceThicknessMaximum)
      ..setFloat('anisotropy', d.anisotropy)
      ..setFloat('anisotropy_rotation', d.anisotropyRotation);
    _setTexture('base_color_texture', d.baseColorTexture);
    _setTransform('base_color', d.baseColorTexture);
    _setTexture('metallic_roughness_texture', d.metallicRoughnessTexture);
    _setTransform('metallic_roughness', d.metallicRoughnessTexture);
    _setTexture('normal_texture', d.normalTexture);
    _setTransform('normal', d.normalTexture);
    if (!transmissive) {
      _bindFeatureTextures(d);
    } else {
      _setTexture('emissive_texture', d.emissiveTexture);
      _setTransform('emissive', d.emissiveTexture);
      _bindTransmissionTexture(d);
    }
  }

  void _bindFeatureTextures(PhysicalMaterialDescriptor d) {
    final features = <(int, PhysicalTexture)>[
      (1, d.emissiveTexture),
      (2, d.occlusionTexture),
      if (d.clearcoat > 0.0) ...[
        (7, d.clearcoatNormalTexture),
        (5, d.clearcoatTexture),
        (6, d.clearcoatRoughnessTexture),
      ],
      if (d.sheenColor.xyz.length2 > 0.0) ...[
        (8, d.sheenColorTexture),
        (9, d.sheenRoughnessTexture),
      ],
      if (d.iridescence > 0.0) ...[
        (10, d.iridescenceTexture),
        (11, d.iridescenceThicknessTexture),
      ],
      if (d.anisotropy != 0.0) (12, d.anisotropyTexture),
      if (d.diffuseTransmission > 0.0) ...[
        (14, d.diffuseTransmissionColorTexture),
        (13, d.diffuseTransmissionTexture),
      ],
      (4, d.specularColorTexture),
      (3, d.specularTexture),
    ].where((entry) => entry.$2.source != null).toList();
    if (features.length > 3) {
      debugPrint(
        'PhysicallyBasedMaterial "$name" has ${features.length} material texture '
        'inputs; this shader permutation samples the first three. '
        'TODO(material-permutations): cook a texture-mask-specific shader '
        'per imported material to remove the three-input limit.',
      );
    }
    final first = features.isEmpty ? null : features[0];
    final second = features.length < 2 ? null : features[1];
    final third = features.length < 3 ? null : features[2];
    parameters
      ..setInt('feature_a', first?.$1 ?? 0)
      ..setInt('feature_b', second?.$1 ?? 0)
      ..setInt('feature_c', third?.$1 ?? 0);
    _setTexture('feature_texture_a', first?.$2 ?? PhysicalTexture());
    _setTexture('feature_texture_b', second?.$2 ?? PhysicalTexture());
    _setTexture('feature_texture_c', third?.$2 ?? PhysicalTexture());
    _setTransform('feature_a', first?.$2 ?? PhysicalTexture());
    _setTransform('feature_b', second?.$2 ?? PhysicalTexture());
    _setTransform('feature_c', third?.$2 ?? PhysicalTexture());
  }

  void _bindTransmissionTexture(PhysicalMaterialDescriptor d) {
    final texture = d.thicknessTexture.source != null
        ? d.thicknessTexture
        : d.transmissionTexture;
    parameters.setInt(
      'transmission_texture_kind',
      d.thicknessTexture.source != null
          ? 2
          : d.transmissionTexture.source != null
          ? 1
          : 0,
    );
    _setTexture('transmission_data_texture', texture);
    _setTransform('transmission_data', texture);
    if (d.thicknessTexture.source != null &&
        d.transmissionTexture.source != null) {
      debugPrint(
        'PhysicallyBasedMaterial "$name" uses separate transmission and thickness '
        'textures; thickness takes the shared data slot. '
        'TODO(material-permutations): cook a two-data-texture transmission '
        'variant.',
      );
    }
  }

  void _setTexture(String name, PhysicalTexture texture) {
    final source = texture.source;
    final sampled = source?.sampledTexture;
    if (source == null || sampled == null) {
      parameters.clearTexture(name);
      return;
    }
    parameters.setTexture(name, sampled, sampler: source.sampledSampler);
  }

  void _setTransform(String name, PhysicalTexture texture) {
    final transform = texture.transform;
    parameters
      ..setVec4(
        '${name}_uv_transform',
        Vector4(
          transform.offset.x,
          transform.offset.y,
          transform.scale.x,
          transform.scale.y,
        ),
      )
      ..setFloat('${name}_uv_rotation', transform.rotation)
      ..setInt('${name}_uv_set', texture.texCoord.clamp(0, 1));
  }
}
