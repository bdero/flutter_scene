import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';

/// Which faces of a shadow caster are rendered into the shadow map (the
/// others are culled). Trades the two shadow-map failure modes (self-shadow
/// acne vs peter-panning) against each other.
/// {@category Lighting and environment}
enum ShadowCasterFaces {
  /// Render the light-facing (front) faces; cull back faces. The
  /// general-purpose default. Self-shadow acne on lit surfaces is held off by
  /// the depth and normal bias, which is hard to tune at grazing light angles.
  front,

  /// Render the faces pointing away from the light (back faces); cull front
  /// faces ("second-depth" shadow mapping). For solid, watertight geometry
  /// this removes self-shadow acne on lit surfaces, since the recorded depth
  /// is the far side of the body. The tradeoff is peter-panning (a shadow can
  /// detach from a thin caster); on thick bodies the offset hides inside the
  /// solid, so this is a good fit for blocky/voxel worlds.
  back,

  /// Render both faces (no culling). Records the nearest face, like [front]
  /// for closed geometry, but also captures one-sided or open meshes.
  both,
}

/// The sampling pattern used for directional shadow filtering.
/// {@category Lighting and environment}
enum DirectionalShadowFilter {
  /// A screen-space rotated Poisson disk that hides the regular texel grid.
  rotatedPoisson,

  /// A deterministic 17-tap grid with stable, visibly stepped texel edges.
  /// This avoids the per-fragment rotation used by [rotatedPoisson].
  fixedPcf,

  /// Percentage-closer soft shadows. A blocker search widens the penumbra
  /// with the caster's distance from the receiver, so shadows sharpen at
  /// contact and soften with reach, scaled by
  /// [DirectionalLight.angularRadius] and capped by
  /// [DirectionalLight.shadowSoftness]. Costs 9 extra shadow-map taps.
  pcss,

  /// A smooth, non-dithered 4-tap bilinear PCF grid. Reads 4 adjacent texels
  /// per tap and interpolates depth tests continuously, giving smooth analog
  /// penumbras without noise or stepping within a 16-sample texture budget.
  bilinearPcf,
}

/// An infinitely-distant light source (e.g. the sun) that illuminates
/// the whole scene from a single direction.
///
/// Attach one to a [Scene] via [Scene.directionalLight]; leaving it null
/// gives image-based lighting only (the historical behavior). The
/// analytic contribution is layered on top of the IBL ambient term. The
/// shader normalizes [direction], so it need not be unit length.
///
/// When [castsShadow] is true the renderer adds a depth-only shadow
/// pass. Shadows are cascaded: the camera view is split into
/// [shadowCascadeCount] depth ranges out to [shadowMaxDistance], each
/// fit with its own shadow map so near geometry stays crisp over a long
/// view distance. [firstCascadeFarBound] pins where the first of them
/// ends and [cascadeOverlap] cross-fades the hand-off between them. The
/// penumbra is a soft Poisson-disk PCF kernel of
/// radius [shadowSoftness], and shadowing fades back to lit at the far
/// edge over [shadowFadeRange]. Cascaded shadows require the scene to
/// render with a perspective projection.
/// {@category Lighting and environment}
class DirectionalLight {
  /// Default world-space travel direction for scene-level lights.
  static Vector3 get defaultDirection => Vector3(-0.3, -1.0, -0.2);

  /// Creates a [DirectionalLight].
  ///
  /// [direction] is the direction the light travels in world space (from
  /// the light toward the scene). [color] is the light's linear RGB;
  /// [intensity] scales it.
  DirectionalLight({
    Vector3? direction,
    Vector3? color,
    this.intensity = 3.0,
    this.priority = 0,
    this.castsShadow = false,
    this.cacheStaticShadows = true,
    this.shadowFadeRange = 2.0,
    this.shadowSoftness = 0.08,
    this.shadowCascadeCount = 4,
    this.shadowMaxDistance = 150.0,
    this.shadowCascadeSplitLambda = 0.6,
    this.firstCascadeFarBound,
    this.cascadeOverlap = 0.0,
    this.shadowMapResolution = 1024,
    this.shadowDepthBias = 0.02,
    this.shadowNormalBias = 0.02,
    this.shadowAmbientStrength = 0.0,
    this.shadowFilter = DirectionalShadowFilter.rotatedPoisson,
    this.shadowCasterFaces = ShadowCasterFaces.front,
    this.contactShadows = false,
    this.contactShadowDistance = 0.3,
    this.angularRadius = 0.005,
    this.channelMask = 0xFF,
    this.shadowCasterChannelMask = 0xFF,
  }) : direction = direction ?? defaultDirection,
       color = color ?? Vector3(1.0, 1.0, 1.0);

