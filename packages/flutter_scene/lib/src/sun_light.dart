/// Drives a scene's directional light (and its cast shadows) from a sky's sun.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/skybox.dart';

/// Aims a scene's directional light at a [SunSky]'s sun, so cast shadows track
/// the sky.
///
/// Assign one to `Scene.sunLight` to have the scene shade and shadow from the
/// same sun the sky draws: each frame the binding points its [light] opposite
/// the sky's `sunDirection` and recolors it from the sky's sun. Pair it with a
/// `SkyEnvironment` driven by the same sky so the soft image-based lighting and
/// the hard shadow agree:
///
/// ```dart
/// final sky = PhysicalSkySource();
/// scene.skybox = Skybox(sky);
/// scene.skyEnvironment = SkyEnvironment(sky);
/// scene.sunLight = SunLight(sky, castsShadow: true);
/// ```
///
/// While set, the binding owns `Scene.directionalLight` (it replaces and then
/// keeps updating that light); setting `directionalLight` by hand has no
/// lasting effect. Cascaded shadows need a perspective camera.
/// {@category Lighting and environment}
class SunLight {
  /// Creates a binding that aims a directional light at [source]'s sun.
  ///
  /// [color] and [intensity] override the sky-derived sun color and intensity
  /// when non-null; otherwise they follow the sky. [intensityScale] always
  /// multiplies the final intensity. The shadow fields mirror
  /// [DirectionalLight]'s and are applied to [light].
  SunLight(
    this.source, {
    this.castsShadow = true,
    this.intensityScale = 1.0,
    this.priority = 0,
    this.color,
    this.intensity,
    this.cacheStaticShadows = true,
    this.shadowSoftness = 0.08,
    this.shadowMaxDistance = 150.0,
    this.shadowCascadeCount = 4,
    this.shadowMapResolution = 1024,
    this.shadowDepthBias = 0.02,
    this.shadowNormalBias = 0.02,
    this.shadowFadeRange = 2.0,
    this.shadowCascadeSplitLambda = 0.6,
    this.shadowAmbientStrength = 0.0,
    this.shadowFilter = DirectionalShadowFilter.rotatedPoisson,
    this.contactShadows = false,
    this.contactShadowDistance = 0.3,
    this.angularRadius = 0.005,
    this.shadowCasterFaces = ShadowCasterFaces.front,
  });

  /// The sky whose sun aims the light.
  SunSky source;

  /// Whether the derived light casts shadows.
  bool castsShadow;

  /// Multiplies the (sky-derived or overridden) intensity.
  double intensityScale;

  /// Selects this sun for primary directional-light features. Higher values
  /// win; see [DirectionalLight.priority].
  int priority;

  /// Overrides the sky-derived sun color when non-null.
  Vector3? color;

  /// Overrides the sky-derived sun intensity when non-null.
  double? intensity;

  /// Whether static shadow casters are cached; see
  /// [DirectionalLight.cacheStaticShadows].
  bool cacheStaticShadows;

  /// World-space penumbra radius; see [DirectionalLight.shadowSoftness].
  double shadowSoftness;

  /// Shadow view distance; see [DirectionalLight.shadowMaxDistance].
  double shadowMaxDistance;

  /// Number of shadow cascades; see [DirectionalLight.shadowCascadeCount].
  int shadowCascadeCount;

  /// Per-cascade shadow-map resolution; see
  /// [DirectionalLight.shadowMapResolution].
  int shadowMapResolution;

  /// Depth bias; see [DirectionalLight.shadowDepthBias].
  double shadowDepthBias;

  /// Normal bias; see [DirectionalLight.shadowNormalBias].
  double shadowNormalBias;

  /// Far-edge fade band; see [DirectionalLight.shadowFadeRange].
  double shadowFadeRange;

  /// Cascade split blend; see [DirectionalLight.shadowCascadeSplitLambda].
  double shadowCascadeSplitLambda;

  /// How much the shadow also darkens the IBL ambient; see
  /// [DirectionalLight.shadowAmbientStrength]. Useful here because a
  /// [SkyEnvironment] bakes the sun into the ambient, so a plain shadow leaves
  /// shadowed areas reading as fully lit.
  double shadowAmbientStrength;

  /// Shadow sampling pattern; see [DirectionalLight.shadowFilter].
  DirectionalShadowFilter shadowFilter;

  /// Screen-space contact shadows; see [DirectionalLight.contactShadows].
  bool contactShadows;

  /// Contact-shadow march distance; see
  /// [DirectionalLight.contactShadowDistance].
  double contactShadowDistance;

  /// Light angular radius for soft-shadow penumbras; see
  /// [DirectionalLight.angularRadius].
  double angularRadius;

  /// Which faces are rendered into the shadow map; see
  /// [DirectionalLight.shadowCasterFaces].
  ShadowCasterFaces shadowCasterFaces;

  /// The managed light. Mutated in place by [resolve] each frame so the scene
  /// graph need not re-register a new light when the sun moves.
  final DirectionalLight light = DirectionalLight();

  /// Updates [light] from the current sun and returns it. Called by the engine
  /// once per frame before the scene is shaded; not part of the app-facing API.
  DirectionalLight resolve() {
    // The sun direction points toward the sun; the light travels the other way.
    light.direction
      ..setFrom(source.sunDirection)
      ..negate();
    light.color.setFrom(color ?? source.sunLightColor);
    light.castsShadow = castsShadow;
    light.intensity = (intensity ?? source.sunLightIntensity) * intensityScale;
    light.priority = priority;
    light.cacheStaticShadows = cacheStaticShadows;
    light.shadowSoftness = shadowSoftness;
    light.shadowMaxDistance = shadowMaxDistance;
    light.shadowCascadeCount = shadowCascadeCount;
    light.shadowMapResolution = shadowMapResolution;
    light.shadowDepthBias = shadowDepthBias;
    light.shadowNormalBias = shadowNormalBias;
    light.shadowFadeRange = shadowFadeRange;
    light.shadowCascadeSplitLambda = shadowCascadeSplitLambda;
    light.shadowAmbientStrength = shadowAmbientStrength;
    light.shadowFilter = shadowFilter;
    light.contactShadows = contactShadows;
    light.contactShadowDistance = contactShadowDistance;
    light.angularRadius = angularRadius;
    light.shadowCasterFaces = shadowCasterFaces;
    return light;
  }
}
