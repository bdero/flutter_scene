import 'package:vector_math/vector_math.dart';

/// The camera a pass rasterizes with, recovered from its view-projection,
/// for fragments that need the view axis (a parallax silhouette marching the
/// light's view in a shadow map).
class PassCamera {
  /// Recovers the camera of [viewProjection], whose clip depth increases away
  /// from the eye.
  factory PassCamera.fromViewProjection(Matrix4 viewProjection) {
    final m = viewProjection;
    final rowX = Vector3(m.entry(0, 0), m.entry(0, 1), m.entry(0, 2));
    final rowY = Vector3(m.entry(1, 0), m.entry(1, 1), m.entry(1, 2));
    final rowZ = Vector3(m.entry(2, 0), m.entry(2, 1), m.entry(2, 2));
    final rowW = Vector3(m.entry(3, 0), m.entry(3, 1), m.entry(3, 2));
    // Along the view axis clip x and y hold still, and clip depth grows.
    final axis = rowX.cross(rowY);
    if (axis.length2 > 0) axis.normalize();
    if (axis.dot(rowZ) < 0) axis.negate();
    final scale = rowW.length + rowX.length + rowY.length;
    if (rowW.length <= 1e-6 * scale) {
      return PassCamera._(Vector3.zero(), axis, orthographic: true);
    }
    // The eye is where clip x, y and w are all 0.
    final inverse = Matrix4.copy(m)..invert();
    final eye = inverse.transform(Vector4(0, 0, 1, 0));
    final position = eye.w.abs() > 1e-12
        ? Vector3(eye.x / eye.w, eye.y / eye.w, eye.z / eye.w)
        : Vector3.zero();
    // Clip w is the distance along the view axis, so it grows forward.
    final forward = rowW.normalized();
    return PassCamera._(position, forward, orthographic: false);
  }

  PassCamera._(this.position, this.forward, {required this.orthographic});

  /// The eye, meaningful only for a perspective camera.
  final Vector3 position;

  /// The unit view axis, from the eye into the scene.
  final Vector3 forward;

  /// Whether every view ray runs along [forward].
  final bool orthographic;
}