  /// The direction the light travels, in world space (from the light
  /// toward the scene). Need not be unit length.
  ///
  /// This aims the scene-level [Scene.directionalLight] convenience. The
  /// default [DirectionalLightComponent] ignores it and uses its node's local
  /// +Z axis. Use [DirectionalLightComponent.aimed] for another local axis.
  Vector3 direction;

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color].
  double intensity;

  /// Selects the primary directional light when a render feature supports
  /// only one, such as cascaded shadows. Higher values win. Equal priorities
  /// fall back to the strongest light.
  ///
  /// Additional directional lights still contribute direct lighting.
  int priority;

  /// Whether this light casts shadows (adds a shadow-map pass).
  bool castsShadow;

  /// Whether nodes marked `shadowStatic` are cached across frames.
  ///
  /// Disable this for a light whose direction changes every frame. Rebuilding
  /// and replaying cached tiles would add work compared with rendering all
  /// casters directly into the frame atlas.
  bool cacheStaticShadows;

  /// World-space width of the band at the far shadow cascade's edge
  /// over which shadowing fades back to lit, so the shadow distance
  /// limit is soft rather than a hard cutoff. `0` disables the fade.
  double shadowFadeRange;

  /// World-space radius of the shadow penumbra. Larger values give a
  /// softer shadow edge; `0` gives a hard edge. Sampled by a rotated
  /// Poisson-disk PCF kernel.
  double shadowSoftness;

  /// Number of shadow cascades, clamped to 1 through 4. More cascades
  /// keep shadows crisp over a longer view distance, each at the cost
  /// of one more depth pass. Used by [computeCascades].
  int shadowCascadeCount;

  /// View distance, in world units, out to which [computeCascades]
  /// spreads the shadow cascades. Beyond it surfaces are unshadowed.
  double shadowMaxDistance;

  /// Blends the cascade split spacing between logarithmic (`1.0`) and
  /// uniform (`0.0`). Higher values give the near cascades
  /// proportionally more resolution. Used by [computeCascades].
  double shadowCascadeSplitLambda;

  /// View distance, in world units, at which the first cascade ends. `null`
  /// (the default) lets [shadowCascadeSplitLambda] place it.
  ///
  /// Pin it to hold a known resolution over the near field, for example the
  /// reach of a third-person camera, and let the rest of the range spread
  /// across the remaining cascades under the usual split scheme. A pin below
  /// the camera near plane is lifted just above it so cascade 0 keeps
  /// thickness; a pin at or past [shadowMaxDistance] is ignored and the
  /// automatic scheme runs, since it would collapse every later cascade onto
  /// the far bound. Also ignored when there is only one cascade (it already
  /// ends at [shadowMaxDistance]). Automatic bounding-sphere fitting and
  /// texel snapping still apply.
  /// {@category Lighting and environment}
  double? firstCascadeFarBound;

  /// Fraction of each cascade's shadow tile, measured inward from its edge,
  /// over which it cross-fades into the next cascade, from `0.0` to `1.0`.
  ///
  /// `0.0` (the default) hands off hard, so a fragment takes the first cascade
  /// whose tile contains it and the resolution change can read as a seam.
  /// Larger values soften that seam; each cascade also widens past its split by
  /// the same fraction of its span, so the blend band is genuinely covered by
  /// both. `1.0` blends from the tile center outward. Fragments inside the band
  /// cost a second cascade lookup.
  /// {@category Lighting and environment}
  double cascadeOverlap;

  /// Pixel resolution of the (square) shadow map. With cascades this is
  /// the resolution of each cascade's tile.
  int shadowMapResolution;

  /// World-space depth bias subtracted from the receiver before the
  /// shadow test. Converted into each cascade's clip-space depth range,
  /// so a caster's shadow appears at the same world-height threshold in
  /// every cascade rather than fading out in the coarser far ones.
  double shadowDepthBias;

  /// World-space offset along the surface normal applied to the receiver
  /// before the shadow lookup ("normal-offset shadows"). Flutter GPU has
  /// no slope-scaled depth-bias rasterizer state, so this carries the
  /// load of acne removal on grazing surfaces.
  double shadowNormalBias;

  /// How much the cast shadow also darkens the image-based-lighting ambient,
  /// from `0.0` to `1.0`.
  ///
  /// Physically the analytic light is additive over the IBL ambient, so a
  /// shadow only removes the direct sun and leaves the ambient (sky) fully
  /// lighting the shadowed area. That is correct when the IBL excludes the
  /// sun, but a sky-baked environment already contains the sun's energy, so
  /// the ambient alone reads as fully lit. This control multiplies the ambient
  /// by `mix(1.0, shadow, shadowAmbientStrength)`, so `0.0` leaves the ambient
  /// untouched (the physical default) and `1.0` lets the shadow darken the
  /// ambient as much as the direct light. A non-physical artistic control for
  /// sky-lit scenes that want shadows to read as shadows.
  double shadowAmbientStrength;

  /// The percentage-closer filtering pattern used to sample the shadow map.
  DirectionalShadowFilter shadowFilter;

  /// Marches the camera depth buffer toward the light for small-scale
  /// contact shadowing that shadow-map resolution and bias miss. Runs on the
  /// screen-space occlusion chain (enabling this adds those passes even with
  /// ambient occlusion off) and needs a perspective camera. Applies whether
  /// or not [castsShadow] is set.
  bool contactShadows;

  /// How far the contact-shadow march reaches, in world units. Short
  /// distances keep the effect to tight contacts; long ones read as a cheap
  /// shadow substitute but show screen-space artifacts sooner.
  double contactShadowDistance;

  /// The light's angular radius in radians, driving how quickly
  /// [DirectionalShadowFilter.pcss] penumbras widen with caster distance.
  /// The default is close to the physical sun; larger values read as an
  /// overcast or stylized key light.
  double angularRadius;

  /// Which faces are rendered into the shadow map. Defaults to
  /// [ShadowCasterFaces.front]; use [ShadowCasterFaces.back] for solid,
  /// watertight geometry (e.g. voxel terrain) to remove grazing-angle
  /// self-shadow acne.
  ShadowCasterFaces shadowCasterFaces;

  /// The light channels this light illuminates, an 8-bit mask (default
  /// `0xFF`, every channel). A node receives this light only when
  /// `channelMask & node.lightChannelMask` is nonzero, so a zero mask on
  /// either side never intersects and the light is skipped. Channels do not
  /// affect image-based (environment) lighting, which every node receives.
  ///
  /// Deliberately independent of [shadowCasterChannelMask], which selects what
  /// renders into the shadow map. A node can be lit without casting, or cast
  /// without being lit.
  /// {@category Lighting and environment}
  int channelMask;

  /// The light channels whose nodes render into this light's shadow map, an
  /// 8-bit mask (default `0xFF`, every channel). A node casts only when
  /// `shadowCasterChannelMask & node.lightChannelMask` is nonzero. Narrow it
  /// to keep bulky scenery out of the cascades without changing what the light
  /// illuminates.
  ///
  /// Deliberately independent of [channelMask], which selects what this light
  /// illuminates.
  /// {@category Lighting and environment}
  int shadowCasterChannelMask;

  /// Builds the [shadowCascadeCount] shadow cascades that cover
  /// [camera]'s view out to [shadowMaxDistance], for a render target of
  /// the given [aspectRatio]. Returned near-to-far.
  ///
  /// Each cascade fits a bounding sphere to its slice of the camera
  /// frustum, so the cascade's projection size stays constant as the
  /// camera rotates; the projection is then texel-snapped so shadow
  /// edges do not shimmer.
  ///
  /// [worldDirection] is the light's world-space travel direction. When
  /// omitted it falls back to [direction] (the light's own field), which
  /// is correct for a light placed without a node transform.
  List<ShadowCascade> computeCascades(
    Camera camera,
    double aspectRatio, [
    Vector3? worldDirection,
  ]) {
    // Cascades fit the camera frustum, which is perspective-specific.
    final perspective = camera.projection as PerspectiveProjection;
    final count = shadowCascadeCount.clamp(1, 4);
    final near = perspective.near;
    final far = shadowMaxDistance;

    // Practical split scheme: a blend of logarithmic and uniform
    // spacing, so the near cascades get proportionally more resolution. A
    // pinned first bound takes the first split and the same scheme spreads the
    // rest from there; a single cascade has no rest, so it keeps far.
    // A pin at or past shadowMaxDistance leaves no range for the remaining
    // cascades (every later split collapses onto far), so it falls back to
    // the automatic scheme; the lower clamp stays strictly above the near
    // plane so cascade 0 keeps thickness.
    final bound = firstCascadeFarBound;
    final pinned = bound != null && count > 1 && bound < far && far > near
        ? math.max(bound, near + (far - near) * 1e-3)
        : null;
    final splits = <double>[near];
    if (pinned != null) splits.add(pinned);
    final splitNear = pinned ?? near;
    final splitCount = pinned != null ? count - 1 : count;
    for (var i = 1; i <= splitCount; i++) {
      final ratio = i / splitCount;
      final logSplit = splitNear * math.pow(far / splitNear, ratio);
      final uniformSplit = splitNear + (far - splitNear) * ratio;
      splits.add(
        shadowCascadeSplitLambda * logSplit +
            (1.0 - shadowCascadeSplitLambda) * uniformSplit,
      );
    }

    // Camera direction and field-of-view tangents.
    final forward = camera.forward;
    final tanV = math.tan(perspective.fovRadiansY * 0.5);
    final tanH = tanV * aspectRatio;
    final tanRadius2 = tanH * tanH + tanV * tanV;

    final effectiveDirection = worldDirection ?? direction;
    final lightLength = effectiveDirection.length;
    final lightDir = lightLength == 0.0
        ? Vector3(0.0, -1.0, 0.0)
        : effectiveDirection * (1.0 / lightLength);

    final overlap = cascadeOverlap.clamp(0.0, 1.0);

    final cascades = <ShadowCascade>[];
    for (var c = 0; c < count; c++) {
      // The smallest stable sphere enclosing both rectangular end planes has
      // its center on the view axis. Equalize the near/far corner distances,
      // unless that point lies beyond the far plane, where the far rectangle's
      // own circumcircle is the minimum. This keeps the rotation-invariant
      // cascade fit while wasting less shadow-map area than a midpoint sphere.
      final sliceNear = splits[c];
      // Overlap fits a cascade past its split so it and its successor both
      // cover the band the shader cross-fades over. The last cascade has no
      // successor, so it keeps its bound.
      final sliceFar = overlap > 0.0 && c < count - 1
          ? splits[c + 1] + (splits[c + 1] - sliceNear) * overlap
          : splits[c + 1];
      final centerDepth = math.min(
        sliceFar,
        (sliceNear + sliceFar) * (1.0 + tanRadius2) * 0.5,
      );
      final position = camera.position;
      final center = Vector3(
        position.x + forward.x * centerDepth,
        position.y + forward.y * centerDepth,
        position.z + forward.z * centerDepth,
      );
      final nearRadius2 =
          (centerDepth - sliceNear) * (centerDepth - sliceNear) +
          sliceNear * sliceNear * tanRadius2;
      final farRadius2 =
          (sliceFar - centerDepth) * (sliceFar - centerDepth) +
          sliceFar * sliceFar * tanRadius2;
      final radius = math.sqrt(math.max(nearRadius2, farRadius2));

      cascades.add(
        ShadowCascade(
          lightSpaceMatrix: _cascadeLightSpaceMatrix(lightDir, center, radius),
          splitDistance: splits[c + 1],
          boxSize: radius * 2.0,
          center: center,
          radius: radius,
        ),
      );
    }
    return cascades;
  }

  // How far toward the sun (in sphere radii) a cascade's light-space box
  // reaches, plus a small forward margin past the slice. The reach must be
  // generous because at grazing sun angles the occluder that shadows a receiver
  // can be far toward the sun (long shadows); too short a reach drops those
  // occluders from the map and the shadow goes missing (lit bands, one per
  // cascade). The depth range is decoupled from the perpendicular box, so reach
  // costs no shadow-map resolution; the fp32 atlas keeps depth precise over the
  // wide range. Their sum over 2 is the depthRange / boxSize ratio that
  // material_lighting.glsl's depth-bias normalization (`... / (7.0 * box)`)
  // must match: (12 + 2) / 2 = 7.
  static const double _casterReachRadii = 12.0;
  static const double _forwardMarginRadii = 2.0;

  /// The world -> light-clip matrix for a cascade covering the sphere
  /// ([center], [radius]); see [_cascadeLightSpaceMatrix]. The shadow cache
  /// uses this to rebuild a cascade's matrix with a slack-enlarged radius.
  @internal
  Matrix4 cascadeLightSpaceMatrix(
    Vector3 lightDir,
    Vector3 center,
    double radius,
  ) => _cascadeLightSpaceMatrix(lightDir, center, radius);

  // The world -> light-clip matrix for a cascade whose frustum slice is
  // bounded by a sphere ([sphereCenter], [sphereRadius]). The orthographic box
  // is the sphere's bounding square in the perpendicular plane, with a depth
  // range extended far toward the sun (see [_casterReachRadii]), and
  // texel-snapped against the world origin.
  Matrix4 _cascadeLightSpaceMatrix(
    Vector3 lightDir,
    Vector3 sphereCenter,
    double sphereRadius,
  ) {
    final fx = lightDir.x;
    final fy = lightDir.y;
    final fz = lightDir.z;
    final useZUp = fy.abs() > 0.99;
    final rx0 = useZUp ? -fy : fz;
    final ry0 = useZUp ? fx : 0.0;
    final rz0 = useZUp ? 0.0 : -fx;
    final inverseRightLength =
        1.0 / math.sqrt(rx0 * rx0 + ry0 * ry0 + rz0 * rz0);
    final rx = rx0 * inverseRightLength;
    final ry = ry0 * inverseRightLength;
    final rz = rz0 * inverseRightLength;
    final ux = fy * rz - fz * ry;
    final uy = fz * rx - fx * rz;
    final uz = fx * ry - fy * rx;

    final inverseRadius = 1.0 / sphereRadius;
    final inverseDepth =
        inverseRadius / (_casterReachRadii + _forwardMarginRadii);
    var tx =
        -(rx * sphereCenter.x + ry * sphereCenter.y + rz * sphereCenter.z) *
        inverseRadius;
    var ty =
        -(ux * sphereCenter.x + uy * sphereCenter.y + uz * sphereCenter.z) *
        inverseRadius;
    final tz =
        (-(fx * sphereCenter.x + fy * sphereCenter.y + fz * sphereCenter.z) +
            sphereRadius * _casterReachRadii) *
        inverseDepth;

    // Texel-snap against the world origin so the cascade's texel grid
    // is stable as the camera (and so the cascade) moves.
    final resolution = shadowMapResolution.toDouble();
    final texelX = (tx * 0.5 + 0.5) * resolution;
    final texelY = (ty * 0.5 + 0.5) * resolution;
    final offsetX = (texelX.roundToDouble() - texelX) / resolution * 2.0;
    final offsetY = (texelY.roundToDouble() - texelY) / resolution * 2.0;
    tx += offsetX;
    ty += offsetY;
    return Matrix4(
      rx * inverseRadius,
      ux * inverseRadius,
      fx * inverseDepth,
      0.0, //
      ry * inverseRadius,
      uy * inverseRadius,
      fy * inverseDepth,
      0.0, //
      rz * inverseRadius,
      uz * inverseRadius,
      fz * inverseDepth,
      0.0, //
      tx,
      ty,
      tz,
      1.0, //
    );
  }

  static Matrix4 _lookAt(Vector3 position, Vector3 target, Vector3 up) {
    final forward = (target - position).normalized();
    final right = up.cross(forward).normalized();
    final newUp = forward.cross(right).normalized();
    return Matrix4(
      right.x,
      newUp.x,
      forward.x,
      0.0, //
      right.y,
      newUp.y,
      forward.y,
      0.0, //
      right.z,
      newUp.z,
      forward.z,
      0.0, //
      -right.dot(position),
      -newUp.dot(position),
      -forward.dot(position),
      1.0, //
    );
  }
}

