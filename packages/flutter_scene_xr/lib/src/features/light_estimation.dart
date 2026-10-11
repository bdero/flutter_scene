import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Vector3;

/// Real-world lighting the runtime estimates.
/// {@category Features}
abstract class XrLightEstimation {
  /// The latest estimate, or null until the runtime produces one.
  XrLightEstimate? get estimate;
}

/// An estimate of the real-world lighting around the viewer.
///
/// [sphericalHarmonics] are nine RGB coefficients (27 floats, `r g b` per
/// band in order) of the ambient light; the primary light is the strongest
/// directional component.
// TODO(xr-light-estimate): feed the coefficients into the scene's
// EnvironmentMap SH path and the primary light into Scene.directionalLight;
// nothing applies them yet.
/// {@category Features}
class XrLightEstimate {
  /// An estimate with zero light.
  XrLightEstimate()
    : sphericalHarmonics = Float32List(27),
      primaryLightDirection = Vector3(0.0, 1.0, 0.0),
      primaryLightIntensity = Vector3.zero();

  /// Nine RGB SH coefficients, 27 floats.
  final Float32List sphericalHarmonics;

  /// The direction the primary light comes from, unit length, in the
  /// session's reference space.
  final Vector3 primaryLightDirection;

  /// The primary light's linear RGB intensity.
  final Vector3 primaryLightIntensity;
}
