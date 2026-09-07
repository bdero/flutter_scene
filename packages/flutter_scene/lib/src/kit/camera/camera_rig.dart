import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/camera_director.dart';
import 'package:flutter_scene/src/camera_controllers/camera_path.dart';
import 'package:flutter_scene/src/camera_controllers/dolly_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/first_person_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/fly_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/follow_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/orbit_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/rts_camera_controller.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/kit/camera/camera_shake.dart';
import 'package:flutter_scene/src/node.dart';

/// A camera, assembled: the node, the [CameraComponent], a [CameraDirector],
/// and a [controller], wired together and ready to add to a scene.
///
/// Setting a camera up by hand is four steps that are the same every time —
/// make a node, give it a camera component, make it the active camera, attach
/// a controller. A rig is those four steps in one call, per kind of game:
///
/// ```dart
/// final rig = CameraRig.firstPerson(followTarget: player);
/// scene.add(rig.node);
///
/// // In the view:
/// CameraControls(controller: rig.input, child: SceneView(scene: scene))
/// ```
///
/// Every rig comes with a director even when there is only one camera in it,
/// so adding a second shot later is [add] and [CameraDirector.blendTo] rather
/// than a rebuild. [controller] is typed to the rig's own camera, so
/// `rig.controller.addRecoil(...)` on a first-person rig needs no cast.
/// {@category Gameplay kit}
class CameraRig<T extends CameraController> {
  /// Assembles a rig around [controller].
  ///
  /// [projection] is the starting lens; a controller that drives the lens
  /// itself (a strategy camera in orthographic mode) overwrites it on the
  /// first frame. [activateOnMount] makes this the scene's primary camera
  /// when its node is added, which is what a single-camera game wants.
  CameraRig(
    this.controller, {
    CameraProjection? projection,
    CameraBlend? defaultBlend,
    CameraShake? shake,
    bool activateOnMount = true,
    String name = 'camera',
  }) : node = Node(name: name),
       camera = CameraComponent(
         projection: projection,
         activateOnMount: activateOnMount,
       ),
       director = CameraDirector(
         defaultBlend: defaultBlend ?? const CameraBlend(0.75),
         shake: shake,
       ) {
    node.addComponent(camera);
    node.addComponent(director);
    director.add(controller, name: name);
  }

  /// The node carrying the camera. Add it to a scene.
  final Node node;

  /// The camera component on [node].
  final CameraComponent camera;

  /// The director blending between this rig's cameras.
  final CameraDirector director;

  /// The rig's primary camera controller.
  final T controller;

  /// Shake layered on the final pose. Add trauma with
  /// [CameraShake.addTrauma].
  CameraShake? get shake => director.shake;
  set shake(CameraShake? value) => director.shake = value;

  /// The controller to hand a `CameraControls` widget: it forwards input to
  /// whichever camera is live, so it keeps working across cuts.
  CameraController get input => director.input;

  /// Registers another camera with this rig's director and returns it, so a
  /// cutscene shot can be declared inline.
  C add<C extends CameraController>(
    C camera, {
    double priority = 0.0,
    String? name,
  }) {
    director.add(camera, priority: priority, name: name);
    return camera;
  }

  /// A first-person rig: the eye rides [followTarget]'s head.
  ///
  /// The default 75-degree field of view is the usual first-person choice;
  /// the engine's 45-degree default is a third-person framing and feels
  /// claustrophobic from inside a character's eyes.
  static CameraRig<FirstPersonCameraController> firstPerson({
    Node? followTarget,
    Vector3? eyeOffset,
    Vector3? position,
    double fovRadiansY = 75 * degrees2Radians,
    double lookSensitivity = 0.005,
    HeadBob? headBob,
    CameraShake? shake,
    String name = 'firstPersonCamera',
  }) => CameraRig(
    FirstPersonCameraController(
      followTarget: followTarget,
      eyeOffset: eyeOffset,
      position: position,
      lookSensitivity: lookSensitivity,
      headBob: headBob,
    ),
    projection: PerspectiveProjection(fovRadiansY: fovRadiansY),
    shake: shake,
    name: name,
  );