/// A light that radiates from a single world-space point equally in every
/// direction, its influence falling off with distance.
///
/// Attach one to the scene by adding a `PointLightComponent` to a node; the
/// light's world position is the node's world-space translation, so moving
/// the node moves the light. The analytic contribution is layered on top of
/// the image-based-lighting ambient term, the same as [DirectionalLight].
///
/// Point lights do not cast shadows.
/// {@category Lighting and environment}
class PointLight {
  /// Creates a [PointLight].
  ///
  /// [color] is the light's linear RGB; [intensity] scales it and is the
  /// radiance at unit distance (point lights fall off with the inverse
  /// square of distance, so useful values are often larger than a
  /// [DirectionalLight]'s). [range] is the world-space distance at which the
  /// influence reaches zero; `0` (the default) means infinite range (pure
  /// inverse-square falloff).
  PointLight({
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.falloffExponent = 2.0,
    this.channelMask = 0xFF,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0);

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color]; the radiance at unit distance.
  double intensity;

  /// World-space distance at which the light's influence smoothly reaches
  /// zero. `0` means infinite range (pure inverse-square falloff, clamped
  /// near the source).
  double range;

  /// The distance-falloff exponent. `2` (the default) is the physical
  /// inverse square; lower values are an artistic control that lets the
  /// light reach further without blowing out its near field (a hero light
  /// touching distant scenery). Values at or below zero are clamped.
  double falloffExponent;

