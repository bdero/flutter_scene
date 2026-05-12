import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/material/environment.dart';

/// An infinitely-distant light source (e.g. the sun) that illuminates
/// the whole scene from a single direction.
///
/// Attach one to a [Scene] via [Scene.directionalLight]; leaving it null
/// gives image-based lighting only (the historical behavior). The
/// analytic contribution is layered on top of the IBL ambient term. The
/// shader normalizes [direction], so it need not be unit length.
///
/// When [castsShadow] is true the renderer adds a depth-only shadow pass
/// from the light's point of view, sampled with PCF. The shadow uses a
/// fixed orthographic frustum: a [shadowFrustumSize] × [shadowFrustumSize]
/// square, [shadowFrustumDepth] deep, centered on [shadowFocusPoint].
/// Geometry outside that box is unshadowed, so size the box (and move the
/// focus point) to cover the part of the scene you care about.
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
    Vector3? shadowFocusPoint,
    this.shadowFrustumSize = 12.0,
    this.shadowFrustumDepth = 50.0,
    this.shadowMapResolution = 1024,
    this.shadowDepthBias = 0.0015,
    this.shadowNormalBias = 0.02,
  }) : direction = direction ?? Vector3(-0.3, -1.0, -0.2),
       color = color ?? Vector3(1.0, 1.0, 1.0),
       shadowFocusPoint = shadowFocusPoint ?? Vector3.zero();

  /// The direction the light travels, in world space (from the light
  /// toward the scene). Need not be unit length.
  Vector3 direction;

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color].
  double intensity;

  /// Whether this light casts shadows (adds a shadow-map pass).
  bool castsShadow;

  /// World-space point the orthographic shadow frustum is centered on.
  Vector3 shadowFocusPoint;

  /// Side length of the (square) orthographic shadow frustum, in world
  /// units. Larger covers more scene at lower effective resolution.
  double shadowFrustumSize;

  /// Depth (near-to-far extent) of the orthographic shadow frustum, in
  /// world units, centered on [shadowFocusPoint] along the light axis.
  double shadowFrustumDepth;

  /// Pixel resolution of the (square) shadow map.
  int shadowMapResolution;

  /// Constant depth bias subtracted from the receiver's light-space depth
  /// before the shadow test, to combat self-shadow acne.
  double shadowDepthBias;

  /// World-space offset along the surface normal applied to the receiver
  /// before the shadow lookup ("normal-offset shadows"). Flutter GPU has
  /// no slope-scaled depth-bias rasterizer state, so this carries the
  /// load of acne removal on grazing surfaces.
  double shadowNormalBias;

  /// Builds the world → light-clip-space matrix used to render and sample
  /// the shadow map. Uses the same column-vector / `[0, 1]` depth
  /// conventions as [PerspectiveCamera.getViewTransform].
  Matrix4 computeLightSpaceMatrix() {
    final length = direction.length;
    final dir =
        length == 0.0 ? Vector3(0.0, -1.0, 0.0) : Vector3.copy(direction)
          ..scale(1.0 / length);
    final up =
        dir.y.abs() > 0.99 ? Vector3(0.0, 0.0, 1.0) : Vector3(0.0, 1.0, 0.0);

    const near = 0.01;
    final far = shadowFrustumDepth;
    final eye = shadowFocusPoint - dir * (far * 0.5);
    final view = _lookAt(eye, shadowFocusPoint, up);

    final s = shadowFrustumSize;
    // Symmetric orthographic projection, column-major, mapping z in
    // [near, far] to [0, 1] (matching the perspective projection).
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
    return ortho * view;
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

/// The lighting state handed to a [Material] when it binds for a draw.
///
/// Bundles the image-based-lighting [EnvironmentMap] (and the scene's
/// `environmentIntensity` multiplier) with the analytic lights and shadow
/// resources, so material code has everything it needs in one place.
class Lighting {
  Lighting({
    required this.environmentMap,
    this.environmentIntensity = 1.0,
    this.directionalLight,
    this.shadowMap,
    this.lightSpaceMatrix,
  });

  /// The image-based-lighting environment in effect for this draw.
  final EnvironmentMap environmentMap;

  /// Scalar multiplier applied to [environmentMap]'s contribution
  /// (the scene's `environmentIntensity`).
  final double environmentIntensity;

  /// The scene's directional light, or null when there isn't one.
  final DirectionalLight? directionalLight;

  /// The shadow map (a depth-in-`.r` texture) for [directionalLight], or
  /// null when shadows are off for this frame. Sampled with
  /// [lightSpaceMatrix].
  final gpu.Texture? shadowMap;

  /// World → light-clip-space matrix matching [shadowMap], or null when
  /// there is no shadow map this frame.
  final Matrix4? lightSpaceMatrix;
}
