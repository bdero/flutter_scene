import 'dart:math' as math;

import 'package:flutter_gpu_shim/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/material/environment.dart';

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
/// render with a [PerspectiveCamera].
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

  /// Builds the [shadowCascadeCount] shadow cascades that cover
  /// [camera]'s view out to [shadowMaxDistance], for a render target of
  /// the given [aspectRatio]. Returned near-to-far.
  ///
  /// Each cascade fits a bounding sphere to its slice of the camera
  /// frustum, so the cascade's projection size stays constant as the
  /// camera rotates; the projection is then texel-snapped so shadow
  /// edges do not shimmer.
  List<ShadowCascade> computeCascades(
    PerspectiveCamera camera,
    double aspectRatio,
  ) {
    final count = shadowCascadeCount.clamp(1, 4);
    final near = camera.fovNear;
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
    final forward = (camera.target - camera.position).normalized();
    final right = camera.up.cross(forward).normalized();
    final up = forward.cross(right).normalized();
    final tanV = math.tan(camera.fovRadiansY * 0.5);
    final tanH = tanV * aspectRatio;

    final lightLength = direction.length;
    final lightDir =
        lightLength == 0.0
            ? Vector3(0.0, -1.0, 0.0)
            : direction * (1.0 / lightLength);

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

  // The world -> light-clip matrix for a cascade whose frustum slice is
  // bounded by a sphere ([sphereCenter], [sphereRadius]). The
  // orthographic box is the sphere's bounding square, extended along
  // the light axis so casters behind the slice still reach it, and
  // texel-snapped against the world origin.
  Matrix4 _cascadeLightSpaceMatrix(
    Vector3 lightDir,
    Vector3 sphereCenter,
    double sphereRadius,
  ) {
    final up =
        lightDir.y.abs() > 0.99
            ? Vector3(0.0, 0.0, 1.0)
            : Vector3(0.0, 1.0, 0.0);
    // The eye sits well behind the sphere so casters between it and the
    // slice are captured.
    final eye = sphereCenter - lightDir * (sphereRadius * 3.0);
    final view = _lookAt(eye, sphereCenter, up);

    const near = 0.0;
    final far = sphereRadius * 6.0;
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

/// One cascade of a cascaded shadow map, produced by
/// [DirectionalLight.computeCascades].
///
/// A cascade owns the world -> light-clip-space matrix that renders and
/// samples its shadow map tile, plus the camera view distance at which
/// its coverage ends.
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
class Lighting {
  Lighting({
    required this.environmentMap,
    this.environmentIntensity = 1.0,
    Matrix3? environmentTransform,
    this.directionalLight,
    this.shadowMap,
    this.cascades = const [],
  }) : environmentTransform = environmentTransform ?? Matrix3.identity();

  /// The image-based-lighting environment in effect for this draw.
  final EnvironmentMap environmentMap;

  /// Scalar multiplier applied to [environmentMap]'s contribution
  /// (the scene's `environmentIntensity`).
  final double environmentIntensity;

  /// Rotation applied to the image-based-lighting environment (the
  /// scene's `environmentTransform`). Identity leaves it unrotated.
  final Matrix3 environmentTransform;

  /// The scene's directional light, or null when there isn't one.
  final DirectionalLight? directionalLight;

  /// The cascaded shadow map atlas (a depth-in-`.r` texture holding the
  /// cascade tiles as a horizontal strip) for [directionalLight], or
  /// null when shadows are off for this frame. Sampled with [cascades].
  final gpu.Texture? shadowMap;

  /// The shadow cascades matching [shadowMap], near-to-far, or empty
  /// when there is no shadow map this frame.
  final List<ShadowCascade> cascades;
}