  /// The light channels this light illuminates, an 8-bit mask (default
  /// `0xFF`, every channel). A node receives this light only when
  /// `channelMask & node.lightChannelMask` is nonzero, so a zero mask on
  /// either side never intersects. Channels do not affect image-based
  /// (environment) lighting, which every node receives.
  /// {@category Lighting and environment}
  int channelMask;
}

/// A rectangle that emits light from its face, shaded with linearly
/// transformed cosines so the highlight stretches and the falloff follows
/// the panel's true shape and area.
///
/// Attach one by adding a `RectAreaLightComponent` to a node. The rectangle
/// lies in the node's local XY plane, [width] along local X and [height]
/// along local Y, emitting along local +Z (matching the directional-light
/// aim convention). One-sided; the back face emits nothing. Area lights cast
/// no shadows.
/// {@category Lighting and environment}
class RectAreaLight {
  /// Creates a [RectAreaLight].
  RectAreaLight({
    Vector3? color,
    this.intensity = 1.0,
    this.width = 1.0,
    this.height = 1.0,
    this.range = 0.0,
    this.channelMask = 0xFF,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0);

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color]; the emitted radiance of the
  /// panel's surface. The received light also grows with the panel's area.
  double intensity;

  /// The rectangle's world-space width along the node's local X axis
  /// (before node scale).
  double width;

