## 0.1.0-dev

* Typed actions (`ButtonAction`, `AxisAction`, `VectorAction`, `DeltaAction`) bound to physical controls through named slots in an `ActionSet`.
* Composite and gated bindings (`DpadBinding`, `AxisPairBinding`, `ChordBinding`, `GatedBinding`) with processors (`Deadzone`, `Scale`, `Invert`, `ResponseCurve`, `PerSecond`, `SwapAxes`), tunable sensitivity, inversion, and deadzones.
* A per-player context stack with consumption, opaque entries, priorities, and a text-field guard.
* Frame and fixed-step read windows that see every press exactly once, including taps inside one frame.
* Hold, tap, and multi-tap recognizers, with hold-to-toggle as a setting.
* Keyboard, mouse, and trackpad sources, `InputListener`, and `InputScope`.
* Gamepads through the `gamepads` package with hot-plug, stable device handles, pairing, `JoinHelper`, and a macOS HID fallback for pads the GameController framework misses.
* `PointerLock` for first-person mouse look on macOS, Windows, Linux (X11 and Wayland), and the web.
* Rebinding with `player.overrides`, versioned JSON profiles with renames and migration, `listenForBinding`, conflict detection, and `bindingDisplay` labels that follow keyboard layout and pad style.
* Scene integration: `scene.attachInput`, `node.playerInput`, `PlayerBinding`, drivers for the bundled character and camera controllers, and `DefaultActions`.
* `InputDebugOverlay` and an injection API for tests, bots, and replays.
