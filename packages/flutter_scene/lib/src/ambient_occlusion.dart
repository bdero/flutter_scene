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
/// Two estimators are available through [method]. Both take only a depth
/// buffer (the per-pixel normal is reconstructed from depth), so they fit a
/// forward renderer with no normal buffer, and both run as full-screen
/// fragment passes with no compute.
/// {@category Rendering}
class AmbientOcclusionSettings {
  /// Whether ambient occlusion runs. Off by default. When false the scene
  /// adds no ambient-occlusion passes and the lighting is unaffected.
  bool enabled = false;

  /// Which occlusion estimator runs. See [AmbientOcclusionMethod].
  AmbientOcclusionMethod method = AmbientOcclusionMethod.obscurance;

  /// World-space radius the occlusion is gathered over. Larger values
  /// darken broader cavities; smaller values keep occlusion to tight
  /// contact creases.
  double radius = 0.33;

  /// Nonnegative scalar on the occlusion strength. `1.0` is each method's
  /// calibrated look ([AmbientOcclusionMethod.groundTruth] matches ray-traced
  /// visibility there; [AmbientOcclusionMethod.obscurance] is normalized to
  /// its tuned strength), so the same value reads consistently across both
  /// methods. `0.0` removes screen-space occlusion. Output obscurance
  /// saturates at `0.98` before [power] is applied.
  double intensity = 1.0;

  /// Contrast power applied to the final visibility. Values above `1.0`
  /// deepen already-occluded regions without increasing the raw estimate.
  double power = 1.5;

  /// Strength of the four immediate-neighbour samples. This restores tight
  /// contact detail that the wider sampling disk and blur can soften.
  ///
  /// Only used by [AmbientOcclusionMethod.obscurance].
  double detail = 0.5;

  /// Distance, in world units, a sampled surface must sit in front of the
  /// shaded point before it counts as an occluder. Lifts the estimate off
  /// the surface so a flat plane does not occlude itself.
  ///
  /// Only used by [AmbientOcclusionMethod.obscurance].
  double bias = 0.07;

  /// Minimum sine of the sample angle above the surface horizon. Samples
  /// closer to tangent are rejected to prevent shallow surfaces from
  /// self-occluding because of depth precision and coarse tessellation.
  ///
  /// Only used by [AmbientOcclusionMethod.obscurance].
  double horizonAngle = 0.06;

  /// Fraction of screen-space occlusion applied to analytic direct lights.
  /// `0.0` affects indirect lighting only, while `1.0` affects both equally.
  double directLightAffect = 0.0;

  /// How much bounce light the occluded indirect diffuse term keeps, from
  /// `0.0` (occlusion darkens toward black) to `1.0` (occlusion converges
  /// toward the surface albedo, so creases keep color instead of going
  /// gray). Uses the fitted multi-bounce model from Jimenez et al. 2016.
  double multiBounce = 0.0;

  /// Number of samples taken per pixel. More samples cut noise at a
  /// roughly linear cost. Reasonable values are about 8 to 32.
  ///
  /// Only used by [AmbientOcclusionMethod.obscurance];
  /// [AmbientOcclusionMethod.groundTruth] samples
  /// `sliceCount * stepsPerSlice * 2` texels per pixel.
  int sampleCount = 16;

  /// Number of hemisphere slices integrated per pixel by
  /// [AmbientOcclusionMethod.groundTruth]. More slices cut directional noise
  /// at a linear cost. Reasonable values are 2 to 4; the shader caps at 8.
  int sliceCount = 3;

  /// Depth samples marched along each side of a slice by
  /// [AmbientOcclusionMethod.groundTruth]. More steps resolve occluders more
  /// precisely across the radius. Reasonable values are 2 to 4; the shader
  /// caps at 8.
  int stepsPerSlice = 3;