  /// The rectangle's world-space height along the node's local Y axis
  /// (before node scale).
  double height;

  /// World-space distance from the panel's center at which its influence
  /// windows to zero. `0` means infinite range (the form factor's own
  /// inverse-square falloff still applies).
  double range;

  /// The light channels this panel illuminates, an 8-bit mask (default
  /// `0xFF`, every channel). A node receives this light only when
  /// `channelMask & node.lightChannelMask` is nonzero, so a zero mask on
  /// either side never intersects. Channels do not affect image-based
  /// (environment) lighting, which every node receives.
  /// {@category Lighting and environment}
  int channelMask;
}

/// A light that radiates from a world-space point within a cone, combining a
/// [PointLight]'s distance falloff with an angular falloff between an inner
/// and outer cone.
///
/// Attach one by adding a `SpotLightComponent` to a node; the light's world
/// position is the node's world translation and its aim is the node's
/// world-space rotation applied to [direction]. The analytic contribution is
/// layered on top of the image-based-lighting ambient term.
///
/// When [castsShadow] is true and the scene's spot-shadow budget has room, the
/// renderer renders the spot's cone into a perspective shadow map and the light
/// is occluded by geometry between it and the surface.
/// {@category Lighting and environment}
class SpotLight {
  /// Creates a [SpotLight].
  ///
  /// [direction] is the cone's aim in the owning node's local space (rotated
  /// to world by the node's transform). [innerConeAngle] and [outerConeAngle]
  /// are half-angles in radians: the cone is full brightness within
  /// [innerConeAngle] of the axis and falls to zero at [outerConeAngle].
  /// Both must satisfy `0 <= inner < outer < pi/2`.
  SpotLight({
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.falloffExponent = 2.0,
    Vector3? direction,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = math.pi / 4.0,
    this.castsShadow = false,
    this.shadowMapResolution = 1024,
    this.shadowNear = 0.1,
    this.shadowDepthBias = 0.0,
    this.shadowNormalBias = 0.1,
    this.shadowSoftness = 1.0,
    this.shadowCasterFaces = ShadowCasterFaces.front,
    this.channelMask = 0xFF,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0),
       direction = direction ?? Vector3(0.0, -1.0, 0.0);

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color]; the radiance at unit distance.
  double intensity;

