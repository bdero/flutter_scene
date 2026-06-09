/// The visible background drawn behind a scene, and the sources that
/// describe what it looks like.
library;

/// A source of skybox color as a function of world-space view direction.
///
/// A [Skybox] wraps a source and the engine draws it behind all scene
/// geometry. The built-in source today is [EnvironmentSkySource]; custom
/// shader-driven and procedural sources are planned.
abstract class SkySource {
  const SkySource();
}

/// Shows the scene's image-based-lighting environment as the background,
/// optionally blurred.
///
/// Samples `Scene.environment`'s prefiltered-radiance atlas along each view
/// ray. [blurriness] selects how rough (and so how blurred) the sampled band
/// is: `0.0` shows the sharp environment, `1.0` shows the fully-blurred band.
/// The same atlas drives specular reflections, so a blurred background stays
/// consistent with what reflective surfaces show.
class EnvironmentSkySource extends SkySource {
  EnvironmentSkySource({this.blurriness = 0.0});

  /// How blurred the background is, from `0.0` (sharp) to `1.0` (fully
  /// blurred). Clamped to that range when sampled.
  double blurriness;
}

/// The visible background drawn behind a [Scene].
///
/// Assign one to `Scene.skybox`. The skybox is decoupled from the scene's
/// image-based lighting (`Scene.environment`): the default
/// [EnvironmentSkySource] shows that same environment, but the two can be set
/// independently. The engine draws the skybox behind all scene geometry at
/// the far plane; you never place or order any geometry yourself.
class Skybox {
  Skybox(this.source, {this.intensity = 1.0});

  /// What the sky looks like.
  SkySource source;

  /// Scales the sampled radiance. It is combined with
  /// `Scene.environmentIntensity`, so a default skybox showing the
  /// environment matches the brightness of image-based reflections.
  double intensity;
}
