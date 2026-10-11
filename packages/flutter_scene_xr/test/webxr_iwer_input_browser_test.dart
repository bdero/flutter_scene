@TestOn('browser')
library;

import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/iwer.dart';

final class _RecordingSink implements InputSink {
  final InputSystem _system = InputSystem();
  final List<(InputDevice, Control, double)> published = [];
  final List<InputDevice> disconnected = [];

  @override
  InputDevice connectDevice(
    DeviceKind kind, {
    required String name,
    String? identity,
    int? vendorId,
    int? productId,
  }) => _system.connectDevice(
    kind,
    name: name,
    identity: identity,
    vendorId: vendorId,
    productId: productId,
  );

  @override
  void disconnectDevice(InputDevice device) => disconnected.add(device);

  @override
  void updateDevice(
    InputDevice device, {
    String? name,
    int? vendorId,
    int? productId,
  }) {}

  @override
  void publish(InputDevice device, Control control, double value) =>
      published.add((device, control, value));

  @override
  void publishDelta(
    InputDevice device,
    Control control,
    double dx,
    double dy,
  ) {}

  /// The latest value published per control on the device named
  /// [deviceName].
  Map<Control, double> levelsOf(String deviceName) => {
    for (final (device, control, value) in published)
      if (device.name == deviceName) control: value,
  };

  Set<String> get deviceNames => {
    for (final (device, _, _) in published) device.name,
  };
}

const _vrLocalFloor = XrSessionRequest(
  mode: XrSessionMode.immersiveVr,
  referenceSpaces: [XrReferenceSpaceType.localFloor],
);

double _maxJointShift(List<Vector3> before, List<Vector3> after) {
  var max = 0.0;
  for (var i = 0; i < before.length && i < after.length; i++) {
    final shift = (after[i] - before[i]).length;
    if (shift > max) max = shift;
  }
  return max;
}

