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
        KeyControl,
        MouseControl;
export 'src/core/input_system.dart'
    show
        InputClock,
        InputDevice,
        InputSink,
        InputSource,
        InputSystem,
        StopwatchInputClock;
export 'src/core/player_input.dart'
    show ButtonState, ContextEntry, ContextStack, InputWindow, PlayerInput;
export 'src/core/processors.dart'
    show
        Deadzone,
        DeadzoneShape,
        Invert,
        PerSecond,
        Processor,
        ResponseCurve,
        Scale;
