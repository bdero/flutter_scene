import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
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

final class _PhysicalAssets {
  const _PhysicalAssets(this.library, this.metadata);

  final gpu.ShaderLibrary library;
  final Map<String, Object?> metadata;
}

Future<_PhysicalAssets> _loadPhysicalAssets() =>
    _physicalAssetsFuture ??= _loadPhysicalAssetsAndResetOnFailure();

Future<_PhysicalAssets> _loadPhysicalAssetsAndResetOnFailure() async {
  try {
    return await _loadPhysicalAssetsUncached();
  } catch (_) {
    _physicalAssetsFuture = null;
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

/// Advanced layered PBR material with scene-native property names.
///
/// Use [fromDescriptor] for imported data or construct a
/// [PhysicalMaterialDescriptor] directly. Importers map KHR extensions into
/// the same fields, so direct scene authoring never uses format-specific names.
/// {@category Materials}
class PhysicalMaterial extends PreprocessedMaterial {
  PhysicalMaterial._({required super.fragmentShader, required super.metadata});

  /// Creates and loads a physical material from [descriptor].
  static Future<PhysicalMaterial> fromDescriptor(
    PhysicalMaterialDescriptor descriptor,
  ) async {
    final transmissive = descriptor.transmission > 0.0;
    final entry = transmissive ? 'PhysicalTransmission' : 'PhysicalOpaque';
    final assets = await _loadPhysicalAssets();
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
    final material = PhysicalMaterial._(
      fragmentShader: shader,
      metadata: metadata,
    )..setShadowFragmentShader(shadowShader);
    material.name = descriptor.name;
    material.doubleSided = descriptor.doubleSided;
    material._supportsTransmission = transmissive;
    material._alphaMode = descriptor.alphaMode;
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
  bool _supportsTransmission = false;
  AlphaMode _alphaMode = AlphaMode.opaque;
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
        'PhysicalMaterial "$name" has ${features.length} material texture '
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
        'PhysicalMaterial "$name" uses separate transmission and thickness '
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

  /// Updates the clearcoat weight.
  set clearcoat(double value) =>
      parameters.setFloat('clearcoat', value.clamp(0.0, 1.0));

  /// Updates the linear base color and alpha.
  set baseColor(Vector4 value) {
    parameters.setVec4('base_color_factor', value);
    _isOpaque =
        !_supportsTransmission &&
        _alphaMode != AlphaMode.blend &&
        value.a >= 1.0;
  }

  /// Updates metalness.
  set metallic(double value) =>
      parameters.setFloat('metallic_factor', value.clamp(0.0, 1.0));

  /// Updates perceptual roughness.
  set roughness(double value) => parameters.setFloat(
    'roughness_factor',
    _reflectionRoughnessFactor = value.clamp(0.0, 1.0),
  );

  /// Updates the normal-map strength.
  set normalScale(double value) => parameters.setFloat('normal_scale', value);

  /// Updates ambient-occlusion strength.
  set occlusionStrength(double value) =>
      parameters.setFloat('occlusion_strength', value.clamp(0.0, 1.0));

  /// Updates the linear emissive color.
  set emissive(Vector3 value) => parameters.setVec3('emissive_factor', value);

  /// Updates emissive radiance strength.
  set emissiveStrength(double value) =>
      parameters.setFloat('emissive_strength', math.max(value, 0.0));

  /// Updates dielectric specular weight.
  set specular(double value) =>
      parameters.setFloat('specular_factor', value.clamp(0.0, 1.0));

  /// Updates the linear dielectric specular color.
  set specularColor(Vector3 value) =>
      parameters.setVec3('specular_color_factor', value);

  /// Updates clearcoat perceptual roughness.
  set clearcoatRoughness(double value) =>
      parameters.setFloat('clearcoat_roughness', value.clamp(0.0, 1.0));

  /// Updates the sheen color.
  set sheenColor(Vector3 value) => parameters.setVec3('sheen_color', value);

  /// Updates sheen perceptual roughness.
  set sheenRoughness(double value) =>
      parameters.setFloat('sheen_roughness', value.clamp(0.0, 1.0));

  /// Updates specular transmission.
  set transmission(double value) {
    if (!_supportsTransmission) {
      throw StateError(
        'This material was created without transmission scene inputs. '
        'Create it from a descriptor whose transmission is greater than zero.',
      );
    }
    parameters.setFloat('transmission', value.clamp(0.0, 1.0));
  }

  /// Updates diffuse transmission.
  set diffuseTransmission(double value) =>
      parameters.setFloat('diffuse_transmission', value.clamp(0.0, 1.0));

  /// Updates the linear diffuse-transmission color.
  set diffuseTransmissionColor(Vector3 value) =>
      parameters.setVec3('diffuse_transmission_color', value);

  /// Updates volume thickness in scene units.
  set thickness(double value) =>
      parameters.setFloat('thickness', math.max(value, 0.0));

  /// Updates the distance at which volume attenuation reaches its color.
  set attenuationDistance(double value) => parameters.setFloat(
    'attenuation_distance',
    value.isFinite ? math.max(value, 0.0001) : 1.0e20,
  );

  /// Updates the linear volume attenuation color.
  set attenuationColor(Vector3 value) =>
      parameters.setVec3('attenuation_color', value);

  /// Updates chromatic transmission spread.
  set dispersion(double value) =>
      parameters.setFloat('dispersion', math.max(value, 0.0));

  /// Updates the iridescent-film weight.
  set iridescence(double value) =>
      parameters.setFloat('iridescence', value.clamp(0.0, 1.0));

  /// Updates the iridescent-film index of refraction.
  set iridescenceIor(double value) =>
      parameters.setFloat('iridescence_ior', math.max(value, 1.0));

  /// Updates anisotropic reflection strength.
  set anisotropy(double value) =>
      parameters.setFloat('anisotropy', value.clamp(0.0, 1.0));

  /// Updates anisotropy direction rotation in radians.
  set anisotropyRotation(double value) =>
      parameters.setFloat('anisotropy_rotation', value);

  /// Updates the material index of refraction.
  set ior(double value) => parameters.setFloat('ior', math.max(value, 1.0));
}
