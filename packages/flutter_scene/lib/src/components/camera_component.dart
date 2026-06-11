import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/component.dart';

/// An engine [Component] that places a [Camera] in the scene.
///
/// The camera's view (eye position and orientation) comes from the owning
/// node's world transform: the node's translation is the eye, its local
/// `+Z` axis is the look direction, and its local `+Y` axis is up. The
/// [projection] (the lens) is configured on the component. Move or rotate
/// the node to move or aim the camera.
///
/// Use [toCamera] to capture a [Camera] for the node's current transform to
/// pass to `Scene.render`. (The node should not be scaled; a camera node is
/// expected to carry only rotation and translation.)
/// {@category Scene graph}
class CameraComponent extends Component {
  /// Creates a camera component with the given [projection] (a
  /// [PerspectiveProjection] by default).
  CameraComponent({CameraProjection? projection})
    : projection = projection ?? PerspectiveProjection();

  /// The lens projection for this camera.
  CameraProjection projection;

  /// Returns a [Camera] for the owning node's current world transform.
  ///
  /// The returned camera snapshots the transform, so subsequently moving
  /// the node does not change it; call [toCamera] again for an updated
  /// view.
  Camera toCamera() => _NodeCamera(node.globalTransform.clone(), projection);
}

/// A [Camera] whose view comes from a world transform: the `+Z` axis is the
/// look direction, `+Y` is up, and the translation is the eye. This is the
/// inverse of the eye/target/up convention [PerspectiveCamera] builds, so a
/// node placed at `inverse(camera.getViewMatrix())` yields the same view.
class _NodeCamera extends Camera {
  _NodeCamera(this._worldTransform, this.projection);

  final Matrix4 _worldTransform;

  @override
  final CameraProjection projection;

  @override
  Vector3 get position => _worldTransform.getTranslation();

  @override
  Vector3 get forward => Vector3(
    _worldTransform[8],
    _worldTransform[9],
    _worldTransform[10],
  ).normalized();

  @override
  Vector3 get up => Vector3(
    _worldTransform[4],
    _worldTransform[5],
    _worldTransform[6],
  ).normalized();

  @override
  Matrix4 getViewMatrix() {
    // The view matrix is the inverse of the camera's world transform.
    // copyInverse(arg) writes inverse(arg) into the receiver.
    final view = Matrix4.identity();
    view.copyInverse(_worldTransform);
    return view;
  }
}