  /// Strength of one-bounce screen-space indirect light gathered along the
  /// occlusion march, `0.0` (the default) disabling it. Radiance from the
  /// previous frame's scene color is credited to each newly visible sector,
  /// so lit surfaces bleed their color onto neighbors. Requires
  /// [AmbientOcclusionMethod.groundTruth] with [visibilityBitmask]; while
  /// active the chain renders in half-float and the sun's contact shadows
  /// are unavailable (the channels carry radiance instead).
  ///
  /// The history is reprojected through the previous frame's camera, so the
  /// bounce stays put under camera motion; light bounced off a *moving*
  /// object still lags one frame.
  /// TODO(velocity-reprojection): object motion needs a velocity pass, the
  /// same infrastructure temporal anti-aliasing would introduce.
  double indirectLight = 0.0;

  /// Models occluders as surfaces with a constant [thickness] instead of an
  /// infinitely thick height field, by marking occluded sectors of the
  /// hemisphere in a per-slice bitmask. Cuts the over-darkening that thin
  /// geometry (wires, leaves, thin frames) casts at the cost of losing the
  /// cosine weighting of the closed-form arc integration. Only used by
  /// [AmbientOcclusionMethod.groundTruth].
  bool visibilityBitmask = false;

  /// Assumed occluder thickness in world units when [visibilityBitmask] is
  /// enabled. Surfaces stop occluding the hemisphere beyond this depth
  /// behind their front face.
  double thickness = 0.5;

  /// How quickly a horizon decays when the march walks past an occluder,
  /// from `0.0` (horizons never decay, thin occluders over-darken) to `1.0`
  /// (each farther sample fully replaces the horizon). Small values are
  /// enough. Only used by [AmbientOcclusionMethod.groundTruth] when
  /// [visibilityBitmask] is disabled.
  double thicknessHeuristic = 0.004;

  /// Also computes the bent normal (the average unoccluded direction) and
  /// carries it with the occlusion. Indirect diffuse then samples irradiance
  /// along the bent normal, so occluded surfaces stop picking up light from
  /// directions that are blocked, and
  /// [SpecularAmbientOcclusionMode.bentCone] becomes available. The bent
  /// normal is geometric (reconstructed from depth), so it does not carry
  /// normal-map detail. Only used by [AmbientOcclusionMethod.groundTruth]
  /// when [visibilityBitmask] is disabled.
  bool bentNormals = false;

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

/// Which screen-space occlusion estimator [AmbientOcclusionSettings] runs.
/// {@category Rendering}
enum AmbientOcclusionMethod {
  /// Normalized angular obscurance averaged over a spiral sampling disk,
  /// with a four-neighbour detail term. The cheapest estimate and the
  /// default. Tuned by [AmbientOcclusionSettings.sampleCount],
  /// [AmbientOcclusionSettings.bias], [AmbientOcclusionSettings.horizonAngle],
  /// and [AmbientOcclusionSettings.detail].
  ///
  /// The sampling follows McGuire et al., "Scalable Ambient Obscurance"
  /// (2012), https://research.nvidia.com/publication/scalable-ambient-obscurance.
  obscurance,

  /// Horizon-based visibility integrated over hemisphere slices, matching
  /// the cosine-weighted reference that ray-traced occlusion converges to.
  /// Reads more coherent contact shadowing than [obscurance] at similar
  /// cost, and composes correctly with image-based lighting. Tuned by
  /// [AmbientOcclusionSettings.sliceCount],
  /// [AmbientOcclusionSettings.stepsPerSlice],
  /// [AmbientOcclusionSettings.visibilityBitmask],
  /// [AmbientOcclusionSettings.thickness], and
  /// [AmbientOcclusionSettings.thicknessHeuristic].
  ///
  /// The integration follows Jimenez et al., "Practical Realtime Strategies
  /// for Accurate Indirect Occlusion" (2016); the optional visibility
  /// bitmask follows Therrien et al., "Screen Space Indirect Lighting with
  /// Visibility Bitmask" (2023).
  groundTruth,
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

  /// Indirect specular is occluded by intersecting the unoccluded-direction
  /// cone around the bent normal with the specular lobe's cone around the
  /// reflection vector (Jimenez et al. 2016, section 6, with a linear
  /// overlap approximation). Directional, so reflections darken only when
  /// the lobe actually points into blocked directions. Requires
  /// [AmbientOcclusionSettings.bentNormals]; falls back to [simple] when
  /// the bent normal is unavailable.
  bentCone,
}
