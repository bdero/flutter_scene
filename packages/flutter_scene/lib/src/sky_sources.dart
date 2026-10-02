/// Built-in procedural sky sources.
library;

import 'dart:math' as math;
import 'dart:typed_data';

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
  // The uniform block, rewritten in place each bind.
  final Float32List _info = Float32List(20);
  late final ByteData _infoBytes = ByteData.sublistView(_info);

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
    final info = _info;
    _put3(info, 0, zenithColor, 1.0);
    _put3(info, 4, horizonColor, 1.0);
    _put3(info, 8, groundColor, 1.0);
    _put3(info, 12, sunDirection, sunSharpness);
    _put3(info, 16, sunColor, 1.0);
    setUniformBlock('GradientSkyInfo', _infoBytes);
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
  // The uniform block, rewritten in place each bind.
  final Float32List _info = Float32List(20);
  late final ByteData _infoBytes = ByteData.sublistView(_info);

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
    final info = _info;
    _put3(info, 0, sunDirection, sunAngularRadius);
    _put3(info, 4, rayleighColor, rayleighCoefficient);
    _put3(info, 8, mieColor, mieCoefficient);
    info[12] = turbidity;
    info[13] = mieEccentricity;
    info[14] = energy;
    info[15] = 0.0;
    _put3(info, 16, groundColor, 1.0);
    setUniformBlock('PhysicalSkyInfo', _infoBytes);
    super.bind(pass, transientsBuffer, environment);
  }
}

// Writes [v] and then [w] into [out] at [offset], one std140 vec4.
void _put3(Float32List out, int offset, Vector3 v, double w) {
  out[offset] = v.x;
  out[offset + 1] = v.y;
  out[offset + 2] = v.z;
  out[offset + 3] = w;
}
