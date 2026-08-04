/// Screen-space ambient occlusion settings for a [Scene].
///
/// Reachable through `Scene.ambientOcclusion`. Ambient occlusion darkens
/// the indirect (image-based) lighting in creases, cavities, and contact
/// points that the smooth environment term would otherwise leave evenly
/// lit. The result reads as soft contact shadowing on edges and concave
/// geometry.
///
/// Disabled by default: a fresh scene does no ambient-occlusion work and
/// adds no render passes. Set [enabled] to turn it on.
///
/// The technique evaluates normalized angular obscurance from a camera depth
/// prepass. It takes only a depth buffer (the per-pixel normal is reconstructed
/// from depth), so it fits a forward renderer with no normal buffer, and runs
/// as full-screen fragment passes with no compute.
///
/// The depth hierarchy and sampling follow McGuire et al., "Scalable Ambient
/// Obscurance" (2012),
/// https://research.nvidia.com/publication/scalable-ambient-obscurance.
/// {@category Rendering}
class AmbientOcclusionSettings {
  /// Whether ambient occlusion runs. Off by default. When false the scene
  /// adds no ambient-occlusion passes and the lighting is unaffected.
  bool enabled = false;

  /// World-space radius the occlusion is gathered over. Larger values
  /// darken broader cavities; smaller values keep occlusion to tight
  /// contact creases.
  double radius = 0.33;

  /// Nonnegative scalar applied to averaged obscurance before conversion to
  /// visibility. `0.0` removes screen-space occlusion. Output obscurance
  /// saturates at `0.98` before [power] is applied.
  double intensity = 2.0;

  /// Contrast power applied to the final visibility. Values above `1.0`
  /// deepen already-occluded regions without increasing the raw estimate.
  double power = 1.5;

  /// Strength of the four immediate-neighbour samples. This restores tight
  /// contact detail that the wider sampling disk and blur can soften.
  double detail = 0.5;

  /// Distance, in world units, a sampled surface must sit in front of the
  /// shaded point before it counts as an occluder. Lifts the estimate off
  /// the surface so a flat plane does not occlude itself.
  double bias = 0.07;

  /// Minimum sine of the sample angle above the surface horizon. Samples
  /// closer to tangent are rejected to prevent shallow surfaces from
  /// self-occluding because of depth precision and coarse tessellation.
  double horizonAngle = 0.06;

  /// Fraction of screen-space occlusion applied to analytic direct lights.
  /// `0.0` affects indirect lighting only, while `1.0` affects both equally.
  double directLightAffect = 0.0;

  /// Number of samples taken per pixel. More samples cut noise at a
  /// roughly linear cost. Reasonable values are about 8 to 32.
  int sampleCount = 16;

  /// Evaluates the occlusion buffer at half resolution and bilaterally
  /// upsamples it, cutting the occlusion pixel work to a quarter at the
  /// cost of fine detail. Recommended on mobile.
  bool halfResolution = true;

  /// Renders the depth prepass at full resolution and samples it through a
  /// downsampled mip chain (a level per sample distance), instead of rasterising
  /// the depth at the occlusion resolution.
  ///
  /// This is the Scalable Ambient Obscurance depth-mip design. It keeps the
  /// depth accurate where the projection compresses a large range into few
  /// pixels (a steep grazing surface or a vertex-displaced "curved world"), so
  /// the occlusion of near geometry is not contaminated by the far surface
  /// behind it, and it keeps large radii cache-friendly. The cost is a
  /// full-resolution depth prepass plus the chain build, so it is off by default
  /// and best reserved for higher-end targets.
  bool depthMipChain = false;

  /// How indirect specular reflections are occluded. See
  /// [SpecularAmbientOcclusionMode].
  SpecularAmbientOcclusionMode specularMode = SpecularAmbientOcclusionMode.none;
}

/// How [AmbientOcclusionSettings] occludes indirect specular reflections.
///
/// Ambient occlusion is fundamentally a diffuse-visibility estimate, so
/// occluding the specular lobe with the same factor over-darkens glossy
/// reflections. These modes select how (or whether) the specular lobe is
/// occluded.
/// {@category Rendering}
enum SpecularAmbientOcclusionMode {
  /// Indirect specular is not occluded by ambient occlusion. Cheapest and
  /// the default.
  none,

  /// Indirect specular is occluded by an empirical estimate derived from
  /// the diffuse occlusion, the view angle, and roughness (Lagarde and de
  /// Rousiers 2014, "Physically Based Rendering" course notes,
  /// section 4.10.2). Cheap; tightens reflections in cavities on smoother
  /// surfaces while leaving rough surfaces unchanged.
  simple,
}
