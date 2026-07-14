import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/material/environment.dart';

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
/// view distance. The penumbra is a soft Poisson-disk PCF kernel of
/// radius [shadowSoftness], and shadowing fades back to lit at the far
/// edge over [shadowFadeRange]. Cascaded shadows require the scene to
/// render with a perspective projection.
/// {@category Lighting and environment}
class DirectionalLight {
  /// Creates a [DirectionalLight].
  ///
  /// [direction] is the direction the light travels in world space (from
  /// the light toward the scene). [color] is the light's linear RGB;
  /// [intensity] scales it.
  DirectionalLight({
    Vector3? direction,
    Vector3? color,
    this.intensity = 3.0,
    this.castsShadow = false,
    this.shadowFadeRange = 2.0,
    this.shadowSoftness = 0.08,
    this.shadowCascadeCount = 4,
    this.shadowMaxDistance = 150.0,
    this.shadowCascadeSplitLambda = 0.6,
    this.shadowMapResolution = 1024,
    this.shadowDepthBias = 0.02,
    this.shadowNormalBias = 0.02,
    this.shadowAmbientStrength = 0.0,
    this.shadowCasterFaces = ShadowCasterFaces.front,
  }) : direction = direction ?? Vector3(-0.3, -1.0, -0.2),
       color = color ?? Vector3(1.0, 1.0, 1.0);

