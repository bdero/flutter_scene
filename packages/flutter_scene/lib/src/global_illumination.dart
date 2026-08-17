import 'package:vector_math/vector_math.dart';

/// Global illumination settings for a [Scene].
///
/// A world-space grid of irradiance probes caches bounce light, so indirect
/// light persists for surfaces the camera is not currently looking at and
/// colored bleed reads correctly. Probes are filled by scattering the
/// previous frame's shaded scene color into the grid, so lighting changes
/// converge over a few frames rather than snapping.
///
/// Disabled by default. A fresh scene adds no probe passes.
///
/// The field replaces the environment's smooth diffuse term inside its
/// volume and fades back to it at the boundary, so it never double-counts
/// image-based lighting. Indirect specular is untouched; reflection probes
/// and environment volumes keep owning it.
///
/// Wall thickness is a content rule, not a renderer setting. A wall thinner
/// than one probe spacing leaks light regardless of [visibility], and walls
/// modeled as zero-thickness planes always leak. Build solids.
/// {@category Lighting and environment}
class GlobalIlluminationSettings {
  /// Whether the irradiance field runs. Off by default; a fresh scene adds
  /// no probe passes.
  ///
  /// Enabling it forces the depth prepass with normals on, the same way
  /// [AmbientOcclusionSettings.enabled] forces the prepass, because the
  /// injection scatter reads both.
  bool enabled = false;

  /// How the field's world-space volume is placed. See
  /// [IrradianceVolumeMode].
  IrradianceVolumeMode volumeMode = IrradianceVolumeMode.followCamera;

  /// Probe count along each axis. The product is the probe count and drives
  /// the atlas size. Aim for roughly one probe every 2 to 3 world units.
  ///
  /// Denser is not better. A dense grid localizes each probe's influence and
  /// starts to reveal the grid structure, so reach for [shadowBias] and
  /// [visibility] before raising this. Values are clamped so the atlas fits
  /// a portable texture dimension.
  Vector3 resolution = Vector3(16, 8, 16);

  /// World-space size of the volume. Ignored by
  /// [IrradianceVolumeMode.fitScene], which derives it from the scene
  /// bounds, and by [IrradianceVolumeMode.component], which takes it from
  /// the active [IrradianceVolumeComponent].
  Vector3 extents = Vector3(20, 10, 20);

  /// Scales the field's contribution to indirect diffuse. `1.0` is the
  /// energy-matched result; lower values fade back toward the environment.
  double intensity = 1.0;

  /// Fraction of a probe's previous value kept each update, expressed at a
  /// 60 Hz reference cadence so a throttled frame rate converges at the same
  /// wall-clock rate instead of blending in more noise. Higher converges
  /// more slowly and more stably. The published useful band is 0.85 to 0.98.
  double hysteresis = 0.95;

  /// Scales the offset applied to the shading point before the cage lookup,
  /// as a multiple of the smallest cell edge. Absorbs the octahedral
  /// averaging error so flat surfaces do not self-shadow. Expressed relative
  /// to cell size on purpose, so it does not have to be retuned for scene
  /// scale.
  double shadowBias = 0.3;

  /// Strength of the depth-moment visibility test, `0` disabling it (pure
  /// trilinear, smoother but leaks through thin walls) and `1` applying it
  /// fully. Also see [visibilityBias].
  ///
  /// Setting this to `0` compiles the receiver's depth fetches out, halving
  /// its texture work.
  double visibility = 0.7;

  /// Depth bias for the visibility test, as a fraction of the smallest cell
  /// edge. Must stay under the thinnest wall the scene expects to block
  /// light. Too small and flat surfaces self-shadow into splotches; too
  /// large and thin geometry leaks.
  double visibilityBias = 0.08;

  /// How many probes the blend and filter passes refresh each frame. `0`
  /// refreshes all of them. Lower values amortize the cost over more frames
  /// and converge proportionally slower.
  ///
  /// A nonzero budget under a moving light produces a visible update wave
  /// crossing the scene, so it is a quality tradeoff rather than a free win.
  int probeUpdateBudget = 0;

  /// Resolution of the downsampled buffer the screen-space injection
  /// scatters from. Each texel becomes one scattered sample per frame.
  IrradianceInjectionResolution injectionResolution =
      IrradianceInjectionResolution.eighth;

  /// Clamps injected radiance by luminance, preserving hue, so a single very
  /// bright pixel cannot burn a probe. `0` disables the clamp.
  double fireflyClamp = 8.0;

  /// Scales emissive surfaces' contribution to the injected radiance, so a
  /// small bright emitter can light a room without blowing out the direct
  /// image. `1.0` injects emission at the same strength it is shaded.
  ///
  /// Emitters the camera cannot see contribute nothing under injection
  /// alone. Bake the field ([Scene.bakeIrradianceField]) for those.
  double emissiveGiBoost = 1.0;

  /// Holds the field static while the camera moves and resumes updating once
  /// it comes to rest. Visually near-lossless for an inspect-style viewer and
  /// much cheaper; wrong for a game camera, so it is off by default.
  // TODO(gi-idle-gate): a continuous history-persistence value that rises as
  // the camera slows would degrade more gracefully than this boolean, the
  // way Babylon's IBL shadow remanence does.
  bool updateWhenIdleOnly = false;

  /// Freezes injection so the field holds whatever a bake left in it,
  /// costing nothing per frame beyond the receiver. Ignored when the field
  /// has no bake.
  bool bakeOnly = false;
}

/// Where a scene's irradiance volume sits.
/// {@category Lighting and environment}
enum IrradianceVolumeMode {
  /// Fitted once to the scene's static world bounds, with padding. Best for
  /// a scene that fits in one grid.
  fitScene,

  /// Centered on the camera and snapped to the probe grid, so the volume
  /// scrolls as the camera travels and only the probes that scrolled in need
  /// refilling. Best for a large or streaming world.
  followCamera,

  /// Placed by an [IrradianceVolumeComponent] in the scene graph.
  component,
}

/// Resolution of the buffer screen-space irradiance injection scatters from,
/// as a fraction of the render target. Each texel becomes one scattered
/// sample per frame, so a coarser buffer costs proportionally less vertex
/// work and converges proportionally slower.
/// {@category Lighting and environment}
enum IrradianceInjectionResolution {
  /// Half the render target on each axis.
  half(2),

  /// A quarter of the render target on each axis.
  quarter(4),

  /// An eighth of the render target on each axis. The default.
  eighth(8),

  /// A sixteenth of the render target on each axis.
  sixteenth(16);

  const IrradianceInjectionResolution(this.divisor);

  /// How far each axis of the render target is divided down.
  final int divisor;
}