void main() {
  late IwerDevice device;

  setUpAll(() {
    device = installIwer();
  });

  tearDownAll(uninstallIwer);

  setUp(() {
    device.primaryInputMode = 'controller';
    device.updateVisibilityState('visible');
    for (final controller in [
      device.controllers.left,
      device.controllers.right,
    ]) {
      controller.updateButtonValue('trigger', 0);
      controller.updateButtonValue('squeeze', 0);
      controller.updateAxes('thumbstick', 0, 0);
    }
    device.hands.left.poseId = 'default';
    device.hands.right.poseId = 'default';
  });

  test('tracks two controllers and publishes their buttons and axes', () async {
    final session = await startSession(_vrLocalFloor);
    final sink = _RecordingSink();
    final input = XrInputSource()..attach(sink);
    final subscription = session.frames.listen(input.applyFrame);
    addTearDown(subscription.cancel);

    final frame = await frameWhere(
      session,
      (frame) => frame.inputSources.length == 2,
    );
    expect(frame.inputSources, hasLength(2));
    final left = frame.source(XrHandedness.left);
    final right = frame.source(XrHandedness.right);
    expect(left, isNotNull);
    expect(right, isNotNull);
    for (final source in [left!, right!]) {
      expect(source.targetRayMode, XrTargetRayMode.trackedPointer);
      expect(source.profiles, contains('meta-quest-touch-plus'));
      expect(source.hasGamepad, isTrue);
      expect(source.mapping, 'xr-standard');
      expect(source.targetRayPosition, isNotNull);
      expect(source.gripPosition, isNotNull);
      // trigger, squeeze, touchpad, thumbstick, two face buttons, thumbrest.
      expect(source.buttonValues, hasLength(7));
      expect(source.axes, hasLength(4));
      expect(source.selectPressed, isFalse);
      expect(source.hasHand, isFalse);
    }
    expect(
      sink.deviceNames,
      containsAll(['XR left controller', 'XR right controller']),
    );
    expect(
      sink.levelsOf('XR right controller')[GamepadControl.rightTrigger],
      0.0,
    );
    expect(
      sink.levelsOf('XR left controller')[GamepadControl.leftTrigger],
      0.0,
    );

    // The trigger is analog and fires select.
    device.controllers.right.updateButtonValue('trigger', 1);
    final pressed = await frameWhere(session, (frame) {
      final source = frame.source(XrHandedness.right);
      return source != null &&
          source.buttonValues![0] == 1.0 &&
          source.selectPressed;
    });
    final rightPressed = pressed.source(XrHandedness.right)!;
    expect(rightPressed.buttonValues![0], 1.0);
    expect(rightPressed.buttonPressed![0], isTrue);
    expect(rightPressed.selectPressed, isTrue);
    expect(pressed.source(XrHandedness.left)!.selectPressed, isFalse);
    expect(
      sink.levelsOf('XR right controller')[GamepadControl.rightTrigger],
      1.0,
    );
    expect(
      sink.levelsOf('XR left controller')[GamepadControl.leftTrigger],
      0.0,
    );

    device.controllers.right.updateButtonValue('trigger', 0);
    final released = await frameWhere(session, (frame) {
      final source = frame.source(XrHandedness.right);
      return source != null &&
          source.buttonValues![0] == 0.0 &&
          !source.selectPressed;
    });
    final rightReleased = released.source(XrHandedness.right)!;
    expect(rightReleased.buttonPressed![0], isFalse);
    expect(rightReleased.selectPressed, isFalse);
    expect(
      sink.levelsOf('XR right controller')[GamepadControl.rightTrigger],
      0.0,
    );

    // The thumbstick rides axes 2 and 3; controls flip Y to +up.
    device.controllers.right.updateAxes('thumbstick', 0.5, -0.25);
    final steered = await frameWhere(
      session,
      (frame) => frame.source(XrHandedness.right)?.axes![2] != 0.0,
    );
    final rightSteered = steered.source(XrHandedness.right)!;
    expect(rightSteered.axes![2], closeTo(0.5, 1e-6));
    expect(rightSteered.axes![3], closeTo(-0.25, 1e-6));
    expect(rightSteered.axes![0], 0.0);
    expect(rightSteered.axes![1], 0.0);
    final levels = sink.levelsOf('XR right controller');
    expect(levels[GamepadControl.rightStickX], closeTo(0.5, 1e-6));
    expect(levels[GamepadControl.rightStickY], closeTo(0.25, 1e-6));

    // Squeeze fires the squeeze events and the shoulder control.
    device.controllers.left.updateButtonValue('squeeze', 1);
    final squeezed = await frameWhere(session, (frame) {
      final source = frame.source(XrHandedness.left);
      return source != null &&
          source.buttonValues![1] == 1.0 &&
          source.squeezePressed;
    });
    final leftSqueezed = squeezed.source(XrHandedness.left)!;
    expect(leftSqueezed.buttonPressed![1], isTrue);
    expect(leftSqueezed.squeezePressed, isTrue);
    expect(
      sink.levelsOf('XR left controller')[GamepadControl.leftShoulder],
      1.0,
    );
    expect(sink.disconnected, isEmpty);
  });

  // IWER fills the xr-standard touchpad slots this controller lacks with
  // null rather than zero; a frame must still come through.
  test('reads null touchpad axis slots as zero', () async {
    final session = await startSession(_vrLocalFloor);
    final frame = await frameWhere(
      session,
      (frame) => frame.inputSources.length == 2,
    );
    expect(frame.inputSources, hasLength(2));
    for (final source in frame.inputSources) {
      expect(source.axes, hasLength(4));
      expect(source.axes![0], 0.0);
      expect(source.axes![1], 0.0);
      expect(source.buttonValues, hasLength(7));
    }
  });

  test('tracks hands with 25 joints that follow the hand pose', () async {
    final session = await startSession(
      const XrSessionRequest(
        mode: XrSessionMode.immersiveVr,
        optionalFeatures: [XrFeatures.handTracking],
        referenceSpaces: [XrReferenceSpaceType.localFloor],
      ),
    );
    expect(session.features, contains(XrFeatures.handTracking));
    final sink = _RecordingSink();
    final input = XrInputSource()..attach(sink);
    final subscription = session.frames.listen(input.applyFrame);
    addTearDown(subscription.cancel);

    device.primaryInputMode = 'hand';
    final frame = await frameWhere(
      session,
      (frame) =>
          frame.inputSources.length == 2 &&
          frame.inputSources.every(
            (source) =>
                source.hasHand &&
                source.jointTracked!.any((tracked) => tracked),
          ),
    );
    expect(frame.inputSources, hasLength(2));
    final right = frame.source(XrHandedness.right);
    expect(right, isNotNull);
    expect(right!.hasHand, isTrue);
    expect(right.jointPositions, hasLength(XrHandJoint.values.length));
    expect(right.jointTracked!.where((tracked) => tracked), isNotEmpty);
    expect(right.targetRayMode, XrTargetRayMode.trackedPointer);
    expect(sink.deviceNames, containsAll(['XR left hand', 'XR right hand']));

    final before = right.jointPositions!;
    device.hands.right.poseId = 'pinch';
    final pinched = await frameWhere(session, (frame) {
      final source = frame.source(XrHandedness.right);
      return source != null &&
          source.hasHand &&
          _maxJointShift(before, source.jointPositions!) > 1e-4;
    });
    final after = pinched.source(XrHandedness.right)!.jointPositions!;
    expect(_maxJointShift(before, after), greaterThan(1e-4));
    expect(device.hands.right.poseId, 'pinch');
  });
}
