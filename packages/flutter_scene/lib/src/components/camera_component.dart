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
///
/// When the owning node is mounted in a scene, the component registers as a
/// candidate for the scene's primary camera (`Scene.camera`). The first
/// camera mounted becomes the primary automatically; call [makeActive] to
/// select this one explicitly.
/// {@category Scene graph}
class CameraComponent extends Component {
  /// Creates a camera component with the given [projection] (a
  /// [PerspectiveProjection] by default).
  CameraComponent({CameraProjection? projection})
    : _projection = projection ?? PerspectiveProjection();

  CameraProjection _projection;

  /// The lens projection for this camera.
  CameraProjection get projection => _projection;
  set projection(CameraProjection value) {
    _projection = value;
    // Keep the cached camera (held by RenderViews or as the scene primary) in
    // sync so a projection change takes effect without re-fetching.
    _camera?.projection = value;
  }

  // Memoized so repeated resolution does not allocate and so the camera has a
  // stable identity (used by [active] and the scene primary). Invalidated when
  // the component is detached, since a new attachment may use a new node.
  NodeCamera? _camera;

  bool _activateOnMount = false;

  /// Returns a [NodeCamera] backed by the owning node.
  ///
  /// The returned camera tracks the node: moving or rotating the node
  /// moves the view on the next frame, so it is safe to hold in a
  /// persistent `RenderView`. The same instance is returned across calls
  /// while the component stays attached.
  NodeCamera toCamera() => _camera ??= NodeCamera(node, _projection);

  /// Makes this the scene's primary camera, overriding auto-promotion.
  ///
  /// If the owning node is not yet mounted, the selection is deferred and
  /// applied when it mounts.
  void makeActive() {
    final renderScene = isAttached ? node.internalRenderScene : null;
    if (renderScene != null) {
      renderScene.cameraOverride = toCamera();
    } else {
      _activateOnMount = true;
    }
  }

  /// Whether the scene's primary camera currently resolves to this component.
  bool get active {
    final renderScene = isAttached ? node.internalRenderScene : null;
    return renderScene != null &&
        identical(renderScene.primaryCamera, toCamera());
  }

  @override
  void onMount() {
    node.internalRenderScene?.addCamera(this);
    if (_activateOnMount) {
      _activateOnMount = false;
      node.internalRenderScene?.cameraOverride = toCamera();
    }
  }

  @override
  void onUnmount() {
    node.internalRenderScene?.removeCamera(this);
  }

  @override
  void onDetach() {
    // A reattachment may bind a different node, so drop the cached camera.
    _camera = null;
  }
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
  CameraProjection projection;

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
