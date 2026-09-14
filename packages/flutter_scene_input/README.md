# flutter_scene_input

Rebindable input actions for Flutter Scene games: keyboard, mouse, gamepads, and pointer lock, with contexts, rebinding, and scene drivers.

Games read typed actions instead of keys. An `ActionSet` binds each action to physical controls through named slots, a context stack decides which sets are live, and read windows give frame and fixed-step code consistent values and edges.

```dart
const move = VectorAction('move');
const jump = ButtonAction('jump');

final gameplay = ActionSet('gameplay', {
  move: {
    'keyboard': DpadBinding(
      up: PhysicalKeyboardKey.keyW.control,
      down: PhysicalKeyboardKey.keyS.control,
      left: PhysicalKeyboardKey.keyA.control,
      right: PhysicalKeyboardKey.keyD.control,
    ),
    'gamepad': const StickBinding(
      GamepadControl.leftStick,
      processors: [Deadzone(0.15)],
    ),
  },
  jump: {
    'keyboard': ButtonBinding(PhysicalKeyboardKey.space.control),
    'gamepad': const ButtonBinding(GamepadControl.south),
  },
});

final player = InputSystem.instance.defaultPlayer..contexts.push(gameplay);
scene.attachInput();

// In a component's update:
if (player.button(jump).justPressed) character.jump();
character.setMoveInput(player.vector(move));
```

- Wrap the game view in `InputListener` for mouse input, and use `PointerLock.instance` for mouse look.
- `DefaultActions` has ready-made character, fly camera, and orbit camera sets, and the drivers feed the bundled controllers.
- `player.overrides` and `listenForBinding` build a controls screen; profiles persist as versioned JSON.

Sandboxed macOS apps need the `com.apple.security.device.usb` entitlement for the HID gamepad fallback.
