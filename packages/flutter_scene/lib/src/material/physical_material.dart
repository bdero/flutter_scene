import 'package:vector_math/vector_math.dart';
import 'package:flutter/foundation.dart' show internal;

import '../texture/texture2d.dart';
import 'physically_based_material.dart';

/// One texture input on a [PhysicalMaterialDescriptor].
@internal
class PhysicalTexture {
  /// Creates a texture input with optional UV selection and transform.
  PhysicalTexture({this.source, TextureTransform? transform, this.texCoord = 0})
    : transform = transform ?? TextureTransform();

  /// The image sampled by this input.
  final TextureSource? source;

  /// The UV transform applied before sampling.
  final TextureTransform transform;

  /// The source UV channel. Built-in geometry carries channels zero and one.
  final int texCoord;
}

/// Normalized scene-native properties for a physically based material.
///
/// Importers normalize file-format extensions into these property names.
@internal
class PhysicalMaterialDescriptor {
  /// Creates a physical material description.
  PhysicalMaterialDescriptor({
    this.name = '',
    PhysicalTexture? baseColorTexture,
    Vector4? baseColor,
    PhysicalTexture? metallicRoughnessTexture,
    this.metallic = 1.0,
    this.roughness = 1.0,
    PhysicalTexture? normalTexture,
    this.normalScale = 1.0,
    PhysicalTexture? occlusionTexture,
    this.occlusionStrength = 1.0,
    PhysicalTexture? emissiveTexture,
    Vector4? emissive,
    this.emissiveStrength = 1.0,
    PhysicalTexture? specularTexture,
    this.specular = 1.0,
    PhysicalTexture? specularColorTexture,
    Vector4? specularColor,
    this.ior = 1.5,
    PhysicalTexture? clearcoatTexture,
    this.clearcoat = 0.0,
    PhysicalTexture? clearcoatRoughnessTexture,
    this.clearcoatRoughness = 0.0,
    PhysicalTexture? clearcoatNormalTexture,
    Vector2? clearcoatNormalScale,
    PhysicalTexture? sheenColorTexture,
    Vector4? sheenColor,
    PhysicalTexture? sheenRoughnessTexture,
    this.sheenRoughness = 0.0,
    PhysicalTexture? transmissionTexture,
    this.transmission = 0.0,
    PhysicalTexture? diffuseTransmissionTexture,
    this.diffuseTransmission = 0.0,
    PhysicalTexture? diffuseTransmissionColorTexture,
    Vector4? diffuseTransmissionColor,
    PhysicalTexture? thicknessTexture,
    this.thickness = 0.0,
    this.attenuationDistance = double.infinity,
    Vector4? attenuationColor,
    this.dispersion = 0.0,
    PhysicalTexture? iridescenceTexture,
    this.iridescence = 0.0,
    this.iridescenceIor = 1.3,
    PhysicalTexture? iridescenceThicknessTexture,
    this.iridescenceThicknessMinimum = 100.0,
    this.iridescenceThicknessMaximum = 400.0,
    PhysicalTexture? anisotropyTexture,
    this.anisotropy = 0.0,
    this.anisotropyRotation = 0.0,
    this.alphaMode = AlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
  }) : baseColorTexture = baseColorTexture ?? PhysicalTexture(),
       baseColor = baseColor ?? Vector4.all(1.0),
       metallicRoughnessTexture = metallicRoughnessTexture ?? PhysicalTexture(),
       normalTexture = normalTexture ?? PhysicalTexture(),
       occlusionTexture = occlusionTexture ?? PhysicalTexture(),
       emissiveTexture = emissiveTexture ?? PhysicalTexture(),
       emissive = emissive ?? Vector4.zero(),
       specularTexture = specularTexture ?? PhysicalTexture(),
       specularColorTexture = specularColorTexture ?? PhysicalTexture(),
       specularColor = specularColor ?? Vector4.all(1.0),
       clearcoatTexture = clearcoatTexture ?? PhysicalTexture(),
       clearcoatRoughnessTexture =
           clearcoatRoughnessTexture ?? PhysicalTexture(),
       clearcoatNormalTexture = clearcoatNormalTexture ?? PhysicalTexture(),
       clearcoatNormalScale = clearcoatNormalScale ?? Vector2.all(1.0),
       sheenColorTexture = sheenColorTexture ?? PhysicalTexture(),
       sheenColor = sheenColor ?? Vector4.zero(),
       sheenRoughnessTexture = sheenRoughnessTexture ?? PhysicalTexture(),
       transmissionTexture = transmissionTexture ?? PhysicalTexture(),
       diffuseTransmissionTexture =
           diffuseTransmissionTexture ?? PhysicalTexture(),
       diffuseTransmissionColorTexture =
           diffuseTransmissionColorTexture ?? PhysicalTexture(),
       diffuseTransmissionColor = diffuseTransmissionColor ?? Vector4.all(1.0),
       thicknessTexture = thicknessTexture ?? PhysicalTexture(),
       attenuationColor = attenuationColor ?? Vector4.all(1.0),
       iridescenceTexture = iridescenceTexture ?? PhysicalTexture(),
       iridescenceThicknessTexture =
           iridescenceThicknessTexture ?? PhysicalTexture(),
       anisotropyTexture = anisotropyTexture ?? PhysicalTexture();

