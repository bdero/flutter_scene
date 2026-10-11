import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene_xr/src/xr_frame.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_pose.dart';

/// The nodes an XR session drives, under one [origin] the app places.
///
/// Add [origin] to the scene and move it to put the player somewhere; the
/// runtime's reference space origin lands there. Each frame,
/// [applyFrame] moves [head], one camera node per view ([eyes]), and the
/// [controller], [hand] and [targetRay] nodes from the frame's poses, and
/// returns the [RenderView]s for `Scene.renderViewsToTargets`. Attach a
/// controller model or a hand mesh by parenting it to the matching node.
///
/// Poses arrive in the runtime's convention (right-handed, `+Y` up, a tracked
/// thing looking along its local `-Z`) and are mapped into the scene's by
/// [xrToScene]. Nothing here allocates per frame; the views and projections
/// are refilled in place.
/// {@category Rig}
class XrRig {
  /// A rig whose eye cameras clip at [near] and [far] until a frame states a
  /// lens. [xrToScene] replaces the default pose mapping.
  XrRig({Matrix4? xrToScene, this.near = 0.05, this.far = 1000.0}) {
    _xrToScene.setFrom(xrToScene ?? defaultXrToScene());
    _xrToSceneInverse.copyInverse(_xrToScene);
    origin.add(head);
  }

  /// The mapping from the runtime's pose convention into the scene's that
  /// [xrToScene] starts with.
  ///
  /// A node's forward axis is its local `+Z` and a camera on a node looks
  /// down it, while a runtime's viewer looks down `-Z`, so the default
  /// reflects `Z`. Applied as a change of basis (`M * pose * M⁻¹`) the
  /// reflection turns every pose into a proper rotation again, so cameras,
  /// controllers and hands all land with their forward on `+Z` and their
  /// right still on `+X`.
  // TODO(xr-handedness): the pending right-handed world migration
  // (flutter_scene PR #499) makes the node forward axis -Z, which turns this
  // default into the identity; flip it when that lands and drop this note.
  static Matrix4 defaultXrToScene() => Matrix4.diagonal3Values(1.0, 1.0, -1.0);

  /// The near clip distance eye cameras start with.
  final double near;

  /// The far clip distance eye cameras start with.
  final double far;

  /// The reference space origin. Move this to move the player.
  final Node origin = Node(name: 'xr_origin');

  /// The viewer, between the eyes. A child of [origin].
  final Node head = Node(name: 'xr_head');

  /// One camera node per view, children of [origin], created as frames need
  /// them. Index matches `XrFrame.views`.
  final List<Node> eyes = [];

  /// The camera component on each of [eyes].
  final List<CameraComponent> eyeCameras = [];

  /// The render views [applyFrame] fills, one per view of the latest frame.
  /// The list instance is stable, so a `RenderViewGroup` can hold it.
  final List<RenderView> views = [];

  final Matrix4 _xrToScene = Matrix4.identity();
  final Matrix4 _xrToSceneInverse = Matrix4.identity();
  final Matrix4 _poseMatrix = Matrix4.identity();
  final Matrix4 _scratch = Matrix4.identity();
  // Held once so the per-frame mutateLocalTransform call allocates nothing.
  late final void Function(Matrix4) _writeScratch = _writeScratchInto;

  final Map<XrHandedness, Node> _controllers = {};
  final Map<XrHandedness, Node> _targetRays = {};
  final Map<XrHandedness, Node> _hands = {};
  final Map<XrHandedness, List<Node>> _handJoints = {};
  final List<RenderView> _allViews = [];

  /// The change of basis from the runtime's pose convention into the
  /// scene's, applied to every pose [applyFrame] receives. Assigning copies
  /// the matrix; see [defaultXrToScene].
  Matrix4 get xrToScene => _xrToScene;
  set xrToScene(Matrix4 value) {
    _xrToScene.setFrom(value);
    _xrToSceneInverse.copyInverse(_xrToScene);
  }

  /// The node a held controller's grip pose drives, created on first use
  /// under [origin] and hidden while the controller is not tracked.
  Node controller(XrHandedness handedness) => _controllers.putIfAbsent(
    handedness,
    () => _child('xr_controller_${handedness.name}'),
  );

