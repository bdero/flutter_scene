import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, internal;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:vector_math/vector_math.dart';

import '../gpu/gpu.dart' as gpu;
import 'physical_material.dart';
import 'physically_based_material.dart' show AlphaMode, TextureTransform;
import 'preprocessed_material.dart';

const _dataBundleKey =
    'packages/flutter_scene/flutter_scene/fmat/physical/physical.shaderbundle';
const _dataSidecarKey =
    'packages/flutter_scene/flutter_scene/fmat/physical/physical.fmat.json';
const _legacyBundleKey =
    'packages/flutter_scene/build/shaderbundles/physical.shaderbundle';
const _legacySidecarKey =
    'packages/flutter_scene/build/shaderbundles/physical.fmat.json';

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

Future<_PhysicalAssets> _loadPhysicalAssetsUncached() async {
  var bundleKey = _legacyBundleKey;
  var sidecarKey = _legacySidecarKey;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    if (manifest.listAssets().contains(_dataBundleKey)) {
      bundleKey = _dataBundleKey;
      sidecarKey = _dataSidecarKey;
    }
  } catch (_) {
    // The legacy assets remain available without an asset manifest.
  }
  final library = await gpu.loadShaderLibraryAsync(bundleKey);
  if (library == null) {
    throw StateError('Could not load physical shader bundle "$bundleKey".');
  }
  final sidecar = jsonDecode(await rootBundle.loadString(sidecarKey));
  return _PhysicalAssets(library, (sidecar as Map).cast<String, Object?>());
}

/// Loads the internal shader variants used by physically based materials.
@internal
Future<void> initializePhysicalMaterialResources() async {
  await _loadPhysicalAssets();
}

/// A prepared internal shader variant for [PhysicallyBasedMaterial].
@internal
class PhysicalMaterialVariant extends PreprocessedMaterial {
  PhysicalMaterialVariant._({
    required super.fragmentShader,
    required super.metadata,
  });

  /// Creates a prepared variant from already-loaded static resources.
  static PhysicalMaterialVariant fromDescriptor(
    PhysicalMaterialDescriptor descriptor,
  ) {
    final transmissive = descriptor.transmission > 0.0;
    final entry = transmissive ? 'PhysicalTransmission' : 'PhysicalOpaque';
    final assets = _physicalAssets;
    if (assets == null) {
      throw StateError(
        'Physical material resources are not ready. Await '
        'Scene.initializeStaticResources() before preparing materials.',
      );
    }
    final shader = assets.library[entry];
    if (shader == null) {
      throw StateError('Physical shader entry "$entry" is missing.');
    }
    final shadowShader = assets.library['${entry}Shadow'];
    if (shadowShader == null) {
      throw StateError(
        'Physical shadow shader entry "${entry}Shadow" is missing.',
      );
    }
    final metadata = (assets.metadata[entry] as Map).cast<String, Object?>();
    final material = PhysicalMaterialVariant._(
      fragmentShader: shader,
      metadata: metadata,
    )..setShadowFragmentShader(shadowShader);
    material.name = descriptor.name;
    material.doubleSided = descriptor.doubleSided;
    material._reflectionRoughnessTexture = descriptor.metallicRoughnessTexture;
    material._reflectionRoughnessFactor = descriptor.roughness;
    material._isOpaque =
        !transmissive &&
        descriptor.alphaMode != AlphaMode.blend &&
        descriptor.baseColor.a >= 1.0;
    material._apply(descriptor, transmissive: transmissive);
    if (descriptor.alphaMode == AlphaMode.mask) {
      material.configureDepthAlphaMask(
        texture: descriptor.baseColorTexture.source,
        transform: descriptor.baseColorTexture.transform,
        texCoord: descriptor.baseColorTexture.texCoord,
        cutoff: descriptor.alphaCutoff,
        alpha: descriptor.baseColor.a,
      );
    }
    return material;
  }

  bool _isOpaque = true;
  PhysicalTexture _reflectionRoughnessTexture = PhysicalTexture();
  double _reflectionRoughnessFactor = 1.0;

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

  void _apply(PhysicalMaterialDescriptor d, {required bool transmissive}) {
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
    if (first != null) _setTexture('feature_texture_a', first.$2);
    if (second != null) _setTexture('feature_texture_b', second.$2);
    if (third != null) _setTexture('feature_texture_c', third.$2);
    _setTransform('feature_a', first?.$2 ?? PhysicalTexture());
    _setTransform('feature_b', second?.$2 ?? PhysicalTexture());
    _setTransform('feature_c', third?.$2 ?? PhysicalTexture());
  }

  void _bindTransmissionTexture(PhysicalMaterialDescriptor d) {
    final source = d.thicknessTexture.source ?? d.transmissionTexture.source;
    parameters.setInt(
      'transmission_texture_kind',
      d.thicknessTexture.source != null ? 2 : 1,
    );
    if (source != null) {
      _setTexture(
        'transmission_data_texture',
        d.thicknessTexture.source != null
            ? d.thicknessTexture
            : d.transmissionTexture,
      );
      _setTransform(
        'transmission_data',
        d.thicknessTexture.source != null
            ? d.thicknessTexture
            : d.transmissionTexture,
      );
    }
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
    if (source == null || sampled == null) return;
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
