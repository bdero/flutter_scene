import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene/src/node.dart';

/// Where a camera is, which way it faces, and (optionally) what lens it
/// looks through: the value a [CameraController] produces each frame and a
/// [CameraDirector] blends between.
///
/// A pose is the camera's *state* separated from whatever computes it. That
/// separation is what makes cutscenes possible: two controllers can each keep
/// producing their own pose while the director shows an interpolation of the
/// two, and neither has to know the other exists.
///
/// The orientation convention matches [NodeCamera] and [Node.lookAt]: local
/// `+Z` is the look direction, `+Y` is up, `+X` is right. Applying a pose to
/// a node ([applyTo]) therefore reproduces exactly what
/// `node.lookAtFrom(eye, target)` would.
///
/// [projection] is the lens, and is usually null. A null projection means
/// "whatever lens the camera already has", so a controller only fills it in
/// when it wants to *drive* the lens: a scripted focal-length change, a
/// dolly zoom, or an orthographic shot in an otherwise perspective scene.
/// {@category Scene graph}
class CameraPose {
  /// Creates a pose at [position] oriented by [rotation] (which is
  /// normalized; local `+Z` becomes the look direction).
  CameraPose({
    required Vector3 position,
    required Quaternion rotation,
    this.projection,
  }) : position = position.clone(),
       rotation = rotation.normalized();

  /// A pose at [eye] looking toward [target], with [up] (default `+Y`) as the
  /// reference up.
  ///
  /// Throws the same assertions as [Node.lookAtTransform] when the direction
  /// is degenerate (target on the eye, or an up parallel to the view
  /// direction). For a top-down camera pass `Vector3(0, 0, 1)` as [up].
  factory CameraPose.lookAt(
    Vector3 eye,
    Vector3 target, {
    Vector3? up,
    CameraProjection? projection,
  }) => CameraPose.fromMatrix(
    Node.lookAtTransform(eye, target, up: up),
    projection: projection,
  );

  /// A pose read out of a world [transform] (its translation and rotation;
  /// any scale is dropped).
  factory CameraPose.fromMatrix(
    Matrix4 transform, {
    CameraProjection? projection,
  }) {
    final basis = transform.getRotation();
    // Strip scale so the extracted quaternion is a pure rotation even when the
    // source transform carries one.
    final x = Vector3(basis.entry(0, 0), basis.entry(1, 0), basis.entry(2, 0));
    final y = Vector3(basis.entry(0, 1), basis.entry(1, 1), basis.entry(2, 1));
    final z = Vector3(basis.entry(0, 2), basis.entry(1, 2), basis.entry(2, 2));
    final normalized = Matrix3.columns(
      x.length > 1e-9 ? x.normalized() : Vector3(1.0, 0.0, 0.0),
      y.length > 1e-9 ? y.normalized() : Vector3(0.0, 1.0, 0.0),
      z.length > 1e-9 ? z.normalized() : Vector3(0.0, 0.0, 1.0),
    );
    return CameraPose(
      position: transform.getTranslation(),
      rotation: Quaternion.fromRotation(normalized),
      projection: projection,
    );
  }

  /// A pose at [position] with an explicitly given orthonormal basis.
  ///
  /// Use this instead of [CameraPose.lookAt] when the look direction may
  /// become parallel to the reference up: a look-at needs a world up to cross
  /// against and has no answer for a camera pointing straight down, while a
  /// basis computed from the camera's own yaw is defined everywhere. That
  /// makes it the right constructor for top-down and strategy cameras.
  ///
  /// The vectors must be unit length and mutually perpendicular, and follow
  /// the scene graph's convention: `up.cross(forward) == right`.
  factory CameraPose.fromBasis(
    Vector3 position, {
    required Vector3 right,
    required Vector3 up,
    required Vector3 forward,
    CameraProjection? projection,
  }) {
    assert(
      (up.cross(forward) - right).length < 1e-3,
      'The camera basis is not right-handed in the scene graph convention: '
      'up.cross(forward) must equal right.',
    );
    return CameraPose(
      position: position,
      rotation: Quaternion.fromRotation(Matrix3.columns(right, up, forward)),
      projection: projection,
    );
  }