  /// The node an input source's target ray drives, pointing along its
  /// forward axis. Created on first use under [origin].
  Node targetRay(XrHandedness handedness) => _targetRays.putIfAbsent(
    handedness,
    () => _child('xr_target_ray_${handedness.name}'),
  );

  /// The container for a tracked hand's joint nodes ([handJoints]), created
  /// on first use under [origin] and hidden while the hand is not tracked.
  Node hand(XrHandedness handedness) => _hands.putIfAbsent(
    handedness,
    () => _child('xr_hand_${handedness.name}'),
  );

  /// One node per [XrHandJoint] in enum order, children of [hand].
  List<Node> handJoints(XrHandedness handedness) =>
      _handJoints.putIfAbsent(handedness, () {
        final parent = hand(handedness);
        final joints = [
          for (final joint in XrHandJoint.values)
            Node(name: 'xr_joint_${joint.webName}'),
        ];
        joints.forEach(parent.add);
        return joints;
      });

  /// The ray leaving [head] along its forward axis, in world space.
  Ray get gaze =>
      Ray.originDirection(head.globalTransform.getTranslation(), head.forward);

  /// Moves the rig's nodes to [frame]'s poses and returns the views to
  /// render, each with the frame's target and its view's viewport.
  List<RenderView> applyFrame(XrFrame frame) {
    final viewer = frame.viewerPose;
    if (viewer != null) {
      _applyPose(head, viewer);
    }
    _ensureEyes(frame.views.length);
    for (var i = 0; i < frame.views.length; i++) {
      final view = frame.views[i];
      _applyPose(eyes[i], view.pose);
      final projection = eyeCameras[i].projection as OffAxisProjection;
      final lens = view.projection;
      projection
        ..tanLeft = lens.tanLeft
        ..tanRight = lens.tanRight
        ..tanDown = lens.tanDown
        ..tanUp = lens.tanUp
        ..near = lens.near
        ..far = lens.far;
      views[i]
        ..externalTarget = view.target ?? frame.target
        ..viewport = view.viewport;
    }
    _applyInputSources(frame.inputSources);
    return views;
  }

  void _applyInputSources(List<XrInputSourceState> sources) {
    for (final node in _controllers.values) {
      node.visible = false;
    }
    for (final node in _targetRays.values) {
      node.visible = false;
    }
    for (final node in _hands.values) {
      node.visible = false;
    }
    for (final source in sources) {
      final ray = source.targetRayPose;
      if (ray != null) {
        final node = targetRay(source.handedness);
        _applyPose(node, ray);
        node.visible = true;
      }
      final grip = source.gripPose ?? ray;
      if (grip != null) {
        final node = controller(source.handedness);
        _applyPose(node, grip);
        node.visible = true;
      }
      final hand = source.hand;
      if (hand != null && hand.isTracked) {
        final container = this.hand(source.handedness);
        container.visible = true;
        final joints = handJoints(source.handedness);
        for (var j = 0; j < joints.length; j++) {
          final tracked = hand.jointTracked[j];
          joints[j].visible = tracked;
          if (tracked) _applyPose(joints[j], hand.jointPoses[j]);
        }
      }
    }
  }

  void _ensureEyes(int count) {
    while (eyes.length < count) {
      final node = _child('xr_eye_${eyes.length}');
      final camera = CameraComponent(
        projection: OffAxisProjection.symmetric(near: near, far: far),
      );
      node.addComponent(camera);
      eyes.add(node);
      eyeCameras.add(camera);
      _allViews.add(RenderView(camera: camera.toCamera()));
    }
    if (views.length != count) {
      views
        ..clear()
        ..addAll(_allViews.take(count));
    }
  }

  // Writes pose, rebased by xrToScene, into node's local transform.
  void _applyPose(Node node, XrPose pose) {
    pose.copyIntoMatrix(_poseMatrix);
    _scratch
      ..setFrom(_xrToScene)
      ..multiply(_poseMatrix)
      ..multiply(_xrToSceneInverse);
    node.mutateLocalTransform(_writeScratch);
  }

  void _writeScratchInto(Matrix4 transform) => transform.setFrom(_scratch);

  Node _child(String name) {
    final node = Node(name: name);
    origin.add(node);
    return node;
  }
}