  /// World-space distance at which the light's influence smoothly reaches
  /// zero. `0` means infinite range (pure inverse-square falloff).
  double range;

  /// The distance-falloff exponent (see [PointLight.falloffExponent]).
  double falloffExponent;

  /// The cone's aim, in the owning node's local space. Need not be unit
  /// length. Rotated to world by the node's transform.
  Vector3 direction;

  /// Half-angle of the inner cone, in radians. Within this angle of the
  /// axis the light is at full brightness.
  double innerConeAngle;

  /// Half-angle of the outer cone, in radians. Between [innerConeAngle] and
  /// this the light falls off to zero; past it the light contributes nothing.
  double outerConeAngle;

  /// Whether this spot casts a shadow. When true, the renderer renders the
  /// cone into a perspective shadow map if the scene's spot-shadow budget has
  /// room (shadow-casting spots are limited; the rest shade unshadowed).
  bool castsShadow;

  /// Pixel resolution of this spot's (square) shadow map tile.
  int shadowMapResolution;

  /// Near clip distance of the shadow frustum. Geometry closer to the light
  /// than this does not occlude.
  double shadowNear;

  /// Clip-space depth bias subtracted from the receiver before the shadow
  /// test. Defaults to `0`: a constant clip-space bias is badly behaved in a
  /// perspective shadow (tiny near the light, large far away, which detaches
  /// the shadow from a caster's base), so the normal-offset bias below does
  /// the work instead. Raise it only to fight grazing-angle self-shadow acne.
  double shadowDepthBias;

  /// World-space offset along the surface normal applied to the receiver
  /// before the shadow lookup ("normal-offset shadows"). This is the main
  /// acne/peter-panning control for a spot; being world-space it scales with
  /// the scene, so very small scenes may want a smaller value.
  double shadowNormalBias;

  /// Radius, in shadow-map texels, of the soft-shadow PCF kernel. `0` gives a
  /// hard edge.
  double shadowSoftness;

  /// Which faces are rendered into the shadow map. [ShadowCasterFaces.back]
  /// (second-depth) removes the shadow detaching from a solid caster's base
  /// (peter-panning) by recording the far side; [ShadowCasterFaces.front] is
  /// the general default.
  ShadowCasterFaces shadowCasterFaces;

  // TODO(light-channels-spot-casters): add a spot caster mask alongside
  // DirectionalLight.shadowCasterChannelMask, so a spot's shadow map can drop
  // casters the way a cascade can.
  /// The light channels this spot illuminates, an 8-bit mask (default `0xFF`,
  /// every channel). A node receives this light only when
  /// `channelMask & node.lightChannelMask` is nonzero, so a zero mask on
  /// either side never intersects. Channels do not affect image-based
  /// (environment) lighting, which every node receives.
  ///
  /// Gates the lighting only. Every caster still renders into this spot's
  /// shadow map; only [DirectionalLight.shadowCasterChannelMask] filters
  /// casters.
  /// {@category Lighting and environment}
  int channelMask;

  /// The world -> clip matrix that renders and samples this spot's perspective
  /// shadow map, for a light at [worldPosition] aimed along [worldDirection]
  /// (both from the owning node's transform). The frustum is the cone, a
  /// vertical field of view of twice [outerConeAngle] (with a small margin) and
  /// a square aspect, out to [range] (or a default when the range is infinite).
  Matrix4 shadowViewProjection(Vector3 worldPosition, Vector3 worldDirection) {
    final length = worldDirection.length;
    final dir = length == 0.0
        ? Vector3(0.0, -1.0, 0.0)
        : worldDirection / length;
    final up = dir.y.abs() > 0.99
        ? Vector3(0.0, 0.0, 1.0)
        : Vector3(0.0, 1.0, 0.0);
    final view = DirectionalLight._lookAt(
      worldPosition,
      worldPosition + dir,
      up,
    );
    final far = range > 0.0 ? range : 100.0;
    // A small margin past the outer cone so its lit edge sits inside the
    // frustum rather than on its clipped border.
    final fovY = math.min(2.0 * outerConeAngle * 1.05, math.pi * 0.98);
    final projection = PerspectiveProjection(
      fovRadiansY: fovY,
      near: shadowNear,
      far: far,
    ).getProjectionMatrix(1.0);
    return projection * view;
  }
}

