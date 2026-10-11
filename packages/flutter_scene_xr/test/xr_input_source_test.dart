import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/fake_frames.dart';

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

  Map<Control, double> levelsOf(String deviceName) => {
    for (final (device, control, value) in published)
      if (device.name == deviceName) control: value,
  };
}

void main() {
  group('XrInputSource.controlsFor', () {
    test('maps an xr-standard right controller', () {
      final state = controllerState(
        id: 1,
        handedness: XrHandedness.right,
        trigger: 0.8,
        squeeze: true,
        thumbstickPress: true,
        primary: true,
        stickX: 0.5,
        stickY: -0.25,
      );
      final controls = Map.fromEntries(
        XrInputSource.controlsFor(state).map((e) => MapEntry(e.$1, e.$2)),
      );
      expect(controls[GamepadControl.rightTrigger], 0.8);
      expect(controls[GamepadControl.rightShoulder], 1.0);
      expect(controls[GamepadControl.rightStickPress], 1.0);
      expect(controls[GamepadControl.south], 1.0);
      expect(controls[GamepadControl.east], 0.0);
      expect(controls[GamepadControl.rightStickX], 0.5);
      // +Y up for controls, +Y down from the runtime.
      expect(controls[GamepadControl.rightStickY], 0.25);
      expect(controls.containsKey(GamepadControl.leftTrigger), isFalse);
    });

    test('maps an xr-standard left controller to the left-hand controls', () {
      final state = controllerState(
        id: 2,
        handedness: XrHandedness.left,
        trigger: 1.0,
        secondary: true,
        stickX: -1.0,
      );
      final controls = Map.fromEntries(
        XrInputSource.controlsFor(state).map((e) => MapEntry(e.$1, e.$2)),
      );
      expect(controls[GamepadControl.leftTrigger], 1.0);
      expect(controls[GamepadControl.north], 1.0);
      expect(controls[GamepadControl.west], 0.0);
      expect(controls[GamepadControl.leftStickX], -1.0);
    });

    test('a source without a gamepad publishes select as the trigger', () {
      final state = XrInputSourceState(
        id: 3,
        handedness: XrHandedness.none,
        targetRayMode: XrTargetRayMode.gaze,
      )..selectPressed = true;
      final controls = XrInputSource.controlsFor(state).toList();
      expect(controls, contains((GamepadControl.rightTrigger, 1.0)));
      expect(controls, contains((GamepadControl.rightShoulder, 0.0)));
    });
  });

  group('XrInputSource.applyFrame', () {
    test('connects a device per source, publishes, and disconnects', () {
      final sink = _RecordingSink();
      final source = XrInputSource()..attach(sink);
      final left = controllerState(
        id: 1,
        handedness: XrHandedness.left,
        trigger: 0.3,
      );
      final right = controllerState(
        id: 2,
        handedness: XrHandedness.right,
        squeeze: true,
      );
      source.applyFrame(
        stereoFrame(head: Vector3(0, 1.6, 0), inputSources: [left, right]),
      );
      final leftLevels = sink.levelsOf('XR left controller');
      final rightLevels = sink.levelsOf('XR right controller');
      expect(leftLevels[GamepadControl.leftTrigger], 0.3);
      expect(rightLevels[GamepadControl.rightShoulder], 1.0);
      final devices = sink.published.map((e) => e.$1).toSet();
      expect(devices, hasLength(2));
      expect(devices.every((d) => d.kind == DeviceKind.gamepad), isTrue);

      // Unchanged values are not republished; changed ones are.
      sink.published.clear();
      left.gamepad!.buttonValues[0] = 0.9;
      source.applyFrame(
        stereoFrame(head: Vector3(0, 1.6, 0), inputSources: [left, right]),
      );
      expect(sink.published, hasLength(1));
      expect(sink.published.single.$2, GamepadControl.leftTrigger);
      expect(sink.published.single.$3, 0.9);

      // A source that leaves the frame disconnects its device.
      source.applyFrame(
        stereoFrame(head: Vector3(0, 1.6, 0), inputSources: [left]),
      );
      expect(sink.disconnected, hasLength(1));
      expect(sink.disconnected.single.name, 'XR right controller');

      source.detach();
      expect(sink.disconnected, hasLength(2));
    });

    test('a returning source keeps its device handle', () {
      final sink = _RecordingSink();
      final source = XrInputSource()..attach(sink);
      final right = controllerState(id: 1, handedness: XrHandedness.right);
      source.applyFrame(
        stereoFrame(head: Vector3.zero(), inputSources: [right]),
      );
      final handle = sink.published.first.$1.handle;
      source.applyFrame(stereoFrame(head: Vector3.zero()));
      sink.published.clear();
      source.applyFrame(
        stereoFrame(head: Vector3.zero(), inputSources: [right]),
      );
      expect(sink.published.first.$1.handle, handle);
    });
  });
}