  /// The direction the light travels, in world space (from the light
  /// toward the scene). Need not be unit length.
  Vector3 direction;

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color].
  double intensity;

  /// Whether this light casts shadows (adds a shadow-map pass).
  bool castsShadow;

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

  /// Which faces are rendered into the shadow map. Defaults to
  /// [ShadowCasterFaces.front]; use [ShadowCasterFaces.back] for solid,
  /// watertight geometry (e.g. voxel terrain) to remove grazing-angle
  /// self-shadow acne.
  ShadowCasterFaces shadowCasterFaces;

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
    // spacing, so the near cascades get proportionally more resolution.
    final splits = <double>[near];
    for (var i = 1; i <= count; i++) {
      final ratio = i / count;
      final logSplit = near * math.pow(far / near, ratio);
      final uniformSplit = near + (far - near) * ratio;
      splits.add(
        shadowCascadeSplitLambda * logSplit +
            (1.0 - shadowCascadeSplitLambda) * uniformSplit,
      );
    }

    // Camera basis and field-of-view tangents.
    final forward = camera.forward;
    final right = camera.up.cross(forward).normalized();
    final up = forward.cross(right).normalized();
    final tanV = math.tan(perspective.fovRadiansY * 0.5);
    final tanH = tanV * aspectRatio;

    final effectiveDirection = worldDirection ?? direction;
    final lightLength = effectiveDirection.length;
    final lightDir = lightLength == 0.0
        ? Vector3(0.0, -1.0, 0.0)
        : effectiveDirection * (1.0 / lightLength);

    final cascades = <ShadowCascade>[];
    for (var c = 0; c < count; c++) {
      // The eight world-space corners of this cascade's frustum slice.
      final corners = <Vector3>[];
      final center = Vector3.zero();
      for (final depth in [splits[c], splits[c + 1]]) {
        final planeCenter = camera.position + forward * depth;
        for (final sx in const [-1.0, 1.0]) {
          for (final sy in const [-1.0, 1.0]) {
            final corner =
                planeCenter +
                right * (sx * depth * tanH) +
                up * (sy * depth * tanV);
            corners.add(corner);
            center.add(corner);
          }
        }
      }
      // The slice is symmetric about the view axis, so the corner
      // average is the center of their bounding sphere.
      center.scale(1.0 / 8.0);
      var radius = 0.0;
      for (final corner in corners) {
        radius = math.max(radius, (corner - center).length);
      }

      cascades.add(
        ShadowCascade(
          lightSpaceMatrix: _cascadeLightSpaceMatrix(lightDir, center, radius),
          splitDistance: splits[c + 1],
          boxSize: radius * 2.0,
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
    final up = lightDir.y.abs() > 0.99
        ? Vector3(0.0, 0.0, 1.0)
        : Vector3(0.0, 1.0, 0.0);
    // The eye sits far toward the sun so occluders casting long shadows still
    // render into this cascade (see [_casterReachRadii]).
    final eye = sphereCenter - lightDir * (sphereRadius * _casterReachRadii);
    final view = _lookAt(eye, sphereCenter, up);

    const near = 0.0;
    final far = sphereRadius * (_casterReachRadii + _forwardMarginRadii);
    final s = sphereRadius * 2.0;
    final ortho = Matrix4(
      2.0 / s,
      0.0,
      0.0,
      0.0, //
      0.0,
      2.0 / s,
      0.0,
      0.0, //
      0.0,
      0.0,
      1.0 / (far - near),
      0.0, //
      0.0,
      0.0,
      -near / (far - near),
      1.0, //
    );
    final matrix = ortho * view;

    // Texel-snap against the world origin so the cascade's texel grid
    // is stable as the camera (and so the cascade) moves.
    final reference = matrix.transformed(Vector4(0.0, 0.0, 0.0, 1.0));
    final resolution = shadowMapResolution.toDouble();
    final texelX = (reference.x * 0.5 + 0.5) * resolution;
    final texelY = (reference.y * 0.5 + 0.5) * resolution;
    final offsetX = (texelX.roundToDouble() - texelX) / resolution * 2.0;
    final offsetY = (texelY.roundToDouble() - texelY) / resolution * 2.0;
    return Matrix4.translation(Vector3(offsetX, offsetY, 0.0)) * matrix;
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
  PointLight({Vector3? color, this.intensity = 1.0, this.range = 0.0})
    : color = color ?? Vector3(1.0, 1.0, 1.0);

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color]; the radiance at unit distance.
  double intensity;

  /// World-space distance at which the light's influence smoothly reaches
  /// zero. `0` means infinite range (pure inverse-square falloff, clamped
  /// near the source).
  double range;
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
  }) : color = color ?? Vector3(1.0, 1.0, 1.0),
       direction = direction ?? Vector3(0.0, -1.0, 0.0);

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color]; the radiance at unit distance.
  double intensity;

  /// World-space distance at which the light's influence smoothly reaches
  /// zero. `0` means infinite range (pure inverse-square falloff).
  double range;

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
    this.viewportSize = ui.Size.zero,
    this.fog,
    this.sceneDepthLinear,
    this.cameraPosition,
    this.cameraForward,
    this.time = 0.0,
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

  /// The color-pass render-target size, used to map `gl_FragCoord` into the
  /// occlusion texture's UV. Zero when occlusion is off.
  final ui.Size viewportSize;

  /// The opaque geometry's linear (planar view-space) depth texture for
  /// materials that declare `RenderInput.depth` in `Material.sceneInputs`
  /// (depth-fade, absorption, shoreline foam), or null when no visible
  /// material asked for it. Same texture the SSAO/SSR passes consume.
  final gpu.Texture? sceneDepthLinear;

  /// The scene color snapshot taken between the opaque and translucent
  /// phases, for materials that declare `RenderInput.opaqueSceneColor`
  /// (refraction). Null during the opaque phase and when unrequested; the
  /// scene pass sets it before translucent draws encode.
  gpu.Texture? opaqueSceneColor;

  /// Camera world position and normalized forward direction for this view,
  /// letting a material compute its fragment's planar view depth
  /// (`dot(worldPos - cameraPosition, cameraForward)`) to compare against
  /// [sceneDepthLinear]. Null when no material requests scene inputs.
  final Vector3? cameraPosition;
  final Vector3? cameraForward;

  /// Seconds since the scene started rendering, for engine-driven material
  /// animation (the same clock custom post passes receive).
  final double time;
}
