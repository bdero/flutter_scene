import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';

/// An engine [Component] that places a [Camera] in the scene.
///
/// The camera's view (eye position and orientation) comes from the owning
/// node's world transform: the node's translation is the eye, its local
/// `+Z` axis is the look direction, and its local `+Y` axis is up. The
/// [projection] (the lens) is configured on the component. Move or rotate
/// the node to move or aim the camera.
///
/// Use [toCamera] to get a [Camera] backed by the node, suitable for
/// `Scene.render` or a persistent `RenderView`. (The node should not be
/// scaled; a camera node is expected to carry only rotation and
/// translation.)
/// {@category Scene graph}
class CameraComponent extends Component {
  /// Creates a camera component with the given [projection] (a
  /// [PerspectiveProjection] by default).
  CameraComponent({CameraProjection? projection})
    : projection = projection ?? PerspectiveProjection();

  /// The lens projection for this camera.
  CameraProjection projection;

  /// Returns a [NodeCamera] backed by the owning node.
  ///
  /// The returned camera tracks the node: moving or rotating the node
  /// moves the view on the next frame, so it is safe to hold in a
  /// persistent `RenderView`.
  NodeCamera toCamera() => NodeCamera(node, projection);
}

/// A [Camera] whose view comes from a [node]'s world transform: the `+Z`
/// axis is the look direction, `+Y` is up, and the translation is the eye.
/// This is the inverse of the eye/target/up convention [PerspectiveCamera]
/// builds, so a node placed at `inverse(camera.getViewMatrix())` yields
/// the same view.
///
/// The transform is read at render time, so the camera tracks the node
/// live. Usually obtained from [CameraComponent.toCamera].
/// {@category Scene graph}
class NodeCamera extends Camera {
  /// Creates a camera that tracks [node] with the given [projection].
  NodeCamera(this.node, this.projection);

  /// The node whose world transform drives the view.
  final Node node;

  @override
  final CameraProjection projection;

  Matrix4 get _worldTransform => node.globalTransform;

  @override
  Vector3 get position => _worldTransform.getTranslation();

  @override
  Vector3 get forward {
    final transform = _worldTransform;
    return Vector3(transform[8], transform[9], transform[10]).normalized();
  }

  @override
  Vector3 get up {
    final transform = _worldTransform;
    return Vector3(transform[4], transform[5], transform[6]).normalized();
  }

  @override
  Matrix4 getViewMatrix() {
    // The view matrix is the inverse of the camera's world transform.
    // copyInverse(arg) writes inverse(arg) into the receiver.
    final view = Matrix4.identity();
    view.copyInverse(_worldTransform);
    return view;
  }
}
