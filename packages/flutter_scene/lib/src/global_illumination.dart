import 'dart:math' as math;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/engine_compute_shaders.dart';
import 'package:flutter_scene/src/render/render_quality.dart';
import 'package:vector_math/vector_math.dart';

/// Global illumination settings for a [Scene].
///
/// A world-space grid of irradiance probes caches bounce light, so indirect
/// light persists for surfaces the camera is not currently looking at and
/// colored bleed reads correctly. Probes are filled by [feed], either by
/// gathering the previous frame's shaded scene color into the grid or by
/// tracing rays from each probe, so lighting changes converge over a few
/// frames rather than snapping.
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
  /// Under the screen-space [feed], enabling it forces the depth prepass with
  /// normals on, the same way [AmbientOcclusionSettings.enabled] forces the
  /// prepass, because the screen-space gather reads both. The traced feed
  /// needs neither.
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

  /// How the field learns the scene's light. See [IrradianceFeed].
  IrradianceFeed feed = IrradianceFeed.screenSpace;

  // TODO(gi-sh-receiver): carry this through the scene document and the
  // editor's environment settings.
  /// How lit surfaces read the field. See [IrradianceFieldReceiver].
  IrradianceFieldReceiver receiver = IrradianceFieldReceiver.automatic;

  /// The screen sample density the screen-space feed's weights stand for.
  /// See [IrradianceInjectionResolution]. Unused by the traced feed.
  IrradianceInjectionResolution injectionResolution =
      IrradianceInjectionResolution.eighth;

  /// Clamps radiance entering the field by luminance, preserving hue, so a
  /// single very bright pixel or ray cannot burn a probe. `0` disables the
  /// clamp.
  double fireflyClamp = 8.0;

  /// Scales emissive surfaces' contribution to the injected radiance, so a
  /// small bright emitter can light a room without blowing out the direct
  /// image. `1.0` injects emission at the same strength it is shaded.
  ///
  /// Emitters the camera cannot see contribute nothing under the
  /// screen-space feed. Trace ([IrradianceFeed.rayTraced]) or bake
  /// ([Scene.bakeIrradianceField]) the field for those.
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

/// How a scene's irradiance field is fed.
/// {@category Lighting and environment}
enum IrradianceFeed {
  /// Gathers samples of the previous frame's shaded screen into the probes.
  /// Works on every backend, and sees only what is on screen.
  screenSpace,

  /// Traces rays from every probe against the scene in a compute pass, so
  /// off-screen emitters, walls, and sky all reach the field, and moves
  /// probes out of geometry. Needs compute, which WebGL2, OpenGL ES, and
  /// Flutter before 3.53 lack; check [isSupported] before choosing it. Where
  /// it is unsupported the field stays off rather than switching feeds, since
  /// the screen-space feed reaches far less of the scene.
  ///
  /// Traces static and skinned meshes with their base color and emissive
  /// textures, the sun, and punctual lights. Morph targets and rect area
  /// lights are not traced yet. While it runs, skinned meshes are skinned
  /// once per frame in a compute pass, which their draws reuse.
  rayTraced;

  /// Whether this device can feed the field this way. Always true for
  /// [screenSpace]. Read it once the scene's static resources have loaded.
  bool get isSupported => switch (this) {
    screenSpace => true,
    rayTraced => gpu.supportsCompute && !EngineComputeShaders.failed,
  };
}

/// How lit surfaces read a scene's irradiance field.
/// {@category Lighting and environment}
enum IrradianceFieldReceiver {
  /// [sphericalHarmonics] below [RenderQualityTier.high] and on Android
  /// at its platform default tier, [full] otherwise. With
  /// [RenderQualitySettings.adaptiveGlobalIllumination], also drops to
  /// [sphericalHarmonics] when frames overrun.
  automatic,

  /// Eight probes per surface point, each weighted by whether it can see the
  /// point, which keeps light from leaking through walls. About 24 texture
  /// reads per lit pixel.
  full,

  /// Each probe reduced to linear spherical harmonics after it updates, read
  /// with six filtered texture reads and no visibility test, for mobile and
  /// low-end GPUs. Light leaks through walls thinner than about one probe
  /// spacing, and retired probes borrow their neighbours' light.
  sphericalHarmonics,
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

// TODO(gi-gather): deprecate this, or repurpose it as the samples each probe
// gathers per frame.
/// The screen sample density the screen-space feed's weights stand for, as a
/// fraction of the render target. Each probe gathers a fixed 64 samples per
/// frame whatever this is, so it no longer changes the feed's cost. A finer
/// density weights each sample more, so a direction the screen barely covers
/// stops falling back to the environment sooner.
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

/// The resolved probe lattice the global-illumination field is filling, as
/// read back from a live [Scene] for visualization.
///
/// The field's placement is derived per frame from the volume mode, the
/// camera, and the scene bounds, so an editor cannot re-derive it reliably;
/// read it with `Scene.globalIlluminationProbeGrid` instead.
/// {@category Lighting and environment}
class IrradianceProbeGrid {
  const IrradianceProbeGrid({
    required this.origin,
    required this.spacing,
    required this.counts,
  });

  /// World position of the minimum-corner probe.
  final Vector3 origin;

  /// World-space distance between neighbouring probes, per axis.
  final Vector3 spacing;

  /// Probe count along each axis.
  final Vector3 counts;

  /// Total probes in the lattice.
  int get probeCount => counts.x.round() * counts.y.round() * counts.z.round();

  /// World position of the probe at lattice offset ([x], [y], [z]) from
  /// [origin].
  Vector3 probePosition(int x, int y, int z) => Vector3(
    origin.x + x * spacing.x,
    origin.y + y * spacing.y,
    origin.z + z * spacing.z,
  );
}

/// How many times the adaptive controller may halve a field's probe refresh.
const int kIrradianceBudgetSteps = 2;

/// What [settings]' field renders with this frame: whether lit surfaces read
/// spherical harmonics, the probes refreshed per frame (0 for all), and how
/// many adaptive steps the field offers. [adaptiveSteps] are taken in order,
/// an automatic receiver reading the full field drops to spherical
/// harmonics, then the refresh halves [kIrradianceBudgetSteps] times.
/// [solving] is false while the field is not refreshed at all.
///
/// Not exported.
({bool sphericalHarmonics, int probeUpdateBudget, int adaptiveSteps})
resolveIrradianceFieldQuality({
  required GlobalIlluminationSettings settings,
  required bool automaticSh,
  required int probeCount,
  required bool solving,
  int adaptiveSteps = 0,
}) {
  var steps = adaptiveSteps;
  var sh = switch (settings.receiver) {
    IrradianceFieldReceiver.full => false,
    IrradianceFieldReceiver.sphericalHarmonics => true,
    IrradianceFieldReceiver.automatic => automaticSh,
  };
  final receiverStep =
      settings.receiver == IrradianceFieldReceiver.automatic && !sh;
  if (receiverStep && steps > 0) {
    sh = true;
    steps--;
  }
  final budgetSteps = solving ? kIrradianceBudgetSteps : 0;
  var budget = settings.probeUpdateBudget <= 0
      ? probeCount
      : math.min(settings.probeUpdateBudget, probeCount);
  budget = math.max(1, budget >> math.min(steps, budgetSteps));
  return (
    sphericalHarmonics: sh,
    probeUpdateBudget: budget >= probeCount ? 0 : budget,
    adaptiveSteps: (receiverStep ? 1 : 0) + budgetSteps,
  );
}
