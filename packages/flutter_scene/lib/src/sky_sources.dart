/// Built-in procedural sky sources.
library;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:vector_math/vector_math.dart';

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
class GradientSkySource extends ShaderSkySource {
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
       super(fragmentShader: baseShaderLibrary['SkyGradientFragment']!);

  /// The sky color straight up.
  Vector3 zenithColor;

  /// The sky color at the horizon.
  Vector3 horizonColor;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Direction toward the sun (world space; normalized when used).
  Vector3 sunDirection;

  /// The sun disk color, in linear HDR (values above 1.0 read as a bright
  /// sun through the tone mapper and light the scene strongly when baked).
  Vector3 sunColor;

  /// Sharpness exponent of the sun disk; higher is tighter.
  double sunSharpness;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
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
class PhysicalSkySource extends ShaderSkySource {
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
       super(fragmentShader: baseShaderLibrary['SkyPhysicalFragment']!);

  /// Direction toward the sun (world space; normalized when used).
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

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
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
