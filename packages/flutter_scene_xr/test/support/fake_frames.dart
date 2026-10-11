import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:vector_math/vector_math.dart';

/// A stereo frame as a headset would state it: a viewer at [head] facing
/// [yaw] radians left of `-Z`, two eyes [ipd] apart along the viewer's
/// local `x`, side by side in one target.
XrFrame stereoFrame({
  required Vector3 head,
  double yaw = 0.0,
  double ipd = 0.064,
  ExternalRenderTarget? target,
  Duration time = Duration.zero,
  List<XrInputSourceState> inputSources = const [],
}) {
  final orientation = Quaternion.axisAngle(Vector3(0, 1, 0), yaw);
  final viewer = XrPose(position: head.clone(), orientation: orientation);
  XrView eye(XrEye which, double offset, double tanIn, double tanOut) {
    final pose = XrPose(
      position: head + viewer.rotateDirection(Vector3(offset, 0, 0)),
      orientation: orientation.clone(),
    );
    final left = which == XrEye.left;
    return XrView(
      eye: which,
      pose: pose,
      projection: OffAxisProjection(
        tanLeft: left ? -tanOut : -tanIn,
        tanRight: left ? tanIn : tanOut,
        tanDown: -math.tan(0.8),
        tanUp: math.tan(0.75),
        near: 0.1,
        far: 500,
      ),
      viewport: left
          ? const Rect.fromLTWH(0, 0, 0.5, 1)
          : const Rect.fromLTWH(0.5, 0, 0.5, 1),
    );
  }

  return XrFrame(
    predictedDisplayTime: time,
    views: [
      eye(XrEye.left, -ipd / 2, math.tan(0.7), math.tan(0.9)),
      eye(XrEye.right, ipd / 2, math.tan(0.7), math.tan(0.9)),
    ],
    referenceSpaceType: XrReferenceSpaceType.localFloor,
    viewerPose: viewer,
    target: target,
    inputSources: inputSources,
  );
}

/// An `xr-standard` controller for [handedness] with the trigger at
/// [trigger], the squeeze pressed when [squeeze], and the thumbstick at
/// ([stickX], [stickY]) in the runtime's `+Y` down convention.
XrInputSourceState controllerState({
  required int id,
  required XrHandedness handedness,
  double trigger = 0.0,
  bool squeeze = false,
  bool thumbstickPress = false,
  bool primary = false,
  bool secondary = false,
  double stickX = 0.0,
  double stickY = 0.0,
  XrPose? targetRay,
  bool select = false,
}) {
  final pad =
      XrGamepadState(buttonCount: 6, axisCount: 4, mapping: 'xr-standard')
        ..buttonValues[0] = trigger
        ..buttonPressed[0] = trigger > 0.5
        ..buttonValues[1] = squeeze ? 1.0 : 0.0
        ..buttonPressed[1] = squeeze
        ..buttonValues[3] = thumbstickPress ? 1.0 : 0.0
        ..buttonPressed[3] = thumbstickPress
        ..buttonValues[4] = primary ? 1.0 : 0.0
        ..buttonPressed[4] = primary
        ..buttonValues[5] = secondary ? 1.0 : 0.0
        ..buttonPressed[5] = secondary
        ..axes[2] = stickX
        ..axes[3] = stickY;
  return XrInputSourceState(
      id: id,
      handedness: handedness,
      targetRayMode: XrTargetRayMode.trackedPointer,
      profiles: const ['oculus-touch-v3', 'generic-trigger-squeeze-thumbstick'],
    )
    ..gamepad = pad
    ..targetRayPose = targetRay
    ..gripPose = targetRay
    ..selectPressed = select;
}