  /// The pose [node] currently sits at, from its world transform.
  factory CameraPose.of(Node node, {CameraProjection? projection}) =>
      CameraPose.fromMatrix(node.globalTransform, projection: projection);

  /// A pose at the world origin looking down `+Z`, the identity element for
  /// a director with nothing to show yet.
  static CameraPose get identity =>
      CameraPose(position: Vector3.zero(), rotation: Quaternion.identity());

  /// The world-space eye point.
  final Vector3 position;

  /// The orientation: local `+Z` is the look direction, `+Y` is up.
  final Quaternion rotation;

  /// The lens to use, or null to leave the camera's current lens alone.
  final CameraProjection? projection;

  /// The unit look direction (rotated local `+Z`).
  Vector3 get forward => _rotate(rotation, Vector3(0.0, 0.0, 1.0));

  /// The unit up direction (rotated local `+Y`).
  Vector3 get up => _rotate(rotation, Vector3(0.0, 1.0, 0.0));

  /// The unit right direction (rotated local `+X`).
  Vector3 get right => _rotate(rotation, Vector3(1.0, 0.0, 0.0));

  /// This pose as a world transform (unit scale).
  Matrix4 toMatrix() =>
      Matrix4.compose(position, rotation, Vector3(1.0, 1.0, 1.0));

  /// Writes this pose onto [node]'s world transform, preserving the node's
  /// existing scale (a camera node is not normally scaled, but a pose should
  /// not silently reset one that is).
  void applyTo(Node node) {
    final world = node.globalTransform.storage;
    final scale = Vector3(
      Vector3(world[0], world[1], world[2]).length,
      Vector3(world[4], world[5], world[6]).length,
      Vector3(world[8], world[9], world[10]).length,
    );
    node.globalTransform = Matrix4.compose(position, rotation, scale);
  }

  /// Interpolates toward [to] by [weight] in `[0, 1]`: position lerps,
  /// rotation slerps along the short arc, and the lens blends per
  /// [CameraProjection.lerpTo].
  ///
  /// When only one side names a [projection] that projection is used
  /// outright rather than blended, since there is nothing to blend it
  /// against; see [CameraDirector] for how a null lens resolves in practice.
  CameraPose lerpTo(CameraPose to, double weight) {
    if (weight <= 0.0) return this;
    if (weight >= 1.0) return to;
    final from = projection;
    final into = to.projection;
    final CameraProjection? lens;
    if (from == null) {
      lens = into;
    } else if (into == null) {
      lens = from;
    } else {
      lens = from.lerpTo(into, weight);
    }
    return CameraPose(
      position: position.lerp(to.position, weight),
      rotation: rotation.slerp(to.rotation, weight),
      projection: lens,
    );
  }

  /// A copy of this pose with the given fields replaced.
  CameraPose copyWith({
    Vector3? position,
    Quaternion? rotation,
    CameraProjection? projection,
  }) => CameraPose(
    position: position ?? this.position,
    rotation: rotation ?? this.rotation,
    projection: projection ?? this.projection,
  );

  /// This pose displaced by [offset] expressed in the camera's own local
  /// space (`+X` right, `+Y` up, `+Z` forward), for handheld sway, camera
  /// shake, and lens offsets.
  CameraPose translatedLocal(Vector3 offset) =>
      copyWith(position: position + _rotate(rotation, offset));

  /// This pose rotated by [delta] in the camera's own local space, applied
  /// after the existing orientation.
  CameraPose rotatedLocal(Quaternion delta) =>
      copyWith(rotation: (rotation * delta).normalized());

  @override
  String toString() =>
      'CameraPose(position: $position, forward: $forward, lens: $projection)';
}

/// Rotates [v] by [q] in the convention the scene graph uses, the one
/// [Matrix4.compose] and [Quaternion.fromRotation] agree on.
///
/// Deliberately not `Quaternion.rotate`: vector_math applies the *inverse* of
/// the rotation that `Matrix4.compose` builds from the same quaternion, so a
/// pose using it would report a look direction pointing backwards while its
/// matrix looked the right way.
Vector3 _rotate(Quaternion q, Vector3 v) {
  final axis = Vector3(q.x, q.y, q.z);
  final cross = axis.cross(v);
  return v + cross * (2.0 * q.w) + axis.cross(cross) * 2.0;
}
