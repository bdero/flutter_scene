import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/material/environment.dart';

/// An infinitely-distant light source (e.g. the sun) that illuminates
/// the whole scene from a single direction.
///
/// Attach one to a [Scene] via [Scene.directionalLight]; leaving it null
/// gives image-based lighting only (the historical behavior). The
/// analytic contribution is layered on top of the IBL ambient term. The
/// shader normalizes [direction], so it need not be unit length.
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
  }) : direction = direction ?? Vector3(-0.3, -1.0, -0.2),
       color = color ?? Vector3(1.0, 1.0, 1.0);

  /// The direction the light travels, in world space (from the light
  /// toward the scene). Need not be unit length.
  Vector3 direction;

  /// Linear RGB color of the light.
  Vector3 color;

  /// Scalar multiplier applied to [color].
  double intensity;

  /// Whether this light casts shadows.
  ///
  /// Shadow mapping is not yet wired up, so this currently has no effect;
  /// it is here so the API is stable once it lands.
  bool castsShadow;
}

/// The lighting state handed to a [Material] when it binds for a draw.
///
/// Bundles the image-based-lighting [Environment] with the scene's
/// analytic lights (and, in the future, shadow resources) so material
/// code has everything it needs in one place.
class Lighting {
  Lighting({required this.environment, this.directionalLight});

  /// The image-based-lighting environment in effect for this draw.
  final Environment environment;

  /// The scene's directional light, or null when there isn't one.
  final DirectionalLight? directionalLight;
}
