import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/physical_material_variant.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physical_material.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// How a [PhysicallyBasedMaterial]'s alpha channel is interpreted,
/// matching glTF's `alphaMode`.
/// {@category Materials}
enum AlphaMode {
  /// Alpha is ignored; the material renders fully opaque.
  opaque,

  /// Alpha-tested: a fragment whose alpha is below
  /// [PhysicallyBasedMaterial.alphaCutoff] is discarded and the rest
  /// render fully opaque. Used for cut-out foliage and similar.
  mask,

  /// Alpha-blended: drawn in the depth-sorted translucent pass with
  /// source-over blending.
  blend,
}

/// A texture-coordinate transform applied before sampling a material slot.
///
/// The transform follows glTF's `KHR_texture_transform` order. [scale] is
/// applied first, followed by [rotation] around the origin and [offset].
/// {@category Materials}
class TextureTransform {
  /// Creates a texture transform, identity when all arguments are omitted.
  TextureTransform({Vector2? offset, Vector2? scale, this.rotation = 0.0})
    : offset = offset ?? Vector2.zero(),
      scale = scale ?? Vector2.all(1.0);

  /// Translation in UV coordinates.
  Vector2 offset;

  /// Per-axis UV scale.
  Vector2 scale;

  /// Counter-clockwise rotation in radians.
  double rotation;

  /// Whether this transform leaves UV coordinates unchanged.
  bool get isIdentity =>
      offset == Vector2.zero() && scale == Vector2.all(1.0) && rotation == 0.0;
}

/// A metallic-roughness physically based material with optional layered and
/// transmissive features.
///
/// The material selects and caches an internal shader variant from its active
/// features. Basic opaque configurations use the standard shader, including
/// a scalar [ior], [specular], and [specularColor] (folded into its dielectric
/// reflectance), while specular textures, clearcoat, sheen, transmission,
/// anisotropy, iridescence, and related properties activate physical variants
/// without changing the public type.
/// Importers normalize format-specific extensions into these scene-native
/// properties.
///
///  * Albedo: [baseColorFactor], [baseColorTexture] (multiplied with the
///    optional per-vertex color, weighted by [vertexColorWeight]).
///  * Metallic-roughness: [metallicFactor], [roughnessFactor],
///    [metallicRoughnessTexture] (B = metallic, G = roughness).
///  * Normal: [normalTexture] with [normalScale].
///  * Emissive: [emissiveFactor], [emissiveTexture].
///  * Occlusion: [occlusionTexture] with [occlusionStrength].
///  * Lighting: [environment] (overrides the [Scene]-wide environment
///    when set).
///
/// Translucency is determined by [transmission], [alphaMode], and
/// [baseColorFactor]'s alpha component.
/// {@category Materials}
class PhysicallyBasedMaterial extends Material {
  /// Creates a PBR material with the given textures.
  ///
  /// All textures are optional; missing textures are replaced with
  /// neutral placeholders at draw time. Per-channel scaling factors
  /// (e.g. [metallicFactor], [roughnessFactor]) default to neutral and
  /// can be tweaked after construction.
  PhysicallyBasedMaterial({
    TextureSource? baseColorTexture,
    TextureSource? metallicRoughnessTexture,
    TextureSource? normalTexture,
    TextureSource? emissiveTexture,
    TextureSource? occlusionTexture,
    this.environment,
  }) : _baseColorTexture = baseColorTexture,
       _metallicRoughnessTexture = metallicRoughnessTexture,
       _normalTexture = normalTexture,
       _emissiveTexture = emissiveTexture,
       _occlusionTexture = occlusionTexture {
    setFragmentShaderName(
      'StandardFragment',
      cubeName: 'StandardCubeFragment',
      noShadowName: 'StandardNoShadowFragment',
      noShadowCubeName: 'StandardNoShadowCubeFragment',
    );
  }

  /// Creates a material from normalized imported properties.
  @internal
  static Future<PhysicallyBasedMaterial> fromDescriptor(
    PhysicalMaterialDescriptor descriptor,
  ) async {
    await initializeStaticResources();
    final material = PhysicallyBasedMaterial();
    material._applyDescriptor(descriptor);
    material._ensurePreparedVariant();
    return material;
  }

  /// Loads the shader variants shared by all physically based materials.
  @internal
  static Future<void> initializeStaticResources() =>
      initializePhysicalMaterialResources();

  /// The raw slot sources, for serialization. Same values as the public slot
  /// fields ([baseColorTexture] and friends).
  @internal
  TextureSource? get baseColorTextureSource => baseColorTexture;
  @internal
  TextureSource? get metallicRoughnessTextureSource => metallicRoughnessTexture;
  @internal
  TextureSource? get normalTextureSource => normalTexture;
  @internal
  TextureSource? get emissiveTextureSource => emissiveTexture;
  @internal
  TextureSource? get occlusionTextureSource => occlusionTexture;

  /// The albedo (base color) texture, sampled in linear space and
  /// multiplied by [baseColorFactor]. Defaults to white when null.
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? get baseColorTexture => _baseColorTexture;
  TextureSource? _baseColorTexture;
  set baseColorTexture(TextureSource? value) {
    if (identical(_baseColorTexture, value)) return;
    _baseColorTexture = value;
    _markMaterialDataDirty();
  }

