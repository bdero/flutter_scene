/// Built-in procedural sky sources.
library;

import 'dart:math' as math;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// A stylized gradient sky: zenith, horizon, and ground colors with an HDR
/// sun disk.
///
/// A built-in [ShaderSkySource], so it works everywhere a custom sky does:
/// assign it to `Scene.skybox` for the visible background and to
/// `Scene.skyEnvironment` (or bake with `EnvironmentMap.fromSky`) to light
/// the scene from it. Fields are plain properties read every frame; mutate
/// them freely (the visible sky updates immediately, the lighting per the
/// binding's refresh policy).
///
/// Like every Geometry and Material constructor, construct only after
/// `Scene.initializeStaticResources` completes.
/// {@category Lighting and environment}
class GradientSkySource extends ShaderSkySource implements SunSky {
  GradientSkySource({
    Vector3? zenithColor,
    Vector3? horizonColor,
    Vector3? groundColor,
    Vector3? sunDirection,
    Vector3? sunColor,
    this.sunSharpness = 400.0,
  }) : zenithColor = zenithColor ?? Vector3(0.05, 0.18, 0.55),
       horizonColor = horizonColor ?? Vector3(0.45, 0.62, 0.90),
       groundColor = groundColor ?? Vector3(0.16, 0.14, 0.12),
       sunDirection = sunDirection ?? Vector3(0.4, 0.5, 0.6),
       sunColor = sunColor ?? Vector3(3.0, 2.7, 2.2),
       super(fragmentShaderName: 'SkyGradientFragment');

  /// The sky color straight up.
  Vector3 zenithColor;

  /// The sky color at the horizon.
  Vector3 horizonColor;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Direction toward the sun (world space; normalized when used).
  @override
  Vector3 sunDirection;

  /// The sun disk color, in linear HDR (values above 1.0 read as a bright
  /// sun through the tone mapper and light the scene strongly when baked).
  Vector3 sunColor;

  /// Sharpness exponent of the sun disk; higher is tighter.
  double sunSharpness;

  // The directional-light color/intensity split the HDR [sunColor] into a
  // unit-ish hue and a magnitude, so the derived light matches the disk.
  @override
  Vector3 get sunLightColor {
    final peak = sunLightIntensity;
    return peak > 0 ? sunColor / peak : Vector3(1, 1, 1);
  }

  @override
  double get sunLightIntensity =>
      math.max(sunColor.x, math.max(sunColor.y, sunColor.z));

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    EnvironmentMap environment,
  ) {
    setUniformBlockFromFloats('GradientSkyInfo', <double>[
      ...zenithColor.storage,
      1.0,
      ...horizonColor.storage,
      1.0,
      ...groundColor.storage,
      1.0,
      ...sunDirection.storage,
      sunSharpness,
      ...sunColor.storage,
      1.0,
    ]);
    super.bind(pass, transientsBuffer, environment);
  }
}

/// A physically based daylight sky: an analytic single-scattering atmosphere
/// (Rayleigh and Mie terms) with an HDR sun disk, producing plausible day,
/// sunset, and twilight skies from a sun direction.
///
/// A built-in [ShaderSkySource], so it works everywhere a custom sky does:
/// assign it to `Scene.skybox` for the visible background and to
/// `Scene.skyEnvironment` (or bake with `EnvironmentMap.fromSky`) to light
/// the scene from it. Fields are plain properties read every frame; animate
/// [sunDirection] for a day-night cycle (the visible sky updates immediately,
/// the lighting per the binding's refresh policy). The model is closed-form
/// (no ray march), so the per-frame background draw stays cheap.
///
/// Like every Geometry and Material constructor, construct only after
/// `Scene.initializeStaticResources` completes.
/// {@category Lighting and environment}
class PhysicalSkySource extends ShaderSkySource implements SunSky {
  PhysicalSkySource({
    Vector3? sunDirection,
    this.sunAngularRadius = 0.0175,
    this.rayleighCoefficient = 2.0,
    Vector3? rayleighColor,
    this.mieCoefficient = 0.005,
    this.mieEccentricity = 0.8,
    Vector3? mieColor,
    this.turbidity = 10.0,
    Vector3? groundColor,
    this.energy = 1.0,
  }) : sunDirection = sunDirection ?? Vector3(0.4, 0.5, 0.6),
       rayleighColor = rayleighColor ?? Vector3(0.26, 0.41, 0.58),
       mieColor = mieColor ?? Vector3(0.69, 0.73, 0.81),
       groundColor = groundColor ?? Vector3(0.12, 0.12, 0.13),
       super(fragmentShaderName: 'SkyPhysicalFragment');

