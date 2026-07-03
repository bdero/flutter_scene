import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// How fog density grows with distance from the camera.
///
/// [linear] ramps from [Fog.start] to [Fog.end]; [exponential] and
/// [exponentialSquared] are density-driven (Beer-Lambert), the exponential
/// modes matching what most real-time engines call `exp`/`exp2`.
/// {@category Lighting and environment}
enum FogMode { none, linear, exponential, exponentialSquared }

/// Distance fog for a [Scene]: geometry blends toward [color] the farther it is
/// from the camera, evaluated per-fragment in linear HDR before tone mapping so
/// fog is exposed and tone-mapped along with the scene.
///
/// Fog is a `Scene` setting (`scene.fog`), off by default. Set [enabled] and a
/// [mode] to turn it on. It applies to lit and unlit materials alike (the
/// skybox is left unfogged, so set [color] to your horizon color for distant
/// geometry to dissolve into the sky).
///
/// Two cheap extras: [heightFalloff] makes the fog ground-hugging (thinning with
/// altitude, [exponential] mode only), and [sunInScatter] adds a glow toward the
/// scene's directional light so looking into the sun through fog brightens.
/// {@category Lighting and environment}
class Fog {
  /// Whether fog is applied. False (the default) leaves the scene unfogged even
  /// if a [mode] is set.
  bool enabled = false;

  /// The distance-to-density curve. [FogMode.none] disables fog regardless of
  /// [enabled].
  FogMode mode = FogMode.exponential;

  /// Fog color, linear (not sRGB). Distant opaque geometry converges to this, so
  /// matching it to the horizon color makes geometry dissolve into the sky.
  Vector3 color = Vector3(0.6, 0.7, 0.8);

  /// How much the fog color is taken from the sky instead of [color] (0 = flat
  /// [color], 1 = fully the environment sampled in the view direction). Above 0,
  /// far geometry fades into the actual sky/horizon behind it (aerial
  /// perspective) rather than a flat wall of [color]. Sampled from the
  /// image-based-lighting environment, so it applies to lit materials; unlit
  /// materials always use the flat [color].
  double skyColorInfluence = 0.0;

  /// Density for [FogMode.exponential] and [FogMode.exponentialSquared]. Larger
  /// is thicker. See [visibilityDensity] for a distance-based way to set it.
  double density = 0.02;

  /// Distance at which fog begins. For [FogMode.linear] this is the near end; for
  /// the exponential modes it offsets where accumulation starts (near geometry
  /// stays clear).
  double start = 0.0;

  /// Distance at which [FogMode.linear] reaches full [maxOpacity]. Unused by the
  /// exponential modes.
  double end = 200.0;

  /// Upper bound on fog opacity (0 to 1). Below 1 the fog never fully hides
  /// distant geometry, so a bright sky still shows through.
  double maxOpacity = 1.0;

  /// Distance past which fog is not applied (0 disables the cutoff). Useful to
  /// exclude a far layer that already reads as hazed.
  double cutoffDistance = 0.0;

  /// Reference altitude (world Y) for height fog: where the fog is densest.
  double height = 0.0;

  /// How fast fog thins with altitude above [height] (0 = uniform, no height
  /// fog). Only affects [FogMode.exponential]. Larger hugs the ground more
  /// tightly.
  double heightFalloff = 0.0;

  /// Strength of the in-scattering glow toward the scene's directional light
  /// (0 = off). Cheap sun-through-fog without volumetrics.
  double sunInScatter = 0.0;

  /// Tightness of the sun in-scatter cone: larger concentrates the glow near the
  /// sun. Only meaningful when [sunInScatter] is above 0.
  double sunInScatterExponent = 8.0;

  /// The [density] that makes objects roughly [meters] away fade to a
  /// low-contrast haze, via Koschmieder's law (contrast threshold `0.02`). A
  /// convenience for authoring exponential fog by visibility distance instead of
  /// a raw coefficient.
  static double visibilityDensity(double meters) =>
      meters <= 0.0 ? 0.0 : -math.log(0.02) / meters;
}
