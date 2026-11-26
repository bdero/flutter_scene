/// The lit-shader features a build can compile out, shared by the build hooks
/// and the runtime.
library;

/// A lighting feature the hook can compile out of every lit shader.
///
/// A project that never uses one sets it to `false` under flutter_scene's
/// `lighting_features` hook user-define, and the engine and material bundles
/// are built without it. The lit shaders get smaller, which shortens their
/// first-draw compile on backends that compile at run time (several seconds
/// for the full lit shader on ANGLE's Direct3D backend). A scene that enables a
/// compiled-out feature draws without it.
enum LightingFeature {
  irradianceField('irradiance_field', 'FLUTTER_SCENE_NO_IRRADIANCE_FIELD'),
  rectAreaLights('rect_area_lights', 'FLUTTER_SCENE_NO_RECT_AREA_LIGHTS'),
  environmentBlending(
    'environment_blending',
    'FLUTTER_SCENE_NO_ENVIRONMENT_BLEND',
  ),
  parallaxReflection(
    'parallax_reflection',
    'FLUTTER_SCENE_NO_PARALLAX_REFLECTION',
  ),
  ambientOcclusion(
    'ambient_occlusion',
    'FLUTTER_SCENE_NO_SCREEN_SPACE_OCCLUSION',
  ),
  pointShadows('point_shadows', 'FLUTTER_SCENE_NO_POINT_SHADOWS');

  const LightingFeature(this.key, this.define);

  /// The name under the `lighting_features` user-define.
  final String key;

  /// The GLSL define that compiles the feature out (see
  /// `material_lighting.glsl`).
  final String define;

  /// The base-bundle entry whose presence records that this feature was
  /// compiled out. It is never drawn.
  String get markerEntryName =>
      'LightingFeatureOff${name[0].toUpperCase()}${name.substring(1)}';
}

/// The features [value] (a `lighting_features` user-define) turns off.
///
/// [value] maps feature keys to booleans, and only `false` compiles a feature
/// out. Null means none. Throws a [FormatException] naming the valid keys for
/// anything else.
// TODO(lighting-features-auto): accept `auto`, inferred from the project's
// assets and scenes by the hook.
Set<LightingFeature> parseCompiledOutLightingFeatures(Object? value) {
  if (value == null) return const {};
  final valid = LightingFeature.values.map((f) => f.key).join(', ');
  if (value is! Map) {
    throw FormatException(
      'flutter_scene: lighting_features must map feature names to true or '
      'false. Valid names: $valid.',
    );
  }
  final off = <LightingFeature>{};
  for (final MapEntry(:key, value: enabled) in value.entries) {
    final feature = LightingFeature.values
        .where((f) => f.key == key)
        .firstOrNull;
    if (feature == null) {
      throw FormatException(
        'flutter_scene: unknown lighting feature "$key". Valid names: $valid.',
      );
    }
    if (enabled is! bool) {
      throw FormatException(
        'flutter_scene: lighting_features.$key must be true or false.',
      );
    }
    if (!enabled) off.add(feature);
  }
  return off;
}

/// A stable description of [features] for build stamps and file variants, or
/// the empty string when there are none.
String describeCompiledOutLightingFeatures(Set<LightingFeature> features) {
  if (features.isEmpty) return '';
  final keys = [for (final f in features) f.key]..sort();
  return keys.join(',');
}

/// The file-variant suffix naming the features compiled out of a bundle, so
/// builds with different sets sharing one tree write different files.
String lightingFeaturesVariantSuffix(Set<LightingFeature> features) =>
    features.isEmpty
    ? ''
    : ' lighting_off=${describeCompiledOutLightingFeatures(features)}';