  /// Direction toward the sun (world space; normalized when used).
  @override
  Vector3 sunDirection;

  /// Angular radius of the sun disk, in radians. The physical sun is about
  /// 0.0047; the larger default reads better at typical field of views.
  double sunAngularRadius;

  /// Strength of molecular (Rayleigh) scattering, the blue of the sky.
  double rayleighCoefficient;

  /// Wavelength tint of the Rayleigh term.
  Vector3 rayleighColor;

  /// Strength of aerosol (Mie) scattering, the haze around the sun.
  double mieCoefficient;

  /// Forward-scattering eccentricity of the Mie term (0 = uniform,
  /// approaching 1 = tightly forward around the sun).
  double mieEccentricity;

  /// Wavelength tint of the Mie term.
  Vector3 mieColor;

  /// Aerosol density. Higher values read hazier.
  double turbidity;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Overall intensity multiplier.
  double energy;

  // TODO(physical-sun-radiance): derive the color from the atmosphere's
  // transmittance toward [sunDirection] so the light reddens and dims near the
  // horizon, matching the rendered disk. For now a neutral daylight sun scaled
  // by [energy].
  @override
  Vector3 get sunLightColor => Vector3(1.0, 0.98, 0.95);

  @override
  double get sunLightIntensity => 3.0 * energy;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    EnvironmentMap environment,
  ) {
    setUniformBlockFromFloats('PhysicalSkyInfo', <double>[
      ...sunDirection.storage,
      sunAngularRadius,
      ...rayleighColor.storage,
      rayleighCoefficient,
      ...mieColor.storage,
      mieCoefficient,
      turbidity,
      mieEccentricity,
      energy,
      0.0,
      ...groundColor.storage,
      1.0,
    ]);
    super.bind(pass, transientsBuffer, environment);
  }
}

/// A daylight sky with weather: the analytic atmosphere of
/// [PhysicalSkySource] under a procedural cloud layer, plus the overcast and
/// lightning controls a storm driver animates.
///
/// The clouds are a flat layer projected onto the view ray rather than a march
/// through a volume. A sky is drawn once per frame over every pixel, so a
/// march would cost more than the rest of the frame's shading; a projected
/// layer with a shaped noise field gets the silhouette, the wind, and the
/// horizon compression for a handful of taps. What it does not get is
/// self-shadowing between separate cloud decks or a cloud passing between the
/// camera and a mountain: this is a sky, not geometry.
///
/// [coverage] is the dial that matters. It is a threshold the noise field has
/// to clear, not a multiplier, so raising it grows existing clouds outward
/// rather than fading a uniform haze up from nothing.
///
/// Animate [windOffset] for drift and [flash] for lightning;
/// [LightningComponent] drives both alongside [stormDarkening]. Like every
/// Geometry and Material constructor, construct only after
/// `Scene.initializeStaticResources` completes.
/// {@category Lighting and environment}
class WeatherSkySource extends ShaderSkySource implements SunSky {
  WeatherSkySource({
    Vector3? sunDirection,
    this.sunAngularRadius = 0.0175,
    this.rayleighCoefficient = 2.0,
    Vector3? rayleighColor,
    this.mieCoefficient = 0.005,
    this.mieEccentricity = 0.8,
    Vector3? mieColor,
    this.turbidity = 10.0,
    Vector3? groundColor,
    this.energy = 1.0,
    this.coverage = 0.45,
    this.density = 0.95,
    this.altitude = 1.6,
    this.detail = 0.5,
    this.softness = 0.12,
    this.seed = 1337,
    Vector2? windOffset,
    Vector2? wind,
    Vector3? cloudColor,
    this.cloudShading = 0.85,
    this.stormDarkening = 0.0,
    this.flash = 0.0,
  }) : sunDirection = sunDirection ?? Vector3(0.4, 0.5, 0.6),
       rayleighColor = rayleighColor ?? Vector3(0.26, 0.41, 0.58),
       mieColor = mieColor ?? Vector3(0.69, 0.73, 0.81),
       groundColor = groundColor ?? Vector3(0.12, 0.12, 0.13),
       windOffset = windOffset ?? Vector2.zero(),
       wind = wind ?? Vector2(0.35, 0.1),
       cloudColor = cloudColor ?? Vector3(1.0, 1.0, 1.02),
       super(fragmentShaderName: 'SkyWeatherFragment');

