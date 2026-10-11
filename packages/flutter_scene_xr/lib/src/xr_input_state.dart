import 'dart:typed_data';

import 'package:flutter_scene_xr/src/xr_pose.dart';

/// Which hand an input source belongs to.
/// {@category Input}
enum XrHandedness {
  /// No hand, a gaze or screen tap.
  none,

  /// The left hand.
  left,

  /// The right hand.
  right,
}

/// How an input source aims.
/// {@category Input}
enum XrTargetRayMode {
  /// The ray follows the viewer's gaze.
  gaze,

  /// The ray comes from a tracked controller or hand.
  trackedPointer,

  /// The ray comes from a touch on a handheld screen.
  screen,

  /// The ray exists only while a pinch or tap is in progress.
  transientPointer,
}

/// The joints of a tracked hand, in the order [XrHand.jointPoses] lists
/// them.
/// {@category Input}
enum XrHandJoint {
  wrist('wrist'),
  thumbMetacarpal('thumb-metacarpal'),
  thumbPhalanxProximal('thumb-phalanx-proximal'),
  thumbPhalanxDistal('thumb-phalanx-distal'),
  thumbTip('thumb-tip'),
  indexFingerMetacarpal('index-finger-metacarpal'),
  indexFingerPhalanxProximal('index-finger-phalanx-proximal'),
  indexFingerPhalanxIntermediate('index-finger-phalanx-intermediate'),
  indexFingerPhalanxDistal('index-finger-phalanx-distal'),
  indexFingerTip('index-finger-tip'),
  middleFingerMetacarpal('middle-finger-metacarpal'),
  middleFingerPhalanxProximal('middle-finger-phalanx-proximal'),
  middleFingerPhalanxIntermediate('middle-finger-phalanx-intermediate'),
  middleFingerPhalanxDistal('middle-finger-phalanx-distal'),
  middleFingerTip('middle-finger-tip'),
  ringFingerMetacarpal('ring-finger-metacarpal'),
  ringFingerPhalanxProximal('ring-finger-phalanx-proximal'),
  ringFingerPhalanxIntermediate('ring-finger-phalanx-intermediate'),
  ringFingerPhalanxDistal('ring-finger-phalanx-distal'),
  ringFingerTip('ring-finger-tip'),
  pinkyFingerMetacarpal('pinky-finger-metacarpal'),
  pinkyFingerPhalanxProximal('pinky-finger-phalanx-proximal'),
  pinkyFingerPhalanxIntermediate('pinky-finger-phalanx-intermediate'),
  pinkyFingerPhalanxDistal('pinky-finger-phalanx-distal'),
  pinkyFingerTip('pinky-finger-tip');

  const XrHandJoint(this.webName);

  /// The joint's name in the WebXR Hand Input module.
  final String webName;
}

/// The joints of one tracked hand.
/// {@category Input}
class XrHand {
  /// A hand with every joint untracked.
  XrHand()
    : jointPoses = List<XrPose>.generate(
        XrHandJoint.values.length,
        (_) => XrPose(),
      ),
      jointTracked = List<bool>.filled(XrHandJoint.values.length, false),
      jointRadii = Float32List(XrHandJoint.values.length);

  /// One pose per [XrHandJoint], in enum order. Only meaningful where
  /// [jointTracked] is true.
  final List<XrPose> jointPoses;

  /// Whether each joint was tracked this frame.
  final List<bool> jointTracked;

  /// Each joint's radius in meters, for drawing a capsule.
  final Float32List jointRadii;

  /// The pose of [joint], or null when it is not tracked.
  XrPose? poseOf(XrHandJoint joint) =>
      jointTracked[joint.index] ? jointPoses[joint.index] : null;

  /// Whether any joint is tracked.
  bool get isTracked => jointTracked.any((tracked) => tracked);
}

/// A snapshot of an input source's buttons and axes.
///
/// Button and axis order follow the runtime's own mapping; on WebXR that is
/// the `xr-standard` layout (trigger, squeeze, touchpad, thumbstick, then the
/// face buttons; touchpad axes then thumbstick axes).
/// {@category Input}
class XrGamepadState {
  /// An empty gamepad with [buttonCount] buttons and [axisCount] axes.
  XrGamepadState({int buttonCount = 0, int axisCount = 0, this.mapping = ''})
    : buttonValues = List<double>.filled(buttonCount, 0.0, growable: true),
      buttonPressed = List<bool>.filled(buttonCount, false, growable: true),
      buttonTouched = List<bool>.filled(buttonCount, false, growable: true),
      axes = List<double>.filled(axisCount, 0.0, growable: true);

  /// The runtime's name for the layout (`xr-standard` on WebXR).
  String mapping;

  /// Each button's analog value, `0..1`.
  final List<double> buttonValues;

  /// Whether each button is pressed.
  final List<bool> buttonPressed;

  /// Whether each button is touched (capacitive sensing), or pressed.
  final List<bool> buttonTouched;

  /// Each axis, `-1..1`, with `+Y` down as the runtime reports it.
  final List<double> axes;

  /// Resizes the lists to [buttonCount] and [axisCount], keeping values.
  void resize({required int buttonCount, required int axisCount}) {
    while (buttonValues.length < buttonCount) {
      buttonValues.add(0.0);
      buttonPressed.add(false);
      buttonTouched.add(false);
    }
    while (buttonValues.length > buttonCount) {
      buttonValues.removeLast();
      buttonPressed.removeLast();
      buttonTouched.removeLast();
    }
    while (axes.length < axisCount) {
      axes.add(0.0);
    }
    while (axes.length > axisCount) {
      axes.removeLast();
    }
  }
}

/// One tracked input source (a controller, a hand, a gaze, a screen touch)
/// as of the current frame.
///
/// The session keeps one state object per source for as long as it is
/// connected and refills it each frame.
/// {@category Input}
class XrInputSourceState {
  /// A source identified by [id] for the life of the session.
  XrInputSourceState({
    required this.id,
    required this.handedness,
    required this.targetRayMode,
    this.profiles = const [],
  });

  /// A small integer unique among this session's sources.
  final int id;

  /// Which hand holds it.
  final XrHandedness handedness;

  /// How it aims.
  final XrTargetRayMode targetRayMode;

  /// The runtime's device profile names, most specific first.
  List<String> profiles;

  /// Where the source points from, or null when untracked this frame.
  XrPose? targetRayPose;

  /// Where a held controller sits in the hand, or null for a source with no
  /// grip (a gaze, a bare hand).
  XrPose? gripPose;

  /// Buttons and axes, or null for a source without them.
  XrGamepadState? gamepad;

  /// Hand joints, or null for a source that is not a tracked hand.
  XrHand? hand;

  /// Whether the primary action (trigger, pinch, tap) is held.
  bool selectPressed = false;

  /// Whether the squeeze action (grip button, fist) is held.
  bool squeezePressed = false;

  /// Reusable storage for [targetRayPose] and [gripPose].
  final XrPose targetRayStorage = XrPose();

  /// Reusable storage for [gripPose].
  final XrPose gripStorage = XrPose();
}
