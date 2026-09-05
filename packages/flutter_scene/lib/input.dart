/// Input for flutter_scene: rebindable actions over a pluggable device
/// contract.
///
/// Game code asks for verbs ([InputManager.isPressed], [InputManager.axis],
/// [InputManager.vector2]) instead of reading keys, and an [InputMap] decides
/// which controls produce them. Because a map round-trips through JSON, the
/// same structure serves runtime rebinding and a project-settings file.
///
/// Devices are [InputSource]s. The engine ships [KeyboardInputSource] and
/// [PointerInputSource]; anything else (a gamepad backend, a replay source)
/// implements the contract without a core change, the same shape the audio and
/// physics backends use.
///
/// Wrap a `SceneView` in an [InputScope] to wire Flutter's events in, then
/// call [InputManager.update] once per frame before reading actions. Import
/// this only when a build needs input; the core
/// `package:flutter_scene/scene.dart` does not carry it.
library;

export 'src/input/input_binding.dart'
    show
        AnalogAxisBinding,
        AxisBinding,
        ButtonBinding,
        CompositeVector2Binding,
        InputActionKind,
        InputBinding,
        InputControlReader,
        StickBinding;
export 'src/input/gamepad.dart'
    show GamepadAxis, GamepadButton, GamepadInputSource;
export 'src/input/input_control.dart' show InputControl, InputDevice;
export 'src/input/input_controllers.dart'
    show
        FirstPersonCameraInput,
        FlyCameraInput,
        RtsCameraInput,
        ThirdPersonInput;
export 'src/input/input_manager.dart' show InputManager;
export 'src/input/input_map.dart' show InputAction, InputMap;
export 'src/input/input_scope.dart' show InputScope;
export 'src/input/input_source.dart'
    show InputSink, InputSource, KeyboardInputSource, PointerInputSource;
export 'src/input/pointer_lock.dart' show PointerLock;
export 'src/input/pointer_lock_base.dart' show PointerLockSource;
export 'src/input/web_gamepad_source.dart' show WebGamepadSource;