/// One cascade of a cascaded shadow map, produced by
/// [DirectionalLight.computeCascades].
///
/// A cascade owns the world -> light-clip-space matrix that renders and
/// samples its shadow map tile, plus the camera view distance at which
/// its coverage ends.
/// {@category Lighting and environment}
class ShadowCascade {
  /// Creates a cascade from its [lightSpaceMatrix], [splitDistance], and
  /// [boxSize].
  ShadowCascade({
    required this.lightSpaceMatrix,
    required this.splitDistance,
    required this.boxSize,
    this.center,
    this.radius = 0.0,
  });

  /// World -> light-clip-space matrix that renders and samples this
  /// cascade's shadow map tile.
  final Matrix4 lightSpaceMatrix;

  /// Camera view-space distance, in world units, at which this
  /// cascade's coverage ends.
  final double splitDistance;

  /// World-space side length of this cascade's orthographic box, used
  /// to convert world-space softness and fade widths into the
  /// cascade's UV space.
  final double boxSize;

  /// World-space center of the frustum-slice bounding sphere this cascade
  /// was fit to, or null when the cascade was built directly from a matrix.
  /// The shadow cache uses it to decide when a cached tile still covers the
  /// current view.
  final Vector3? center;

  /// Radius of the bounding sphere behind [center] (0 when unknown).
  final double radius;
}

/// The lighting state handed to a [Material] when it binds for a draw.
///
/// Bundles the image-based-lighting [EnvironmentMap] (and the scene's
/// `environmentIntensity` multiplier) with the analytic lights and shadow
/// resources, so material code has everything it needs in one place.
/// {@category Lighting and environment}
class Lighting {
  Lighting({
    required this.environmentMap,
    this.environmentMapB,
    this.environmentBlend = 0.0,
    this.environmentIntensity = 1.0,
    Matrix3? environmentTransform,
    this.diffuseShTexture,
    this.irradianceField,
    this.directionalLight,
    this.directionalLightDirection,
    this.punctualParamsTexture,
    this.punctualIndexTexture,
    this.punctualParamsCount = 0,
    this.punctualIndexWidth = 0,
    this.punctualIndexHeight = 0,
    this.spotShadowCount = 0,
    this.spotShadowDepthBias = 0.0,
    this.spotShadowNormalBias = 0.0,
    this.spotShadowSoftness = 0.0,
    this.shadowMap,
    this.cascades = const [],
    this.ssaoMap,
    this.specularOcclusionMode = 0.0,
    this.ssaoDirectLightAffect = 0.0,
    this.ssaoMultiBounce = 0.0,
    this.ssaoBentNormals = false,
    this.ssaoContactShadows = false,
    this.ssaoIndirectLight = false,
    this.viewportSize = ui.Size.zero,
    this.fog,
    this.sceneDepthLinear,
    this.filteredSceneColor,
    this.transmissionFilterBandCount = 0,
    this.cameraPosition,
    this.cameraForward,
    this.cameraRight,
    this.cameraUp,
    this.tanHalfFovX = 0.0,
    this.tanHalfFovY = 0.0,
    this.time = 0.0,
    this.planarReflectionsSuppressed = false,
  }) : environmentTransform = environmentTransform ?? Matrix3.identity();

  /// The image-based-lighting environment in effect for this draw.
  final EnvironmentMap environmentMap;

  /// The scene's distance fog, or null when fog is off for this frame. Applied
  /// per-fragment by every material in linear HDR before tone mapping.
  final Fog? fog;

  /// A secondary environment cross-faded with [environmentMap] by
  /// [environmentBlend], or null when a single environment is in effect.
  final EnvironmentMap? environmentMapB;

  /// The factor blending [environmentMap] toward [environmentMapB] (`0` uses
  /// only [environmentMap], `1` only [environmentMapB]). Ignored when
  /// [environmentMapB] is null.
  final double environmentBlend;

  /// Scalar multiplier applied to [environmentMap]'s contribution
  /// (the scene's `environmentIntensity`).
  final double environmentIntensity;

  /// Rotation applied to the image-based-lighting environment (the
  /// scene's `environmentTransform`). Identity leaves it unrotated.
  final Matrix3 environmentTransform;

  /// The diffuse-SH coefficient texture to bind for this draw. During an
  /// environment cross-fade this is a 9x2 composite (row 0 primary, row 1
  /// [environmentMapB]); otherwise null, and [environmentMap]'s own 9x1
  /// texture is bound.
  final gpu.Texture? diffuseShTexture;

  /// The world-space irradiance field in effect for this draw, or null when
  /// it is off. Its atlas carries the diffuse-SH strip in its first two rows,
  /// so it is bound in place of [diffuseShTexture] when present and the field
  /// costs no additional sampler.
  final IrradianceFieldBinding? irradianceField;

  /// The scene's directional light, or null when there isn't one.
  final DirectionalLight? directionalLight;

  /// The world-space travel direction of [directionalLight], derived from
  /// the light node's transform. Null when there is no directional light;
  /// consumers fall back to [DirectionalLight.direction] in that case.
  final Vector3? directionalLightDirection;