  /// A third-person rig trailing [followTarget].
  ///
  /// Pass [occludeAgainst] (usually `scene.root`) to have the camera pull in
  /// when geometry comes between it and the character, instead of clipping
  /// through it.
  static CameraRig<FollowCameraController> thirdPerson({
    required Node followTarget,
    double distance = 6.0,
    double lookHeight = 1.4,
    Node? occludeAgainst,
    CameraShake? shake,
    String name = 'thirdPersonCamera',
  }) {
    final controller = FollowCameraController(
      followTarget: followTarget,
      distance: distance,
      lookHeight: lookHeight,
    );
    if (occludeAgainst != null) controller.occludeAgainst(occludeAgainst);
    return CameraRig(controller, shake: shake, name: name);
  }

  /// An orbit rig for inspecting a model or a scene: drag to turn, scroll to
  /// zoom, two fingers to pan.
  static CameraRig<OrbitCameraController> orbit({
    Vector3? target,
    double distance = 6.0,
    double azimuth = 0.0,
    double polar = 0.3,
    String name = 'orbitCamera',
  }) => CameraRig(
    OrbitCameraController(
      target: target,
      distance: distance,
      azimuth: azimuth,
      polar: polar,
    ),
    name: name,
  );

  /// A free-flying rig, for debugging a level or previewing a scene.
  static CameraRig<FlyCameraController> fly({
    Vector3? position,
    double speed = 5.0,
    String name = 'flyCamera',
  }) => CameraRig(
    FlyCameraController(position: position, speed: speed),
    name: name,
  );

  /// A strategy rig looking down at the map: drag or edge-scroll to pan,
  /// right-drag to turn, wheel to zoom.
  static CameraRig<RtsCameraController> rts({
    Vector3? focus,
    double yaw = 0.0,
    double pitch = 0.9,
    double distance = 40.0,
    bool orthographic = false,
    Aabb3? bounds,
    EdgeScroll? edgeScroll,
    double Function(double x, double z)? groundHeightAt,
    String name = 'rtsCamera',
  }) => CameraRig(
    RtsCameraController(
      focus: focus,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      orthographic: orthographic,
      bounds: bounds,
      edgeScroll: edgeScroll,
      groundHeightAt: groundHeightAt,
    ),
    projection: orthographic ? OrthographicProjection() : null,
    name: name,
  );

  /// An isometric rig: a fixed viewpoint through an orthographic lens, the
  /// framing isometric art is drawn for.
  static CameraRig<RtsCameraController> isometric({
    Vector3? focus,
    double yaw = math.pi / 4,
    double viewHeight = 30.0,
    double rotateSpeed = 0.0,
    Aabb3? bounds,
    EdgeScroll? edgeScroll,
    String name = 'isometricCamera',
  }) => CameraRig(
    RtsCameraController.isometric(
      focus: focus,
      yaw: yaw,
      viewHeight: viewHeight,
      rotateSpeed: rotateSpeed,
      bounds: bounds,
    )..edgeScroll = edgeScroll,
    projection: OrthographicProjection(height: viewHeight),
    name: name,
  );

  /// A rig looking straight down, for a map view or a top-down game.
  static CameraRig<RtsCameraController> topDown({
    Vector3? focus,
    double height = 40.0,
    double viewHeight = 30.0,
    bool orthographic = true,
    Aabb3? bounds,
    EdgeScroll? edgeScroll,
    String name = 'topDownCamera',
  }) => CameraRig(
    RtsCameraController.topDown(
      focus: focus,
      height: height,
      viewHeight: viewHeight,
      orthographic: orthographic,
      bounds: bounds,
    )..edgeScroll = edgeScroll,
    projection: orthographic
        ? OrthographicProjection(height: viewHeight)
        : null,
    name: name,
  );

  /// A rig riding a [CameraPath], for a scripted move or an attract-mode
  /// flythrough.
  static CameraRig<DollyCameraController> dolly({
    required CameraPath path,
    Node? lookTarget,
    Vector3? lookPoint,
    double speed = 4.0,
    double? duration,
    bool loop = false,
    String name = 'dollyCamera',
  }) => CameraRig(
    DollyCameraController(
      path: path,
      lookTarget: lookTarget,
      lookPoint: lookPoint,
      speed: speed,
      duration: duration,
      loop: loop,
    ),
    name: name,
  );
}