  /// Direction toward the sun (world space; normalized when used).
  @override
  Vector3 sunDirection;

  /// Angular radius of the sun disk, in radians.
  double sunAngularRadius;

  /// Strength of molecular (Rayleigh) scattering, the blue of the sky.
  double rayleighCoefficient;

  /// Wavelength tint of the Rayleigh term.
  Vector3 rayleighColor;

  /// Strength of aerosol (Mie) scattering, the haze around the sun.
  double mieCoefficient;

  /// Forward-scattering eccentricity of the Mie term.
  double mieEccentricity;

  /// Wavelength tint of the Mie term.
  Vector3 mieColor;

  /// Aerosol density. Higher values read hazier.
  double turbidity;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Overall intensity multiplier.
  double energy;

  /// How much of the sky the clouds take, `0` clear to `1` overcast.
  double coverage;

  /// How opaque the clouds are where they are thickest.
  double density;

  /// How high the layer sits in the dome projection. Lower values stretch the
  /// clouds further toward the horizon, which reads as a higher, flatter deck.
  double altitude;

  /// Extra noise octaves, `0` to `1`. More detail is wispier and costs three
  /// more taps per pixel at the top of the range.
  double detail;

  /// How wide the transition from clear sky to cloud is. Small values give
  /// hard-edged cartoon clouds, large values give haze.
  double softness;

  /// The noise seed. Changing it gives a different sky with the same weather.
  int seed;

  /// The layer's current scroll, in layer space. A driver advances this by
  /// [wind] each frame; set it directly for a deterministic replay.
  Vector2 windOffset;

  /// Layer-space drift per second, applied to [windOffset] by [advance].
  Vector2 wind;

  /// The colour lit cloud tops take, before the sun's own tint.
  Vector3 cloudColor;

  /// How far the shadowed underside of a cloud darkens toward [cloudColor],
  /// `0` keeping the lit colour everywhere. This is what gives a cloud its
  /// sense of volume.
  double cloudShading;

  /// How overcast the sky is, `0` none to `1` full gloom. Drains the sky
  /// toward its own extinction colour rather than toward grey, so an overcast
  /// noon stays blue-grey and an overcast sunset stays warm.
  double stormDarkening;

  /// The current lightning flash, `0` none to `1` full. Lights the clouds from
  /// inside (brightest where they are thickest, the opposite of the sun) and
  /// lifts the whole sky a little.
  double flash;

  /// Advances the cloud drift by [deltaSeconds].
  void advance(double deltaSeconds) {
    windOffset.x += wind.x * deltaSeconds;
    windOffset.y += wind.y * deltaSeconds;
  }

  // As PhysicalSkySource: a neutral daylight sun scaled by energy, dimmed by
  // the overcast so a storm does not stay lit like noon.
  @override
  Vector3 get sunLightColor => Vector3(1.0, 0.98, 0.95);

  @override
  double get sunLightIntensity =>
      3.0 * energy * (1.0 - 0.75 * stormDarkening.clamp(0.0, 1.0));

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    EnvironmentMap environment,
  ) {
    setUniformBlockFromFloats('WeatherSkyInfo', <double>[
      ...sunDirection.storage,
      sunAngularRadius,
      ...rayleighColor.storage,
      rayleighCoefficient,
      ...mieColor.storage,
      mieCoefficient,
      turbidity,
      mieEccentricity,
      energy,
      0.0,
      ...groundColor.storage,
      1.0,
      coverage,
      density,
      altitude,
      detail,
      windOffset.x,
      windOffset.y,
      seed.toDouble(),
      softness,
      ...cloudColor.storage,
      cloudShading,
      stormDarkening,
      flash,
      0.0,
      0.0,
    ]);
    super.bind(pass, transientsBuffer, environment);
  }
}
