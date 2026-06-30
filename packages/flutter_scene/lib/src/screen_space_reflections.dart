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
}
