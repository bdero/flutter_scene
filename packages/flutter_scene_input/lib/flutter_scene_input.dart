/// Rebindable input actions for Flutter Scene games.
///
/// Games read typed actions (`move`, `jump`, `look`) instead of keys. An
/// [ActionSet] binds each action to physical controls through named slots,
/// a [PlayerInput] evaluates the sets on its [ContextStack], and read windows
/// give frame and fixed-step code consistent values and edges.
library;

export 'src/core/action_set.dart' show ActionSet;
export 'src/core/actions.dart'
    show
        AxisAction,
        AxisRange,
        ButtonAction,
        DeltaAction,
        DerivedButtonAction,
        HoldAction,
        InputAction,
        MultiTapAction,
        TapAction,
        VectorAction;
export 'src/core/bindings.dart'
    show
        AxisBinding,
        AxisPairBinding,
        Binding,
        ButtonBinding,
        ChordBinding,
        DeltaBinding,
        DpadBinding,
        DpadMode,
        GatedBinding,
        StickBinding;
export 'src/core/controls.dart'
    show
        Control,
        ControlKind,
        DeviceKind,
        GamepadControl,
        GamepadLayoutStyle,
        KeyControl,
        MouseControl;
export 'src/core/display.dart'
    show BindingDisplay, BindingDisplays, ControlLabel;
export 'src/core/input_system.dart'
    show
        InputClock,
        InputDevice,
        InputSink,
        InputSource,
        InputSystem,
        StopwatchInputClock;
export 'src/core/overrides.dart'
    show BindingLocation, OverrideRecord, PlayerOverrides;
export 'src/core/player_input.dart'
    show ButtonState, ContextEntry, ContextStack, InputWindow, PlayerInput;
export 'src/core/rebind.dart'
    show
        BindingConflict,
        ConflictResolution,
        RebindOperation,
        RebindResult,
        RebindStatus,
        Rebinding;
export 'src/core/processors.dart'
    show
        Deadzone,
        DeadzoneShape,
        Invert,
        PerSecond,
        Processor,
        ResponseCurve,
        Scale,
        SwapAxes;
export 'src/pointer_lock/pointer_lock.dart' show PointerLock;
export 'src/pointer_lock/pointer_lock_backend.dart' show PointerLockLoss;
export 'src/scene/default_actions.dart' show DefaultActions;
export 'src/scene/drivers.dart'
    show
        CharacterInputDriver,
        FlyCameraControllerInput,
        FlyCameraInputDriver,
        FollowCameraControllerInput,
        FollowCameraInputDriver,
        InputDriver,
        OrbitCameraControllerInput,
        OrbitCameraInputDriver,
        ThirdPersonControllerInput;
export 'src/scene/input_host.dart'
    show InputHost, InputRoot, NodeInput, PlayerBinding, SceneInput;
export 'src/sources/flutter_input.dart' show FlutterInputSources;
export 'src/sources/gamepad_source.dart'
    show GamepadBackend, GamepadSource, GamepadsPackageBackend, JoinHelper;
export 'src/sources/keyboard_source.dart'
    show KeyboardSource, PhysicalKeyControl;
export 'src/sources/mouse_source.dart' show MouseSource;
export 'src/widgets/input_debug_overlay.dart' show InputDebugOverlay;
export 'src/widgets/input_listener.dart'
    show InputListener, InputScope, PointerLockPolicy;