  /// The per-frame parameters texture holding every additional analytic light
  /// (point and spot lights, plus any directional lights past the first
  /// shadowed one), one per RGBA32F row, or null when there are none. Built by
  /// `PunctualLightBuffer` and shared across every lit draw this frame; a draw
  /// reads only the rows its per-object index slice selects.
  final gpu.Texture? punctualParamsTexture;

  /// The per-frame light-index texture: each item's
  /// `[lightListOffset, +lightListCount)` slice indexes into
  /// [punctualParamsTexture]. Null when no item is reached by any light.
  final gpu.Texture? punctualIndexTexture;

  /// Number of light rows in [punctualParamsTexture]. Zero leaves punctual
  /// lighting off (only [directionalLight] and the ambient term contribute).
  final int punctualParamsCount;

  /// Dimensions of [punctualIndexTexture], for the shader's fetch-coordinate
  /// normalization.
  final int punctualIndexWidth;
  final int punctualIndexHeight;

  /// Number of shadow-casting spots this frame; their tiles follow the
  /// directional cascades in [shadowMap] and their matrices ride in
  /// [punctualParamsTexture]. Zero disables spot shadow sampling.
  final int spotShadowCount;

  /// Shared spot-shadow sampling parameters.
  final double spotShadowDepthBias;
  final double spotShadowNormalBias;
  final double spotShadowSoftness;

  /// The cascaded shadow map atlas (a depth-in-`.r` texture holding the
  /// cascade tiles as a horizontal strip) for [directionalLight], or
  /// null when shadows are off for this frame. Sampled with [cascades].
  final gpu.Texture? shadowMap;

  /// The shadow cascades matching [shadowMap], near-to-far, or empty
  /// when there is no shadow map this frame.
  final List<ShadowCascade> cascades;

  /// The screen-space ambient-occlusion texture for this frame (occlusion
  /// factor in `.r`), or null when occlusion is off. When set, it modulates
  /// indirect lighting in the shader.
  final gpu.Texture? ssaoMap;

  /// How indirect specular is occluded: `0` leaves it on the diffuse
  /// occlusion factor, `1` derives a dedicated specular occlusion. Mirrors
  /// `SpecularAmbientOcclusionMode.index`.
  final double specularOcclusionMode;

  /// Fraction of screen-space occlusion applied to analytic direct lights.
  final double ssaoDirectLightAffect;

  /// How much occluded indirect diffuse converges toward the surface albedo
  /// instead of black (the multi-bounce approximation).
  final double ssaoMultiBounce;

  /// Whether [ssaoMap]'s gba channels carry a packed view-space bent normal.
  final bool ssaoBentNormals;

  /// Whether [ssaoMap]'s g channel carries the sun contact-shadow term.
  final bool ssaoContactShadows;

  /// Whether [ssaoMap] carries gathered indirect radiance in rgb with the
  /// visibility in a (instead of visibility in r).
  final bool ssaoIndirectLight;

  /// The color-pass render-target size, which maps `gl_FragCoord` into the
  /// occlusion texture's UV and into the screen UV a material samples its
  /// scene inputs at. Always the pass dimensions, independent of whether
  /// occlusion is on.
  final ui.Size viewportSize;

  /// The opaque geometry's linear (planar view-space) depth texture for
  /// materials that declare `RenderInput.depth` in `Material.sceneInputs`
  /// (depth-fade, absorption, shoreline foam), or null when no visible
  /// material asked for it. Same texture the SSAO/SSR passes consume.
  final gpu.Texture? sceneDepthLinear;

  /// Accumulated scene color behind materials that declare
  /// `RenderInput.opaqueSceneColor` (refraction). Null when unrequested.
  gpu.Texture? opaqueSceneColor;

  /// Compact roughness-filtered atlas of [opaqueSceneColor]. Null unless the
  /// current material requests [RenderInput.filteredSceneColor].
  gpu.Texture? filteredSceneColor;

  /// Number of valid roughness bands in [filteredSceneColor].
  int transmissionFilterBandCount;

  /// Camera world position and normalized basis directions for this view,
  /// letting a material compute its fragment's planar view depth
  /// (`dot(worldPos - cameraPosition, cameraForward)`) to compare against
  /// [sceneDepthLinear]. Null when no material requests scene inputs.
  final Vector3? cameraPosition;
  final Vector3? cameraForward;

  /// Normalized world-space right/up axes used to project refracted volume
  /// exits back into the scene-color image.
  final Vector3? cameraRight;
  final Vector3? cameraUp;

  /// Tangents of the half field of view (x and y), letting a material
  /// project world positions to screen UV (screen-space marches). Zero
  /// for non-perspective cameras; materials treat that as unavailable.
  final double tanHalfFovX;
  final double tanHalfFovY;

  /// Seconds since the scene started rendering, for engine-driven material
  /// animation (the same clock custom post passes receive).
  final double time;

  /// Whether this draw is inside a planar reflection capture, where mirror
  /// materials bind no capture and fall back to their base look so captures
  /// never recurse.
  final bool planarReflectionsSuppressed;
}
