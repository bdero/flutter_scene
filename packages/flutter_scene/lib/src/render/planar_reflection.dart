import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

/// One frame's planar reflection capture: the mirrored scene color and the
/// view-projection that rendered it.
///
/// The reflector distributes a frame to the mirror surface's materials each
/// frame; the material projects its fragment's world position through
/// [viewProjection] to find the capture UV holding that point's reflection.
class PlanarReflectionFrame {
  PlanarReflectionFrame({required this.texture, required this.viewProjection});

  /// The linear HDR capture rendered from the reflected camera.
  final gpu.Texture texture;

  /// The capture camera's combined projection-and-view transform.
  final Matrix4 viewProjection;
}

/// The world-space transform reflecting points across [plane]
/// (`normal . x + constant = 0`, normal unit length).
Matrix4 planarReflectionMatrix(Plane plane) {
  final n = plane.normal;
  final d = plane.constant;
  return Matrix4(
    1.0 - 2.0 * n.x * n.x,
    -2.0 * n.x * n.y,
    -2.0 * n.x * n.z,
    0.0, //
    -2.0 * n.y * n.x,
    1.0 - 2.0 * n.y * n.y,
    -2.0 * n.y * n.z,
    0.0, //
    -2.0 * n.z * n.x,
    -2.0 * n.z * n.y,
    1.0 - 2.0 * n.z * n.z,
    0.0, //
    -2.0 * d * n.x,
    -2.0 * d * n.y,
    -2.0 * d * n.z,
    1.0, //
  );
}

/// Reflects point [p] across [plane].
Vector3 reflectPointAcrossPlane(Vector3 p, Plane plane) {
  final distance = plane.normal.dot(p) + plane.constant;
  return p - plane.normal * (2.0 * distance);
}

/// Reflects direction [d] across [plane]'s orientation.
Vector3 reflectDirectionAcrossPlane(Vector3 d, Plane plane) {
  return d - plane.normal * (2.0 * plane.normal.dot(d));
}

/// Transforms world-space [plane] into the view space of [viewMatrix]
/// (the inverse-transpose plane transform), as a (normal.xyz, constant)
/// four-vector. The result is not renormalized; the oblique projection
/// below is scale-invariant in the plane.
Vector4 planeToViewSpace(Plane plane, Matrix4 viewMatrix) {
  final inverse = Matrix4.zero();
  if (inverse.copyInverse(viewMatrix) == 0.0) {
    return Vector4(
      plane.normal.x,
      plane.normal.y,
      plane.normal.z,
      plane.constant,
    );
  }
  final world = Vector4(
    plane.normal.x,
    plane.normal.y,
    plane.normal.z,
    plane.constant,
  );
  // (V^-1)^T * plane, computed as plane . columns of V^-1.
  final transposed = inverse..transpose();
  return transposed.transform(world);
}

// Reads row [row] of column-major [m] as a Vector4.
Vector4 _row(Matrix4 m, int row) =>
    Vector4(m.entry(row, 0), m.entry(row, 1), m.entry(row, 2), m.entry(row, 3));

// Writes row [row] of column-major [m].
void _setRow(Matrix4 m, int row, Vector4 value) {
  m.setEntry(row, 0, value.x);
  m.setEntry(row, 1, value.y);
  m.setEntry(row, 2, value.z);
  m.setEntry(row, 3, value.w);
}

/// Returns [projection] with its near plane replaced by the view-space clip
/// plane [clipPlane] (`clipPlane . v >= 0` is kept), the standard oblique
/// near-plane modification for a depth range of `[0, 1]`.
///
/// Points on the plane map to depth 0 and the far corner most opposed to the
/// plane still maps to depth 1, so far clipping degrades minimally. Returns
/// [projection] unchanged when the plane is degenerate for this frustum.
Matrix4 obliqueNearClipProjection(Matrix4 projection, Vector4 clipPlane) {
  final inverse = Matrix4.zero();
  if (inverse.copyInverse(projection) == 0.0) {
    return projection;
  }
  // The far corner of the frustum on the plane's positive side, in view
  // space: unproject the clip-space corner whose xy signs follow the plane.
  final corner = inverse.transform(
    Vector4(
      clipPlane.x >= 0 ? 1.0 : -1.0,
      clipPlane.y >= 0 ? 1.0 : -1.0,
      1.0,
      1.0,
    ),
  );
  final denominator = clipPlane.dot(corner);
  if (denominator.abs() < 1e-12) {
    return projection;
  }
  final result = Matrix4.copy(projection);
  final scale = _row(projection, 3).dot(corner) / denominator;
  _setRow(result, 2, clipPlane.scaled(scale));
  return result;
}

/// A [CameraProjection] wrapping [base] with its near plane clamped to a
/// world-space mirror plane (see [obliqueNearClipProjection]).
class ObliqueNearClipProjection extends CameraProjection {
  ObliqueNearClipProjection({
    required this.base,
    required Plane worldPlane,
    required Matrix4 viewMatrix,
    double clipBias = 0.0,
  }) : _viewSpacePlane = planeToViewSpace(
         Plane.normalconstant(
           worldPlane.normal,
           worldPlane.constant - clipBias,
         ),
         viewMatrix,
       );

  /// The unclipped projection this wraps.
  final CameraProjection base;

  final Vector4 _viewSpacePlane;

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) =>
      obliqueNearClipProjection(
        base.getProjectionMatrix(aspectRatio, jitter: jitter),
        _viewSpacePlane,
      );
}

/// The camera a planar reflection capture renders with: [source] reflected
/// across [plane], with an oblique projection that clips geometry behind the
/// mirror (offset [clipBias] world units in front of it).
///
/// The reflected basis is proper (built from the reflected position, aim, and
/// up through the engine's look-at), so the capture draws with unflipped
/// winding; sampling projects the fragment's world position through the
/// capture's view-projection, which makes the mirroring consistent by
/// construction.
class PlanarReflectionCamera extends Camera {
  PlanarReflectionCamera({
    required Camera source,
    required Plane plane,
    double clipBias = 0.0,
  }) : _inner = PerspectiveCamera(
         position: reflectPointAcrossPlane(source.position, plane),
         target:
             reflectPointAcrossPlane(source.position, plane) +
             reflectDirectionAcrossPlane(source.forward, plane),
         up: reflectDirectionAcrossPlane(source.up, plane),
       ) {
    final base = source.projection;
    _projection = base is PerspectiveProjection
        ? ObliqueNearClipProjection(
            base: PerspectiveProjection(
              fovRadiansY: base.fovRadiansY,
              near: base.near,
              far: base.far,
            ),
            worldPlane: plane,
            viewMatrix: _inner.getViewMatrix(),
            clipBias: clipBias,
          )
        : base;
  }

  final PerspectiveCamera _inner;
  late final CameraProjection _projection;

  @override
  Vector3 get position => _inner.position;

  @override
  Vector3 get forward => _inner.forward;

  @override
  Vector3 get up => _inner.up;

  @override
  CameraProjection get projection => _projection;

  @override
  Matrix4 getViewMatrix() => _inner.getViewMatrix();
}
