/// A diagnostic visualization for [ScreenSpaceReflectionsSettings.debugView].
///
/// Replaces the composited image with an intermediate of the reflection
/// trace, for tuning and debugging. [composite] is the normal output.
/// {@category Rendering}
enum SsrDebugView {
  /// The normal reflection-composited image.
  composite,

  /// The screen UV the reflected ray hit (red/green), scaled by confidence.
  reflectedUv,

  /// White where a reflection hit was accepted, black otherwise.
  hitMask,

  /// The per-pixel view-space normal read from the depth prepass.
  normal,

  /// The accepted hit's confidence (the reflection blend weight).
  confidence,

  /// The raw linear depth the trace marches against.
  depth,
}

/// Screen-space reflection settings for a [Scene].
///
/// Reachable through `Scene.screenSpaceReflections`. Screen-space
/// reflections (SSR) trace the rendered image to add sharp, view-dependent
/// reflections on top of the smooth image-based reflections every surface
/// already receives from the scene environment. A surface the trace cannot
/// resolve (a ray that leaves the screen, finds no hit, or lands on too
/// rough a surface) falls back to that environment reflection, so SSR is a
/// refinement layer and never removes reflection detail.
///
/// Disabled by default: a fresh scene does no reflection tracing and adds no
/// render passes. Set [enabled] to turn it on.
///
/// The trace reconstructs view-space positions and normals from a camera
/// depth prepass, so it needs only a depth buffer (no normal buffer) and
/// fits a forward renderer. It requires a [PerspectiveCamera]; other camera
/// types render without it.
/// {@category Rendering}
class ScreenSpaceReflectionsSettings {
  /// Whether screen-space reflections run. Off by default. When false the
  /// scene adds no reflection passes and the image is unaffected.
  ///
  /// Enabling this schedules the shared camera depth prepass (also used by
  /// ambient occlusion); the reflection trace reads it.
  bool enabled = false;

  /// Overall strength of the reflections, multiplying the per-pixel blend
  /// weight. `1.0` is the physical estimate; lower values fade reflections
  /// out, higher values exaggerate them.
  double intensity = 1.0;

  /// How far, in world units, a reflected ray is marched before it is
  /// considered to have missed. Larger values let reflections reach more
  /// distant geometry at a higher trace cost.
  double maxDistance = 24.4;

  /// The assumed world-space thickness of surfaces, used to accept a ray
  /// crossing as a hit. Too small misses thin or grazing geometry; too large
  /// lets a ray passing behind an object falsely reflect it.
  double thickness = 0.46;

  /// Pixels advanced along the screen per march step. `1` samples every
  /// pixel the reflection crosses (highest quality, most costly); larger
  /// values sample more sparsely and cheaply, but can step over thin or
  /// grazing surfaces. This sets the reflection quality; [maxSteps] bounds
  /// its cost.
  double stride = 9.0;

  /// The maximum number of march steps, a hard cost ceiling. Clamped to the
  /// shader's maximum (currently 256). A reflection that reaches this budget
  /// fades out (see [distanceFadeStart]) rather than cutting off.
  int maxSteps = 90;

  /// Glossy blur applied to the reflected color, `0` for a sharp mirror.
  /// Higher values soften the reflection (and hide trace noise), widening
  /// with the hit distance.
  double blur = 0.3;

  /// Where the reflection begins fading out, as a fraction (0..1) of its
  /// reachable range (the closer of [maxDistance] and the [stride]/[maxSteps]
  /// budget). Reflections ramp to zero from here to the range limit, so they
  /// taper smoothly instead of hard-cutting. `1.0` disables the fade; `0.0`
  /// fades gradually across the whole range.
  double distanceFadeStart = 0.0;

  /// The resolution the reflections are traced at, as a fraction (0..1) of
  /// the render size. `1.0` traces at full resolution; lower values trace
  /// (and blur) the reflection layer more cheaply and bilinear-upscale it,
  /// leaving the rest of the image full resolution. The single biggest
  /// performance lever, and the main one to lower on mobile.
  double resolutionScale = 1.0;

  /// A diagnostic visualization to render instead of the composited image.
  /// Defaults to [SsrDebugView.composite] (the normal output).
  SsrDebugView debugView = SsrDebugView.composite;
}