  /// Source material name.
  final String name;

  /// Base-color texture input.
  final PhysicalTexture baseColorTexture;

  /// Linear base color and alpha.
  final Vector4 baseColor;

  /// Packed metallic and roughness texture input.
  final PhysicalTexture metallicRoughnessTexture;

  /// Metalness weight.
  final double metallic;

  /// Perceptual roughness.
  final double roughness;

  /// Tangent-space normal texture input.
  final PhysicalTexture normalTexture;

  /// Normal-map strength.
  final double normalScale;

  /// Ambient-occlusion texture input.
  final PhysicalTexture occlusionTexture;

  /// Ambient-occlusion strength.
  final double occlusionStrength;

  /// Emissive color texture input.
  final PhysicalTexture emissiveTexture;

  /// Linear emissive color.
  final Vector4 emissive;

  /// Emissive radiance multiplier.
  final double emissiveStrength;

  /// Dielectric specular-weight texture input.
  final PhysicalTexture specularTexture;

  /// Dielectric specular weight.
  final double specular;

  /// Dielectric specular-color texture input.
  final PhysicalTexture specularColorTexture;

  /// Linear dielectric specular color.
  final Vector4 specularColor;

  /// Index of refraction.
  final double ior;

  /// Clearcoat-weight texture input.
  final PhysicalTexture clearcoatTexture;

  /// Clearcoat layer weight.
  final double clearcoat;

  /// Clearcoat-roughness texture input.
  final PhysicalTexture clearcoatRoughnessTexture;

  /// Clearcoat perceptual roughness.
  final double clearcoatRoughness;

  /// Clearcoat normal texture input.
  final PhysicalTexture clearcoatNormalTexture;

  /// Clearcoat normal-map strength on each tangent axis.
  final Vector2 clearcoatNormalScale;

  /// Sheen-color texture input.
  final PhysicalTexture sheenColorTexture;

  /// Linear sheen color.
  final Vector4 sheenColor;

  /// Sheen-roughness texture input.
  final PhysicalTexture sheenRoughnessTexture;

  /// Sheen perceptual roughness.
  final double sheenRoughness;

  /// Specular-transmission texture input.
  final PhysicalTexture transmissionTexture;

  /// Specular-transmission weight.
  final double transmission;

  /// Diffuse-transmission weight texture input.
  final PhysicalTexture diffuseTransmissionTexture;

  /// Diffuse-transmission weight.
  final double diffuseTransmission;

  /// Diffuse-transmission color texture input.
  final PhysicalTexture diffuseTransmissionColorTexture;

  /// Linear diffuse-transmission color.
  final Vector4 diffuseTransmissionColor;

  /// Volume-thickness texture input.
  final PhysicalTexture thicknessTexture;

  /// Volume thickness in scene units.
  final double thickness;

  /// Distance at which attenuation reaches [attenuationColor].
  final double attenuationDistance;

  /// Linear volume attenuation color.
  final Vector4 attenuationColor;

  /// Chromatic transmission spread.
  final double dispersion;

  /// Iridescence-weight texture input.
  final PhysicalTexture iridescenceTexture;

  /// Iridescence layer weight.
  final double iridescence;

  /// Iridescent film index of refraction.
  final double iridescenceIor;

  /// Iridescent film-thickness texture input.
  final PhysicalTexture iridescenceThicknessTexture;

  /// Minimum film thickness in nanometres.
  final double iridescenceThicknessMinimum;

  /// Maximum film thickness in nanometres.
  final double iridescenceThicknessMaximum;

  /// Anisotropy direction and strength texture input.
  final PhysicalTexture anisotropyTexture;

  /// Anisotropic reflection strength.
  final double anisotropy;

  /// Anisotropy direction rotation in radians.
  final double anisotropyRotation;

  /// Alpha interpretation.
  final AlphaMode alphaMode;

  /// Cutout threshold for [AlphaMode.mask].
  final double alphaCutoff;

  /// Whether both sides render.
  final bool doubleSided;
}
