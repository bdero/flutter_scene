/// The optional material shader families a build can leave out, shared by the
/// build hooks and the runtime.
library;

/// An optional material feature whose shaders the hook can leave out.
///
/// Each one is built by default and loaded only when a material first uses
/// it, so a project that never uses it pays app size and nothing else. A
/// project that sets it to `false` under flutter_scene's `material_features`
/// hook user-define drops its shaders from the build, and a material asking
/// for it then draws without it (with one debug warning).
enum MaterialFeature {
  /// Parallax occlusion mapping (`PhysicallyBasedMaterial.parallaxScale`).
  /// Off also drops [parallaxSilhouette], which builds on it.
  parallaxOcclusion('parallax_occlusion'),

  /// Silhouette parallax (`PhysicallyBasedMaterial.parallaxSilhouette`).
  parallaxSilhouette('parallax_silhouette');

  const MaterialFeature(this.key);

  /// The name under the `material_features` user-define.
  final String key;

  /// The base-bundle entry whose presence records that this feature was left
  /// out. It is never drawn.
  String get markerEntryName =>
      'MaterialFeatureOff${name[0].toUpperCase()}${name.substring(1)}';
}

/// The features [value] (a `material_features` user-define) leaves out.
///
/// [value] maps feature keys to booleans, and only `false` leaves a feature
/// out. Leaving out [MaterialFeature.parallaxOcclusion] leaves out
/// [MaterialFeature.parallaxSilhouette] too. Null means none. Throws a
/// [FormatException] naming the valid keys for anything else.
Set<MaterialFeature> parseCompiledOutMaterialFeatures(Object? value) {
  if (value == null) return const {};
  final valid = MaterialFeature.values.map((f) => f.key).join(', ');
  if (value is! Map) {
    throw FormatException(
      'flutter_scene: material_features must map feature names to true or '
      'false. Valid names: $valid.',
    );
  }
  final off = <MaterialFeature>{};
  for (final MapEntry(:key, value: enabled) in value.entries) {
    final feature = MaterialFeature.values
        .where((f) => f.key == key)
        .firstOrNull;
    if (feature == null) {
      throw FormatException(
        'flutter_scene: unknown material feature "$key". Valid names: $valid.',
      );
    }
    if (enabled is! bool) {
      throw FormatException(
        'flutter_scene: material_features.$key must be true or false.',
      );
    }
    if (!enabled) off.add(feature);
  }
  if (off.contains(MaterialFeature.parallaxOcclusion)) {
    off.add(MaterialFeature.parallaxSilhouette);
  }
  return off;
}

/// A stable description of [features] for build stamps and file variants, or
/// the empty string when there are none.
String describeCompiledOutMaterialFeatures(Set<MaterialFeature> features) {
  if (features.isEmpty) return '';
  final keys = [for (final f in features) f.key]..sort();
  return keys.join(',');
}

/// The file-variant suffix naming the features left out of a build, so
/// builds with different sets sharing one tree write different files.
String materialFeaturesVariantSuffix(Set<MaterialFeature> features) =>
    features.isEmpty
    ? ''
    : ' material_off=${describeCompiledOutMaterialFeatures(features)}';