  /// UV transform applied to [baseColorTexture].
  TextureTransform get baseColorTextureTransform => _baseColorTextureTransform;
  TextureTransform _baseColorTextureTransform = TextureTransform();
  set baseColorTextureTransform(TextureTransform value) {
    _baseColorTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [baseColorTexture].
  int get baseColorTextureTexCoord => _baseColorTextureTexCoord;
  int _baseColorTextureTexCoord = 0;
  set baseColorTextureTexCoord(int value) {
    _baseColorTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Linear RGBA tint multiplied with [baseColorTexture]. Alpha controls
  /// translucency: values below `1` push the material into the depth-
  /// sorted translucent pass.
  Vector4 get baseColorFactor => _baseColorFactor;
  Vector4 _baseColorFactor = Colors.white;
  set baseColorFactor(Vector4 value) {
    _baseColorFactor = value;
    _markMaterialDataDirty();
  }

  /// How strongly per-vertex colors influence the final albedo. `0`
  /// disables vertex color contribution; `1` (the default) fully
  /// applies it.
  double vertexColorWeight = 1.0;

  /// The combined metallic-roughness texture (B = metallic,
  /// G = roughness). Defaults to white when null.
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? get metallicRoughnessTexture => _metallicRoughnessTexture;
  TextureSource? _metallicRoughnessTexture;
  set metallicRoughnessTexture(TextureSource? value) {
    if (identical(_metallicRoughnessTexture, value)) return;
    _metallicRoughnessTexture = value;
    _markMaterialDataDirty();
  }

  /// UV transform applied to [metallicRoughnessTexture].
  TextureTransform get metallicRoughnessTextureTransform =>
      _metallicRoughnessTextureTransform;
  TextureTransform _metallicRoughnessTextureTransform = TextureTransform();
  set metallicRoughnessTextureTransform(TextureTransform value) {
    _metallicRoughnessTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [metallicRoughnessTexture].
  int get metallicRoughnessTextureTexCoord => _metallicRoughnessTextureTexCoord;
  int _metallicRoughnessTextureTexCoord = 0;
  set metallicRoughnessTextureTexCoord(int value) {
    _metallicRoughnessTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Scalar multiplier applied to the metallic channel. `0` is fully
  /// dielectric, `1` is fully metallic.
  double get metallicFactor => _metallicFactor;
  double _metallicFactor = 1.0;
  set metallicFactor(double value) {
    _metallicFactor = value;
    _markMaterialDataDirty();
  }

  /// Scalar multiplier applied to the roughness channel. `0` is a
  /// perfect mirror, `1` is fully diffuse.
  double get roughnessFactor => _roughnessFactor;
  double _roughnessFactor = 1.0;
  set roughnessFactor(double value) {
    _roughnessFactor = value;
    _markMaterialDataDirty();
  }

  /// Tangent-space normal map. Defaults to a flat normal when null.
  ///
  /// Accepts a [Texture2D] (usually with [TextureContent.normal]) or a
  /// `RenderTexture` (sampled live).
  TextureSource? get normalTexture => _normalTexture;
  TextureSource? _normalTexture;
  set normalTexture(TextureSource? value) {
    if (identical(_normalTexture, value)) return;
    _normalTexture = value;
    _markMaterialDataDirty();
  }

  /// UV transform applied to [normalTexture].
  TextureTransform get normalTextureTransform => _normalTextureTransform;
  TextureTransform _normalTextureTransform = TextureTransform();
  set normalTextureTransform(TextureTransform value) {
    _normalTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [normalTexture].
  int get normalTextureTexCoord => _normalTextureTexCoord;
  int _normalTextureTexCoord = 0;
  set normalTextureTexCoord(int value) {
    _normalTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Strength of [normalTexture]'s perturbation. `1` is the unmodified
  /// map.
  double get normalScale => _normalScale;
  double _normalScale = 1.0;
  set normalScale(double value) {
    _normalScale = value;
    _markMaterialDataDirty();
  }

  /// Optional emissive texture. Defaults to white when null and is
  /// gated by [emissiveFactor].
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? get emissiveTexture => _emissiveTexture;
  TextureSource? _emissiveTexture;
  set emissiveTexture(TextureSource? value) {
    if (identical(_emissiveTexture, value)) return;
    _emissiveTexture = value;
    _markMaterialDataDirty();
  }

  /// Linear RGBA emissive tint. Alpha is unused; the default
  /// `Vector4.zero()` disables emission.
  Vector4 get emissiveFactor => _emissiveFactor;
  Vector4 _emissiveFactor = Vector4.zero();
  set emissiveFactor(Vector4 value) {
    _emissiveFactor = value;
    _markMaterialDataDirty();
  }

  /// Multiplier for emissive radiance. Values above `1` produce HDR emission.
  double get emissiveStrength => _emissiveStrength;
  double _emissiveStrength = 1.0;
  set emissiveStrength(double value) {
    _emissiveStrength = value;
    _markMaterialDataDirty();
  }

  /// UV transform applied to [emissiveTexture].
  TextureTransform get emissiveTextureTransform => _emissiveTextureTransform;
  TextureTransform _emissiveTextureTransform = TextureTransform();
  set emissiveTextureTransform(TextureTransform value) {
    _emissiveTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [emissiveTexture].
  int get emissiveTextureTexCoord => _emissiveTextureTexCoord;
  int _emissiveTextureTexCoord = 0;
  set emissiveTextureTexCoord(int value) {
    _emissiveTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Optional ambient-occlusion texture (R channel). Defaults to white
  /// when null.
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? get occlusionTexture => _occlusionTexture;
  TextureSource? _occlusionTexture;
  set occlusionTexture(TextureSource? value) {
    if (identical(_occlusionTexture, value)) return;
    _occlusionTexture = value;
    _markMaterialDataDirty();
  }

  /// UV transform applied to [occlusionTexture].
  TextureTransform get occlusionTextureTransform => _occlusionTextureTransform;
  TextureTransform _occlusionTextureTransform = TextureTransform();
  set occlusionTextureTransform(TextureTransform value) {
    _occlusionTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [occlusionTexture].
  int get occlusionTextureTexCoord => _occlusionTextureTexCoord;
  int _occlusionTextureTexCoord = 0;
  set occlusionTextureTexCoord(int value) {
    _occlusionTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Strength of [occlusionTexture]'s effect. `0` ignores the map; `1`
  /// applies it fully.
  double get occlusionStrength => _occlusionStrength;
  double _occlusionStrength = 1.0;
  set occlusionStrength(double value) {
    _occlusionStrength = value;
    _markMaterialDataDirty();
  }

  /// Baked indirect diffuse light, in linear radiance unless [lightmapRgbm] is
  /// set. Null (the default) leaves the material lit by the environment alone.
  ///
  /// A bound lightmap replaces the environment's spherical-harmonics diffuse
  /// ambient for this material rather than adding to it, so the baked bounce
  /// is not counted twice. Specular image-based lighting, the analytic lights,
  /// and [occlusionTexture] are unaffected.
  ///
  /// Selects a shader variant that carries the lightmap sampler, so binding
  /// one costs a pipeline the first time it is drawn. Not available on
  /// transmissive materials.
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  // TODO(lightmap-serialization): carry the slot through the `.fscene` codecs
  // (lib/src/fscene/realize/) and the editor's material copy, which round-trip
  // every other texture slot.
  TextureSource? get lightmapTexture => _lightmapTexture;
  TextureSource? _lightmapTexture;
  set lightmapTexture(TextureSource? value) {
    if (identical(_lightmapTexture, value)) return;
    _lightmapTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [lightmapTexture].
  TextureTransform get lightmapTextureTransform => _lightmapTextureTransform;
  TextureTransform _lightmapTextureTransform = TextureTransform();
  set lightmapTextureTransform(TextureTransform value) {
    _lightmapTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [lightmapTexture]. Defaults to `1`,
  /// the channel bakers reserve for the non-overlapping lightmap unwrap.
  int get lightmapTextureTexCoord => _lightmapTextureTexCoord;
  int _lightmapTextureTexCoord = 1;
  set lightmapTextureTexCoord(int value) {
    _lightmapTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Multiplier applied to the decoded [lightmapTexture] radiance.
  double get lightmapIntensity => _lightmapIntensity;
  double _lightmapIntensity = 1.0;
  set lightmapIntensity(double value) {
    _lightmapIntensity = value;
    _markMaterialDataDirty();
  }

  /// Whether [lightmapTexture] is RGBM-encoded, an HDR bake packed into an LDR
  /// image with the shared multiplier in the alpha channel. `false` (the
  /// default) reads the texture as linear radiance.
  bool get lightmapRgbm => _lightmapRgbm;
  bool _lightmapRgbm = false;
  set lightmapRgbm(bool value) {
    if (_lightmapRgbm == value) return;
    _lightmapRgbm = value;
    _markMaterialDataDirty();
  }

  /// Per-material image-based-lighting environment, overriding the
  /// scene-wide `Scene.environment` when set.
  EnvironmentMap? environment;

  /// How the material's alpha is interpreted; see [AlphaMode].
  ///
  /// [AlphaMode.blend] always routes the material through the
  /// translucent pass regardless of [baseColorFactor]'s alpha.
  AlphaMode get alphaMode => _alphaMode;
  AlphaMode _alphaMode = AlphaMode.opaque;
  set alphaMode(AlphaMode value) {
    if (_alphaMode == value) return;
    _alphaMode = value;
    _markMaterialDataDirty();
  }

  /// Alpha-test threshold used when [alphaMode] is [AlphaMode.mask]:
  /// fragments whose alpha falls below this are discarded.
  double get alphaCutoff => _alphaCutoff;
  double _alphaCutoff = 0.5;
  set alphaCutoff(double value) {
    _alphaCutoff = value;
    _markMaterialDataDirty();
  }

  /// Dielectric specular weight texture.
  TextureSource? get specularTexture => _specularTexture;
  TextureSource? _specularTexture;
  set specularTexture(TextureSource? value) {
    if (identical(_specularTexture, value)) return;
    _specularTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [specularTexture].
  TextureTransform get specularTextureTransform => _specularTextureTransform;
  TextureTransform _specularTextureTransform = TextureTransform();
  set specularTextureTransform(TextureTransform value) {
    _specularTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [specularTexture].
  int get specularTextureTexCoord => _specularTextureTexCoord;
  int _specularTextureTexCoord = 0;
  set specularTextureTexCoord(int value) {
    _specularTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Dielectric specular weight.
  double get specular => _specular;
  double _specular = 1.0;
  set specular(double value) {
    _specular = value.clamp(0.0, 1.0);
    _markMaterialDataDirty(variant: true);
  }

  /// Dielectric specular color texture.
  TextureSource? get specularColorTexture => _specularColorTexture;
  TextureSource? _specularColorTexture;
  set specularColorTexture(TextureSource? value) {
    if (identical(_specularColorTexture, value)) return;
    _specularColorTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [specularColorTexture].
  TextureTransform get specularColorTextureTransform =>
      _specularColorTextureTransform;
  TextureTransform _specularColorTextureTransform = TextureTransform();
  set specularColorTextureTransform(TextureTransform value) {
    _specularColorTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [specularColorTexture].
  int get specularColorTextureTexCoord => _specularColorTextureTexCoord;
  int _specularColorTextureTexCoord = 0;
  set specularColorTextureTexCoord(int value) {
    _specularColorTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Linear dielectric specular color.
  Vector4 get specularColor => _specularColor;
  Vector4 _specularColor = Vector4.all(1.0);
  set specularColor(Vector4 value) {
    _specularColor = value;
    _markMaterialDataDirty(variant: true);
  }

  /// Index of refraction.
  double get ior => _ior;
  double _ior = 1.5;
  set ior(double value) {
    _ior = math.max(value, 1.0);
    _markMaterialDataDirty(variant: true);
  }

  /// Clearcoat weight texture.
  TextureSource? get clearcoatTexture => _clearcoatTexture;
  TextureSource? _clearcoatTexture;
  set clearcoatTexture(TextureSource? value) {
    if (identical(_clearcoatTexture, value)) return;
    _clearcoatTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [clearcoatTexture].
  TextureTransform get clearcoatTextureTransform => _clearcoatTextureTransform;
  TextureTransform _clearcoatTextureTransform = TextureTransform();
  set clearcoatTextureTransform(TextureTransform value) {
    _clearcoatTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [clearcoatTexture].
  int get clearcoatTextureTexCoord => _clearcoatTextureTexCoord;
  int _clearcoatTextureTexCoord = 0;
  set clearcoatTextureTexCoord(int value) {
    _clearcoatTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Clearcoat layer weight.
  double get clearcoat => _clearcoat;
  double _clearcoat = 0.0;
  set clearcoat(double value) {
    _clearcoat = value.clamp(0.0, 1.0);
    _markMaterialDataDirty(variant: true);
  }

  /// Clearcoat roughness texture.
  TextureSource? get clearcoatRoughnessTexture => _clearcoatRoughnessTexture;
  TextureSource? _clearcoatRoughnessTexture;
  set clearcoatRoughnessTexture(TextureSource? value) {
    if (identical(_clearcoatRoughnessTexture, value)) return;
    _clearcoatRoughnessTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [clearcoatRoughnessTexture].
  TextureTransform get clearcoatRoughnessTextureTransform =>
      _clearcoatRoughnessTextureTransform;
  TextureTransform _clearcoatRoughnessTextureTransform = TextureTransform();
  set clearcoatRoughnessTextureTransform(TextureTransform value) {
    _clearcoatRoughnessTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [clearcoatRoughnessTexture].
  int get clearcoatRoughnessTextureTexCoord =>
      _clearcoatRoughnessTextureTexCoord;
  int _clearcoatRoughnessTextureTexCoord = 0;
  set clearcoatRoughnessTextureTexCoord(int value) {
    _clearcoatRoughnessTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Clearcoat perceptual roughness.
  double get clearcoatRoughness => _clearcoatRoughness;
  double _clearcoatRoughness = 0.0;
  set clearcoatRoughness(double value) {
    _clearcoatRoughness = value.clamp(0.0, 1.0);
    _markMaterialDataDirty();
  }

  /// Clearcoat tangent-space normal texture.
  TextureSource? get clearcoatNormalTexture => _clearcoatNormalTexture;
  TextureSource? _clearcoatNormalTexture;
  set clearcoatNormalTexture(TextureSource? value) {
    if (identical(_clearcoatNormalTexture, value)) return;
    _clearcoatNormalTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [clearcoatNormalTexture].
  TextureTransform get clearcoatNormalTextureTransform =>
      _clearcoatNormalTextureTransform;
  TextureTransform _clearcoatNormalTextureTransform = TextureTransform();
  set clearcoatNormalTextureTransform(TextureTransform value) {
    _clearcoatNormalTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [clearcoatNormalTexture].
  int get clearcoatNormalTextureTexCoord => _clearcoatNormalTextureTexCoord;
  int _clearcoatNormalTextureTexCoord = 0;
  set clearcoatNormalTextureTexCoord(int value) {
    _clearcoatNormalTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Clearcoat normal-map strength on each tangent axis.
  Vector2 get clearcoatNormalScale => _clearcoatNormalScale;
  Vector2 _clearcoatNormalScale = Vector2.all(1.0);
  set clearcoatNormalScale(Vector2 value) {
    _clearcoatNormalScale = value;
    _markMaterialDataDirty();
  }

  /// Sheen color texture.
  TextureSource? get sheenColorTexture => _sheenColorTexture;
  TextureSource? _sheenColorTexture;
  set sheenColorTexture(TextureSource? value) {
    if (identical(_sheenColorTexture, value)) return;
    _sheenColorTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [sheenColorTexture].
  TextureTransform get sheenColorTextureTransform =>
      _sheenColorTextureTransform;
  TextureTransform _sheenColorTextureTransform = TextureTransform();
  set sheenColorTextureTransform(TextureTransform value) {
    _sheenColorTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [sheenColorTexture].
  int get sheenColorTextureTexCoord => _sheenColorTextureTexCoord;
  int _sheenColorTextureTexCoord = 0;
  set sheenColorTextureTexCoord(int value) {
    _sheenColorTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Linear sheen color.
  Vector4 get sheenColor => _sheenColor;
  Vector4 _sheenColor = Vector4.zero();
  set sheenColor(Vector4 value) {
    _sheenColor = value;
    _markMaterialDataDirty(variant: true);
  }

  /// Sheen roughness texture.
  TextureSource? get sheenRoughnessTexture => _sheenRoughnessTexture;
  TextureSource? _sheenRoughnessTexture;
  set sheenRoughnessTexture(TextureSource? value) {
    if (identical(_sheenRoughnessTexture, value)) return;
    _sheenRoughnessTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [sheenRoughnessTexture].
  TextureTransform get sheenRoughnessTextureTransform =>
      _sheenRoughnessTextureTransform;
  TextureTransform _sheenRoughnessTextureTransform = TextureTransform();
  set sheenRoughnessTextureTransform(TextureTransform value) {
    _sheenRoughnessTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [sheenRoughnessTexture].
  int get sheenRoughnessTextureTexCoord => _sheenRoughnessTextureTexCoord;
  int _sheenRoughnessTextureTexCoord = 0;
  set sheenRoughnessTextureTexCoord(int value) {
    _sheenRoughnessTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Sheen perceptual roughness.
  double get sheenRoughness => _sheenRoughness;
  double _sheenRoughness = 0.0;
  set sheenRoughness(double value) {
    _sheenRoughness = value.clamp(0.0, 1.0);
    _markMaterialDataDirty();
  }

  /// Specular transmission texture.
  TextureSource? get transmissionTexture => _transmissionTexture;
  TextureSource? _transmissionTexture;
  set transmissionTexture(TextureSource? value) {
    if (identical(_transmissionTexture, value)) return;
    _transmissionTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [transmissionTexture].
  TextureTransform get transmissionTextureTransform =>
      _transmissionTextureTransform;
  TextureTransform _transmissionTextureTransform = TextureTransform();
  set transmissionTextureTransform(TextureTransform value) {
    _transmissionTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [transmissionTexture].
  int get transmissionTextureTexCoord => _transmissionTextureTexCoord;
  int _transmissionTextureTexCoord = 0;
  set transmissionTextureTexCoord(int value) {
    _transmissionTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Specular transmission weight.
  double get transmission => _transmission;
  double _transmission = 0.0;
  set transmission(double value) {
    final next = value.clamp(0.0, 1.0);
    _transmission = next;
    _markMaterialDataDirty(variant: true);
  }

  /// Diffuse transmission weight texture.
  TextureSource? get diffuseTransmissionTexture => _diffuseTransmissionTexture;
  TextureSource? _diffuseTransmissionTexture;
  set diffuseTransmissionTexture(TextureSource? value) {
    if (identical(_diffuseTransmissionTexture, value)) return;
    _diffuseTransmissionTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [diffuseTransmissionTexture].
  TextureTransform get diffuseTransmissionTextureTransform =>
      _diffuseTransmissionTextureTransform;
  TextureTransform _diffuseTransmissionTextureTransform = TextureTransform();
  set diffuseTransmissionTextureTransform(TextureTransform value) {
    _diffuseTransmissionTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [diffuseTransmissionTexture].
  int get diffuseTransmissionTextureTexCoord =>
      _diffuseTransmissionTextureTexCoord;
  int _diffuseTransmissionTextureTexCoord = 0;
  set diffuseTransmissionTextureTexCoord(int value) {
    _diffuseTransmissionTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Diffuse transmission weight.
  double get diffuseTransmission => _diffuseTransmission;
  double _diffuseTransmission = 0.0;
  set diffuseTransmission(double value) {
    _diffuseTransmission = value.clamp(0.0, 1.0);
    _markMaterialDataDirty(variant: true);
  }

  /// Diffuse transmission color texture.
  TextureSource? get diffuseTransmissionColorTexture =>
      _diffuseTransmissionColorTexture;
  TextureSource? _diffuseTransmissionColorTexture;
  set diffuseTransmissionColorTexture(TextureSource? value) {
    if (identical(_diffuseTransmissionColorTexture, value)) return;
    _diffuseTransmissionColorTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [diffuseTransmissionColorTexture].
  TextureTransform get diffuseTransmissionColorTextureTransform =>
      _diffuseTransmissionColorTextureTransform;
  TextureTransform _diffuseTransmissionColorTextureTransform =
      TextureTransform();
  set diffuseTransmissionColorTextureTransform(TextureTransform value) {
    _diffuseTransmissionColorTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [diffuseTransmissionColorTexture].
  int get diffuseTransmissionColorTextureTexCoord =>
      _diffuseTransmissionColorTextureTexCoord;
  int _diffuseTransmissionColorTextureTexCoord = 0;
  set diffuseTransmissionColorTextureTexCoord(int value) {
    _diffuseTransmissionColorTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Linear diffuse transmission color.
  Vector4 get diffuseTransmissionColor => _diffuseTransmissionColor;
  Vector4 _diffuseTransmissionColor = Vector4.all(1.0);
  set diffuseTransmissionColor(Vector4 value) {
    _diffuseTransmissionColor = value;
    _markMaterialDataDirty();
  }

  /// Volume thickness texture.
  TextureSource? get thicknessTexture => _thicknessTexture;
  TextureSource? _thicknessTexture;
  set thicknessTexture(TextureSource? value) {
    if (identical(_thicknessTexture, value)) return;
    _thicknessTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [thicknessTexture].
  TextureTransform get thicknessTextureTransform => _thicknessTextureTransform;
  TextureTransform _thicknessTextureTransform = TextureTransform();
  set thicknessTextureTransform(TextureTransform value) {
    _thicknessTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [thicknessTexture].
  int get thicknessTextureTexCoord => _thicknessTextureTexCoord;
  int _thicknessTextureTexCoord = 0;
  set thicknessTextureTexCoord(int value) {
    _thicknessTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Volume thickness in scene units.
  double get thickness => _thickness;
  double _thickness = 0.0;
  set thickness(double value) {
    _thickness = math.max(value, 0.0);
    _markMaterialDataDirty();
  }

  /// Distance at which volume attenuation reaches [attenuationColor].
  double get attenuationDistance => _attenuationDistance;
  double _attenuationDistance = double.infinity;
  set attenuationDistance(double value) {
    _attenuationDistance = value;
    _markMaterialDataDirty();
  }

  /// Linear volume attenuation color.
  Vector4 get attenuationColor => _attenuationColor;
  Vector4 _attenuationColor = Vector4.all(1.0);
  set attenuationColor(Vector4 value) {
    _attenuationColor = value;
    _markMaterialDataDirty();
  }

  /// Chromatic transmission spread.
  double get dispersion => _dispersion;
  double _dispersion = 0.0;
  set dispersion(double value) {
    _dispersion = math.max(value, 0.0);
    _markMaterialDataDirty();
  }

  /// Iridescence weight texture.
  TextureSource? get iridescenceTexture => _iridescenceTexture;
  TextureSource? _iridescenceTexture;
  set iridescenceTexture(TextureSource? value) {
    if (identical(_iridescenceTexture, value)) return;
    _iridescenceTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [iridescenceTexture].
  TextureTransform get iridescenceTextureTransform =>
      _iridescenceTextureTransform;
  TextureTransform _iridescenceTextureTransform = TextureTransform();
  set iridescenceTextureTransform(TextureTransform value) {
    _iridescenceTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [iridescenceTexture].
  int get iridescenceTextureTexCoord => _iridescenceTextureTexCoord;
  int _iridescenceTextureTexCoord = 0;
  set iridescenceTextureTexCoord(int value) {
    _iridescenceTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Iridescence layer weight.
  double get iridescence => _iridescence;
  double _iridescence = 0.0;
  set iridescence(double value) {
    _iridescence = value.clamp(0.0, 1.0);
    _markMaterialDataDirty(variant: true);
  }

  /// Iridescent film index of refraction.
  double get iridescenceIor => _iridescenceIor;
  double _iridescenceIor = 1.3;
  set iridescenceIor(double value) {
    _iridescenceIor = math.max(value, 1.0);
    _markMaterialDataDirty();
  }

  /// Iridescent film-thickness texture.
  TextureSource? get iridescenceThicknessTexture =>
      _iridescenceThicknessTexture;
  TextureSource? _iridescenceThicknessTexture;
  set iridescenceThicknessTexture(TextureSource? value) {
    if (identical(_iridescenceThicknessTexture, value)) return;
    _iridescenceThicknessTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [iridescenceThicknessTexture].
  TextureTransform get iridescenceThicknessTextureTransform =>
      _iridescenceThicknessTextureTransform;
  TextureTransform _iridescenceThicknessTextureTransform = TextureTransform();
  set iridescenceThicknessTextureTransform(TextureTransform value) {
    _iridescenceThicknessTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [iridescenceThicknessTexture].
  int get iridescenceThicknessTextureTexCoord =>
      _iridescenceThicknessTextureTexCoord;
  int _iridescenceThicknessTextureTexCoord = 0;
  set iridescenceThicknessTextureTexCoord(int value) {
    _iridescenceThicknessTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Minimum iridescent film thickness in nanometres.
  double get iridescenceThicknessMinimum => _iridescenceThicknessMinimum;
  double _iridescenceThicknessMinimum = 100.0;
  set iridescenceThicknessMinimum(double value) {
    _iridescenceThicknessMinimum = value;
    _markMaterialDataDirty();
  }

  /// Maximum iridescent film thickness in nanometres.
  double get iridescenceThicknessMaximum => _iridescenceThicknessMaximum;
  double _iridescenceThicknessMaximum = 400.0;
  set iridescenceThicknessMaximum(double value) {
    _iridescenceThicknessMaximum = value;
    _markMaterialDataDirty();
  }

  /// Anisotropy direction and strength texture.
  TextureSource? get anisotropyTexture => _anisotropyTexture;
  TextureSource? _anisotropyTexture;
  set anisotropyTexture(TextureSource? value) {
    if (identical(_anisotropyTexture, value)) return;
    _anisotropyTexture = value;
    _markMaterialDataDirty(variant: true);
  }

  /// UV transform applied to [anisotropyTexture].
  TextureTransform get anisotropyTextureTransform =>
      _anisotropyTextureTransform;
  TextureTransform _anisotropyTextureTransform = TextureTransform();
  set anisotropyTextureTransform(TextureTransform value) {
    _anisotropyTextureTransform = value;
    _markMaterialDataDirty();
  }

  /// Texture-coordinate channel used by [anisotropyTexture].
  int get anisotropyTextureTexCoord => _anisotropyTextureTexCoord;
  int _anisotropyTextureTexCoord = 0;
  set anisotropyTextureTexCoord(int value) {
    _anisotropyTextureTexCoord = value.clamp(0, 1);
    _markMaterialDataDirty();
  }

  /// Anisotropic reflection strength.
  double get anisotropy => _anisotropy;
  double _anisotropy = 0.0;
  set anisotropy(double value) {
    _anisotropy = value.clamp(0.0, 1.0);
    _markMaterialDataDirty(variant: true);
  }

  /// Anisotropy direction rotation in radians.
  double get anisotropyRotation => _anisotropyRotation;
  double _anisotropyRotation = 0.0;
  set anisotropyRotation(double value) {
    _anisotropyRotation = value;
    _markMaterialDataDirty();
  }

  static const int _specularFeature = 1 << 0;
  static const int _clearcoatFeature = 1 << 1;
  static const int _sheenFeature = 1 << 2;
  static const int _transmissionFeature = 1 << 3;
  static const int _diffuseTransmissionFeature = 1 << 4;
  static const int _iridescenceFeature = 1 << 5;
  static const int _anisotropyFeature = 1 << 6;
  // Outside the 0x7f physical-feature mask below: a lightmap picks a shader
  // variant without pulling the material onto the physical path.
  static const int _lightmapFeature = 1 << 7;

  int _variantKey = 0;
  bool _materialDataDirty = true;
  PhysicalMaterialVariant? _preparedVariant;

  void _markMaterialDataDirty({bool variant = false}) {
    _materialDataDirty = true;
    if (!variant) return;
    final previousTransmission = _usesTransmissionVariant;
    _variantKey = _computeVariantKey();
    _updateStandardShaderNames();
    if (previousTransmission != _usesTransmissionVariant) {
      markMaterialSceneInputsChanged();
    }
  }

  /// Whether the scalar specular inputs differ from the glTF defaults, in
  /// which case the standard shader's dielectric F0 carries their product.
  bool get _hasScalarSpecularConfiguration =>
      ior != 1.5 ||
      specular != 1.0 ||
      specularColor.x != 1.0 ||
      specularColor.y != 1.0 ||
      specularColor.z != 1.0;

  /// The dielectric specular reflectance at normal incidence the standard
  /// shader path uses for these inputs, `clamp(((ior - 1) / (ior + 1))^2 *
  /// specularColor * specular, 0, 1)` per `KHR_materials_ior` and
  /// `KHR_materials_specular`, which is the same product the physical shader
  /// forms from its material inputs. Returns 0.04 for the defaults.
  @visibleForTesting
  static Vector3 dielectricSpecularF0({
    required double ior,
    required double specular,
    required Vector4 specularColor,
  }) {
    final clampedIor = math.max(ior, 1.0);
    final iorF0 = math.pow((clampedIor - 1.0) / (clampedIor + 1.0), 2.0);
    return Vector3(
      (iorF0 * specularColor.x * specular).clamp(0.0, 1.0).toDouble(),
      (iorF0 * specularColor.y * specular).clamp(0.0, 1.0).toDouble(),
      (iorF0 * specularColor.z * specular).clamp(0.0, 1.0).toDouble(),
    );
  }

  int _computeVariantKey() {
    var key = 0;
    // Scalar ior, specular factor, and specular color fold into the
    // standard shader's dielectric F0 (see dielectricSpecularF0), so only a
    // specular texture needs the physical variant.
    if (specularTexture != null || specularColorTexture != null) {
      key |= _specularFeature;
    }
    if (clearcoat > 0.0) key |= _clearcoatFeature;
    if (sheenColor.x != 0.0 || sheenColor.y != 0.0 || sheenColor.z != 0.0) {
      key |= _sheenFeature;
    }
    if (transmission > 0.0) key |= _transmissionFeature;
    if (diffuseTransmission > 0.0) key |= _diffuseTransmissionFeature;
    if (iridescence > 0.0) key |= _iridescenceFeature;
    if (anisotropy != 0.0) key |= _anisotropyFeature;
    if (lightmapTexture != null) key |= _lightmapFeature;

    final textures = <TextureSource?>[
      specularTexture,
      specularColorTexture,
      clearcoatTexture,
      clearcoatRoughnessTexture,
      clearcoatNormalTexture,
      sheenColorTexture,
      sheenRoughnessTexture,
      transmissionTexture,
      diffuseTransmissionTexture,
      diffuseTransmissionColorTexture,
      thicknessTexture,
      iridescenceTexture,
      iridescenceThicknessTexture,
      anisotropyTexture,
    ];
    for (var i = 0; i < textures.length; i++) {
      if (textures[i] != null) key |= 1 << (16 + i);
    }
    return key;
  }

  /// The feature bitmask that selects this material's shader variant.
  @internal
  @visibleForTesting
  int get variantKey => _variantKey;

  bool get _usesPhysicalVariant => (_variantKey & 0x7f) != 0;

  /// The bit [variantKey] sets when a baked lightmap is bound.
  @internal
  @visibleForTesting
  static int get lightmapVariantBit => _lightmapFeature;

  // A bake is baked into the surface, not refracted through it, so only the
  // opaque material ships lightmap entries.
  // TODO(lightmap-transmission): generate them for the transmission material
  // too if a transmissive lightmapped surface ever comes up.
  bool get _usesLightmapVariant =>
      (_variantKey & _lightmapFeature) != 0 && !_usesTransmissionVariant;

  /// Whether serialization must preserve physical extension state.
  @internal
  bool get hasPhysicalConfiguration =>
      (_computeVariantKey() & ~_lightmapFeature) != 0 ||
      _hasScalarSpecularConfiguration ||
      clearcoatRoughness != 0.0 ||
      clearcoatNormalScale != Vector2.all(1.0) ||
      sheenRoughness != 0.0 ||
      thickness != 0.0 ||
      attenuationDistance != double.infinity ||
      attenuationColor != Vector4.all(1.0) ||
      dispersion != 0.0 ||
      iridescenceIor != 1.3 ||
      iridescenceThicknessMinimum != 100.0 ||
      iridescenceThicknessMaximum != 400.0 ||
      anisotropyRotation != 0.0;

  bool get _usesTransmissionVariant =>
      (_variantKey & _transmissionFeature) != 0;

  // The standard-path entry pair, swapped when a lightmap is bound so the
  // shader that samples it is also the one the lightmap is bound to.
  bool _standardShaderNamesLightmapped = false;

  void _updateStandardShaderNames() {
    final lightmapped = _usesLightmapVariant;
    if (lightmapped == _standardShaderNamesLightmapped) return;
    _standardShaderNamesLightmapped = lightmapped;
    setFragmentShaderName(
      lightmapped ? 'StandardLightmapFragment' : 'StandardFragment',
      cubeName: lightmapped
          ? 'StandardLightmapCubeFragment'
          : 'StandardCubeFragment',
      noShadowName: lightmapped
          ? 'StandardLightmapNoShadowFragment'
          : 'StandardNoShadowFragment',
      noShadowCubeName: lightmapped
          ? 'StandardLightmapNoShadowCubeFragment'
          : 'StandardNoShadowCubeFragment',
    );
  }

  void _ensurePreparedVariant() {
    if (!_materialDataDirty) return;
    if (!_usesPhysicalVariant) {
      _preparedVariant = null;
      _materialDataDirty = false;
      return;
    }
    final lightmapped = _usesLightmapVariant;
    if (lightmapTexture != null && !lightmapped) {
      debugPrint(
        'PhysicallyBasedMaterial "$name" is transmissive, which has no baked '
        'lightmap variant, so its lightmapTexture is ignored. '
        'TODO(lightmap-transmission): generate the lightmap entries for the '
        'transmission material.',
      );
    }
    final descriptor = _toDescriptor();
    final prepared = _preparedVariant;
    if (prepared == null ||
        prepared.transmissive != _usesTransmissionVariant ||
        prepared.lightmapped != lightmapped) {
      _preparedVariant = PhysicalMaterialVariant.fromDescriptor(
        descriptor,
        lightmapped: lightmapped,
      );
    } else {
      prepared.updateDescriptor(descriptor);
    }
    _preparedVariant!.setLightmap(
      _texture(
        lightmapTexture,
        lightmapTextureTransform,
        lightmapTextureTexCoord,
      ),
      intensity: lightmapIntensity,
      rgbm: lightmapRgbm,
    );
    _materialDataDirty = false;
  }

  PhysicalTexture _texture(
    TextureSource? source,
    TextureTransform transform,
    int texCoord,
  ) =>
      PhysicalTexture(source: source, transform: transform, texCoord: texCoord);

  PhysicalMaterialDescriptor _toDescriptor() => PhysicalMaterialDescriptor(
    name: name,
    baseColorTexture: _texture(
      baseColorTexture,
      baseColorTextureTransform,
      baseColorTextureTexCoord,
    ),
    baseColor: baseColorFactor,
    metallicRoughnessTexture: _texture(
      metallicRoughnessTexture,
      metallicRoughnessTextureTransform,
      metallicRoughnessTextureTexCoord,
    ),
    metallic: metallicFactor,
    roughness: roughnessFactor,
    normalTexture: _texture(
      normalTexture,
      normalTextureTransform,
      normalTextureTexCoord,
    ),
    normalScale: normalScale,
    occlusionTexture: _texture(
      occlusionTexture,
      occlusionTextureTransform,
      occlusionTextureTexCoord,
    ),
    occlusionStrength: occlusionStrength,
    emissiveTexture: _texture(
      emissiveTexture,
      emissiveTextureTransform,
      emissiveTextureTexCoord,
    ),
    emissive: emissiveFactor,
    emissiveStrength: emissiveStrength,
    specularTexture: _texture(
      specularTexture,
      specularTextureTransform,
      specularTextureTexCoord,
    ),
    specular: specular,
    specularColorTexture: _texture(
      specularColorTexture,
      specularColorTextureTransform,
      specularColorTextureTexCoord,
    ),
    specularColor: specularColor,
    ior: ior,
    clearcoatTexture: _texture(
      clearcoatTexture,
      clearcoatTextureTransform,
      clearcoatTextureTexCoord,
    ),
    clearcoat: clearcoat,
    clearcoatRoughnessTexture: _texture(
      clearcoatRoughnessTexture,
      clearcoatRoughnessTextureTransform,
      clearcoatRoughnessTextureTexCoord,
    ),
    clearcoatRoughness: clearcoatRoughness,
    clearcoatNormalTexture: _texture(
      clearcoatNormalTexture,
      clearcoatNormalTextureTransform,
      clearcoatNormalTextureTexCoord,
    ),
    clearcoatNormalScale: clearcoatNormalScale,
    sheenColorTexture: _texture(
      sheenColorTexture,
      sheenColorTextureTransform,
      sheenColorTextureTexCoord,
    ),
    sheenColor: sheenColor,
    sheenRoughnessTexture: _texture(
      sheenRoughnessTexture,
      sheenRoughnessTextureTransform,
      sheenRoughnessTextureTexCoord,
    ),
    sheenRoughness: sheenRoughness,
    transmissionTexture: _texture(
      transmissionTexture,
      transmissionTextureTransform,
      transmissionTextureTexCoord,
    ),
    transmission: transmission,
    diffuseTransmissionTexture: _texture(
      diffuseTransmissionTexture,
      diffuseTransmissionTextureTransform,
      diffuseTransmissionTextureTexCoord,
    ),
    diffuseTransmission: diffuseTransmission,
    diffuseTransmissionColorTexture: _texture(
      diffuseTransmissionColorTexture,
      diffuseTransmissionColorTextureTransform,
      diffuseTransmissionColorTextureTexCoord,
    ),
    diffuseTransmissionColor: diffuseTransmissionColor,
    thicknessTexture: _texture(
      thicknessTexture,
      thicknessTextureTransform,
      thicknessTextureTexCoord,
    ),
    thickness: thickness,
    attenuationDistance: attenuationDistance,
    attenuationColor: attenuationColor,
    dispersion: dispersion,
    iridescenceTexture: _texture(
      iridescenceTexture,
      iridescenceTextureTransform,
      iridescenceTextureTexCoord,
    ),
    iridescence: iridescence,
    iridescenceIor: iridescenceIor,
    iridescenceThicknessTexture: _texture(
      iridescenceThicknessTexture,
      iridescenceThicknessTextureTransform,
      iridescenceThicknessTextureTexCoord,
    ),
    iridescenceThicknessMinimum: iridescenceThicknessMinimum,
    iridescenceThicknessMaximum: iridescenceThicknessMaximum,
    anisotropyTexture: _texture(
      anisotropyTexture,
      anisotropyTextureTransform,
      anisotropyTextureTexCoord,
    ),
    anisotropy: anisotropy,
    anisotropyRotation: anisotropyRotation,
    alphaMode: alphaMode,
    alphaCutoff: alphaCutoff,
    doubleSided: doubleSided,
  );

  void _applyDescriptor(PhysicalMaterialDescriptor descriptor) {
    name = descriptor.name;
    _applyTexture(
      descriptor.baseColorTexture,
      (source) => _baseColorTexture = source,
      (transform) => baseColorTextureTransform = transform,
      (texCoord) => baseColorTextureTexCoord = texCoord,
    );
    _baseColorFactor = descriptor.baseColor;
    _applyTexture(
      descriptor.metallicRoughnessTexture,
      (source) => _metallicRoughnessTexture = source,
      (transform) => metallicRoughnessTextureTransform = transform,
      (texCoord) => metallicRoughnessTextureTexCoord = texCoord,
    );
    _metallicFactor = descriptor.metallic;
    _roughnessFactor = descriptor.roughness;
    _applyTexture(
      descriptor.normalTexture,
      (source) => _normalTexture = source,
      (transform) => normalTextureTransform = transform,
      (texCoord) => normalTextureTexCoord = texCoord,
    );
    _normalScale = descriptor.normalScale;
    _applyTexture(
      descriptor.occlusionTexture,
      (source) => _occlusionTexture = source,
      (transform) => occlusionTextureTransform = transform,
      (texCoord) => occlusionTextureTexCoord = texCoord,
    );
    _occlusionStrength = descriptor.occlusionStrength;
    _applyTexture(
      descriptor.emissiveTexture,
      (source) => _emissiveTexture = source,
      (transform) => emissiveTextureTransform = transform,
      (texCoord) => emissiveTextureTexCoord = texCoord,
    );
    _emissiveFactor = descriptor.emissive;
    _emissiveStrength = descriptor.emissiveStrength;
    _applyAdvancedDescriptor(descriptor);
    _alphaMode = descriptor.alphaMode;
    _alphaCutoff = descriptor.alphaCutoff;
    doubleSided = descriptor.doubleSided;
    _variantKey = _computeVariantKey();
    _updateStandardShaderNames();
    _materialDataDirty = true;
  }

  void _applyAdvancedDescriptor(PhysicalMaterialDescriptor d) {
    _applyTextureSlot(
      d.specularTexture,
      (v) => _specularTexture = v,
      (v) => specularTextureTransform = v,
      (v) => specularTextureTexCoord = v,
    );
    _specular = d.specular;
    _applyTextureSlot(
      d.specularColorTexture,
      (v) => _specularColorTexture = v,
      (v) => specularColorTextureTransform = v,
      (v) => specularColorTextureTexCoord = v,
    );
    _specularColor = d.specularColor;
    _ior = d.ior;
    _applyTextureSlot(
      d.clearcoatTexture,
      (v) => _clearcoatTexture = v,
      (v) => clearcoatTextureTransform = v,
      (v) => clearcoatTextureTexCoord = v,
    );
    _clearcoat = d.clearcoat;
    _applyTextureSlot(
      d.clearcoatRoughnessTexture,
      (v) => _clearcoatRoughnessTexture = v,
      (v) => clearcoatRoughnessTextureTransform = v,
      (v) => clearcoatRoughnessTextureTexCoord = v,
    );
    _clearcoatRoughness = d.clearcoatRoughness;
    _applyTextureSlot(
      d.clearcoatNormalTexture,
      (v) => _clearcoatNormalTexture = v,
      (v) => clearcoatNormalTextureTransform = v,
      (v) => clearcoatNormalTextureTexCoord = v,
    );
    clearcoatNormalScale = d.clearcoatNormalScale;
    _applyTextureSlot(
      d.sheenColorTexture,
      (v) => _sheenColorTexture = v,
      (v) => sheenColorTextureTransform = v,
      (v) => sheenColorTextureTexCoord = v,
    );
    _sheenColor = d.sheenColor;
    _applyTextureSlot(
      d.sheenRoughnessTexture,
      (v) => _sheenRoughnessTexture = v,
      (v) => sheenRoughnessTextureTransform = v,
      (v) => sheenRoughnessTextureTexCoord = v,
    );
    sheenRoughness = d.sheenRoughness;
    _applyTextureSlot(
      d.transmissionTexture,
      (v) => _transmissionTexture = v,
      (v) => transmissionTextureTransform = v,
      (v) => transmissionTextureTexCoord = v,
    );
    _transmission = d.transmission;
    _applyTextureSlot(
      d.diffuseTransmissionTexture,
      (v) => _diffuseTransmissionTexture = v,
      (v) => diffuseTransmissionTextureTransform = v,
      (v) => diffuseTransmissionTextureTexCoord = v,
    );
    _diffuseTransmission = d.diffuseTransmission;
    _applyTextureSlot(
      d.diffuseTransmissionColorTexture,
      (v) => _diffuseTransmissionColorTexture = v,
      (v) => diffuseTransmissionColorTextureTransform = v,
      (v) => diffuseTransmissionColorTextureTexCoord = v,
    );
    diffuseTransmissionColor = d.diffuseTransmissionColor;
    _applyTextureSlot(
      d.thicknessTexture,
      (v) => _thicknessTexture = v,
      (v) => thicknessTextureTransform = v,
      (v) => thicknessTextureTexCoord = v,
    );
    thickness = d.thickness;
    attenuationDistance = d.attenuationDistance;
    attenuationColor = d.attenuationColor;
    dispersion = d.dispersion;
    _applyTextureSlot(
      d.iridescenceTexture,
      (v) => _iridescenceTexture = v,
      (v) => iridescenceTextureTransform = v,
      (v) => iridescenceTextureTexCoord = v,
    );
    _iridescence = d.iridescence;
    iridescenceIor = d.iridescenceIor;
    _applyTextureSlot(
      d.iridescenceThicknessTexture,
      (v) => _iridescenceThicknessTexture = v,
      (v) => iridescenceThicknessTextureTransform = v,
      (v) => iridescenceThicknessTextureTexCoord = v,
    );
    iridescenceThicknessMinimum = d.iridescenceThicknessMinimum;
    iridescenceThicknessMaximum = d.iridescenceThicknessMaximum;
    _applyTextureSlot(
      d.anisotropyTexture,
      (v) => _anisotropyTexture = v,
      (v) => anisotropyTextureTransform = v,
      (v) => anisotropyTextureTexCoord = v,
    );
    _anisotropy = d.anisotropy;
    anisotropyRotation = d.anisotropyRotation;
  }

  void _applyTexture(
    PhysicalTexture texture,
    void Function(TextureSource?) setSource,
    void Function(TextureTransform) setTransform,
    void Function(int) setTexCoord,
  ) => _applyTextureSlot(texture, setSource, setTransform, setTexCoord);

  void _applyTextureSlot(
    PhysicalTexture texture,
    void Function(TextureSource?) setSource,
    void Function(TextureTransform) setTransform,
    void Function(int) setTexCoord,
  ) {
    setSource(texture.source);
    setTransform(texture.transform);
    setTexCoord(texture.texCoord);
  }

  @override
  gpu.Shader get fragmentShader {
    _ensurePreparedVariant();
    return _preparedVariant?.fragmentShader ?? super.fragmentShader;
  }

  @override
  gpu.Shader fragmentShaderForLighting(Lighting lighting) {
    _ensurePreparedVariant();
    return _preparedVariant?.fragmentShaderForLighting(lighting) ??
        super.fragmentShaderForLighting(lighting);
  }

  @override
  Set<RenderInput> get sceneInputs => transmission > 0.0
      ? const {RenderInput.opaqueSceneColor, RenderInput.filteredSceneColor}
      : const {};

  @override
  double get sceneColorSampleBoundsExpansion => thickness;

  @override
  double get sceneColorSampleFilterLodFraction =>
      roughnessFactor * (ior * 2.0 - 2.0).clamp(0.0, 1.0).toDouble();

  @override
  bool get translucentDepthWrite => transmission > 0.0;

  /// Strength of geometric specular antialiasing.
  ///
  /// A normal map or high-curvature surface carries more normal detail than a
  /// pixel can resolve, which the specular highlight turns into shimmer as the
  /// camera or surface moves. This estimates that sub-pixel normal variation
  /// from screen-space derivatives and widens the effective roughness to
  /// suppress it (Kaplanyan/Tokuyoshi). `0` disables the effect; the default
  /// (`0.15`) matches the common recommendation.
  double specularAntiAliasingVariance = 0.15;

  /// Upper bound on the extra roughness [specularAntiAliasingVariance] may add,
  /// in the squared-roughness domain. Caps the effect so strongly varying
  /// normals cannot over-roughen a surface. Default `0.2`.
  double specularAntiAliasingThreshold = 0.2;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    _ensurePreparedVariant();
    final prepared = _preparedVariant;
    if (prepared != null) {
      prepared
        ..name = name
        ..doubleSided = doubleSided
        ..depthBias = depthBias
        ..lodFade = lodFade
        ..lightListOffset = lightListOffset
        ..lightListCount = lightListCount
        ..lightChannelMask = lightChannelMask
        ..modelScaleX = modelScaleX
        ..modelScaleY = modelScaleY
        ..modelScaleZ = modelScaleZ
        ..environment = environment;
      prepared.bind(pass, transientsBuffer, lighting);
      return;
    }
    super.bind(pass, transientsBuffer, lighting);

    // The variant the pipeline was built from, which differs from
    // [fragmentShader] when the bound environment picks the cube radiance
    // layout. Slots must come from the shader actually drawn with.
    final shader = fragmentShaderForLighting(lighting);
    final EnvironmentMap env = environment ?? lighting.environmentMap;

    // FragInfo std140 layout (624 bytes / 156 floats). EngineLightingUniforms
    // packs the shared engine lighting, image-based-lighting, and shadow
    // fields (identical for every lit material); this material fills only its
    // own, disjoint fields:
    //   [0..3]    vec4  color
    //   [4..7]    vec4  emissive_factor
    //   [120]     float vertex_color_weight
    //   [121]     float metallic_factor
    //   [122]     float roughness_factor
    //   [123]     float has_normal_map
    //   [124]     float normal_scale
    //   [125]     float occlusion_strength
    //   [132]     float alpha_mode (0 opaque, 1 mask, 2 blend)
    //   [133]     float alpha_cutoff
    //   [138]     float specular_aa_variance
    //   [139]     float specular_aa_threshold
    // A shared scratch (zeroed each bind, matching a fresh allocation's
    // unwritten slots) instead of a per-draw allocation; emplace below copies
    // the bytes out immediately.
    final fragInfo = _fragInfoScratch..fillRange(0, _fragInfoScratch.length, 0);
    EngineLightingUniforms.packInto(
      fragInfo,
      lighting,
      env,
      nodeChannelMask: lightChannelMask,
      modelScaleX: modelScaleX,
      modelScaleY: modelScaleY,
      modelScaleZ: modelScaleZ,
    );
    fragInfo[0] = baseColorFactor.r;
    fragInfo[1] = baseColorFactor.g;
    fragInfo[2] = baseColorFactor.b;
    fragInfo[3] = baseColorFactor.a;
    fragInfo[4] = emissiveFactor.r;
    fragInfo[5] = emissiveFactor.g;
    fragInfo[6] = emissiveFactor.b;
    fragInfo[7] = emissiveStrength;
    fragInfo[120] = vertexColorWeight;
    fragInfo[121] = metallicFactor;
    fragInfo[122] = roughnessFactor;
    fragInfo[123] = normalTexture != null ? 1.0 : 0.0;
    fragInfo[124] = normalScale;
    fragInfo[125] = occlusionStrength;
    fragInfo[132] = alphaMode.index.toDouble();
    fragInfo[133] = alphaCutoff;
    fragInfo[138] = specularAntiAliasingVariance;
    fragInfo[139] = specularAntiAliasingThreshold;
    // dielectric_f0 [172..174]: packInto wrote the plain 0.04; a scalar ior,
    // specular factor, or specular color replaces it with their product so
    // the draw stays on the standard shader.
    if (_hasScalarSpecularConfiguration) {
      final f0 = dielectricSpecularF0(
        ior: ior,
        specular: specular,
        specularColor: specularColor,
      );
      fragInfo[EngineLightingUniforms.dielectricF0Index] = f0.x;
      fragInfo[EngineLightingUniforms.dielectricF0Index + 1] = f0.y;
      fragInfo[EngineLightingUniforms.dielectricF0Index + 2] = f0.z;
    }
    fragInfo[EngineLightingUniforms.fadeIndex] = lodFade;
    // radiance_blend.zw [162]/[163]: this item's punctual-light slice
    // (count, offset) into the per-frame light-index buffer.
    fragInfo[162] = lightListCount.toDouble();
    fragInfo[163] = lightListOffset.toDouble();
    pass.bindUniform(
      shader.getUniformSlot("FragInfo"),
      transientsBuffer.emplace(_fragInfoBytes),
    );

    final textureTransforms = _textureTransformsScratch;
    _packTextureTransform(
      textureTransforms,
      0,
      baseColorTextureTransform,
      baseColorTextureTexCoord,
    );
    _packTextureTransform(
      textureTransforms,
      8,
      metallicRoughnessTextureTransform,
      metallicRoughnessTextureTexCoord,
    );
    _packTextureTransform(
      textureTransforms,
      16,
      normalTextureTransform,
      normalTextureTexCoord,
    );
    _packTextureTransform(
      textureTransforms,
      24,
      emissiveTextureTransform,
      emissiveTextureTexCoord,
    );
    _packTextureTransform(
      textureTransforms,
      32,
      occlusionTextureTransform,
      occlusionTextureTexCoord,
    );
    // The base record's padding float carries one flag the shader branches on
    // to skip the five UV-transform evaluations, set when any record
    // transforms its UVs or selects UV set 1. The identity transform
    // reproduces the raw UV bit-exactly, so the flag only gates work.
    final transformedUvs =
        !baseColorTextureTransform.isIdentity ||
        !metallicRoughnessTextureTransform.isIdentity ||
        !normalTextureTransform.isIdentity ||
        !emissiveTextureTransform.isIdentity ||
        !occlusionTextureTransform.isIdentity ||
        baseColorTextureTexCoord != 0 ||
        metallicRoughnessTextureTexCoord != 0 ||
        normalTextureTexCoord != 0 ||
        emissiveTextureTexCoord != 0 ||
        occlusionTextureTexCoord != 0;
    textureTransforms[7] = transformedUvs ? 1.0 : 0.0;
    pass.bindUniform(
      shader.getUniformSlot('TextureTransforms'),
      transientsBuffer.emplace(ByteData.sublistView(textureTransforms)),
    );

    _bindSlot(pass, shader, 'base_color_texture', baseColorTexture);
    _bindSlot(pass, shader, 'emissive_texture', emissiveTexture);
    _bindSlot(
      pass,
      shader,
      'metallic_roughness_texture',
      metallicRoughnessTexture,
    );
    _bindSlot(pass, shader, 'normal_texture', normalTexture, normal: true);
    _bindSlot(pass, shader, 'occlusion_texture', occlusionTexture);
    // Image-based-lighting atlas, BRDF LUT, and shadow map. Shared with
    // PreprocessedMaterial: the sampler choices (radiance repeat/clamp, LUT
    // clamp/clamp, shadow nearest/clamp) and the white shadow placeholder
    // live in EngineLightingUniforms.
    EngineLightingUniforms.bindEngineTextures(
      pass,
      shader,
      lighting,
      env,
      // The no-shadow twin declares no shadow_map sampler; the same call
      // that picked `shader` above decides whether the slot exists.
      bindShadows: !usesNoShadowVariant(lighting),
      bindDiffuseSh: !_usesLightmapVariant,
      cubeShader: usesRadianceCubeVariant(lighting),
    );
    // The same condition picked `shader`, so the lightmap goes to a shader
    // that declares its sampler.
    if (_usesLightmapVariant) {
      EngineLightingUniforms.bindLightmap(
        pass,
        shader,
        transientsBuffer,
        texture: resolveTextureSource(lightmapTexture),
        transform: lightmapTextureTransform,
        texCoord: lightmapTextureTexCoord,
        intensity: lightmapIntensity,
        rgbm: lightmapRgbm,
        sampler: textureSourceSampler(lightmapTexture),
      );
    }
    EngineLightingUniforms.bindFog(pass, shader, transientsBuffer, lighting);
  }

  static final Float32List _fragInfoScratch = Float32List(
    EngineLightingUniforms.fragInfoFloatCount,
  );
  static final ByteData _fragInfoBytes = ByteData.sublistView(_fragInfoScratch);

  static final Float32List _textureTransformsScratch = Float32List(40);

  static void _packTextureTransform(
    Float32List target,
    int offset,
    TextureTransform transform,
    int texCoord,
  ) {
    target[offset] = transform.offset.x;
    target[offset + 1] = transform.offset.y;
    target[offset + 2] = transform.scale.x;
    target[offset + 3] = transform.scale.y;
    target[offset + 4] = math.cos(transform.rotation);
    target[offset + 5] = math.sin(transform.rotation);
    target[offset + 6] = texCoord.clamp(0, 1).toDouble();
    target[offset + 7] = 0.0;
  }

  static final gpu.SamplerOptions _repeatSampler = gpu.SamplerOptions(
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.repeat,
  );

  // Binds one texture slot, substituting the neutral placeholder when the
  // slot is empty (or its render texture has no completed frame yet). A
  // RenderTexture source brings its own sampler; static textures use the
  // material's repeat default.
  void _bindSlot(
    gpu.RenderPass pass,
    gpu.Shader shader,
    String name,
    TextureSource? source, {
    bool normal = false,
  }) {
    final resolved = resolveTextureSource(source);
    pass.bindTexture(
      shader.getUniformSlot(name),
      normal
          ? Material.normalPlaceholder(resolved)
          : Material.whitePlaceholder(resolved),
      sampler: textureSourceSampler(source) ?? _repeatSampler,
    );
  }

  @override
  gpu.Texture? get reflectionRoughnessTexture =>
      resolveTextureSource(metallicRoughnessTexture);

  @override
  TextureTransform get reflectionRoughnessTextureTransform =>
      metallicRoughnessTextureTransform;

  @override
  int get reflectionRoughnessTextureTexCoord =>
      metallicRoughnessTextureTexCoord;

  @override
  gpu.SamplerOptions? get reflectionRoughnessTextureSampler =>
      textureSourceSampler(metallicRoughnessTexture);

  @override
  double get reflectionRoughnessFactor => roughnessFactor;

  @override
  bool get depthAlphaMasked => alphaMode == AlphaMode.mask;

  @override
  void bindDepthAlphaMask(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {
    // Mirrors the coverage the color pass tests in Surface():
    // texture.a * weighted vertex-color alpha * baseColorFactor alpha.
    final params = Float32List(12)
      ..[0] = alphaCutoff
      ..[1] = baseColorFactor.a
      ..[2] = vertexColorWeight;
    _packTextureTransform(
      params,
      4,
      baseColorTextureTransform,
      baseColorTextureTexCoord,
    );
    pass.bindUniform(
      shader.getUniformSlot('MaskInfo'),
      transientsBuffer.emplace(ByteData.sublistView(params)),
    );
    pass.bindTexture(
      shader.getUniformSlot('mask_texture'),
      Material.whitePlaceholder(resolveTextureSource(baseColorTexture)),
      sampler: textureSourceSampler(baseColorTexture) ?? _repeatSampler,
    );
  }

  @override
  bool isOpaque() {
    // BLEND always goes through the translucent pass. OPAQUE and MASK
    // are drawn in the opaque pass (MASK relies on the shader's
    // alpha-test discard); a sub-1 baseColorFactor alpha still forces
    // the translucent pass so directly-constructed translucent
    // materials keep working without an explicit alpha mode.
    if (transmission > 0.0 || alphaMode == AlphaMode.blend) return false;
    return baseColorFactor.a >= 1.0;
  }
}
