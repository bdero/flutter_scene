# flutter_scene_xr

XR sessions for Flutter Scene. One scene graph renders on a flat screen and inside a headset; this package adds the session, the rig and the input bridge, and the renderer stays unaware of any runtime.

An `XrRuntime` starts an `XrSession`, which delivers an `XrFrame` of `XrView`s per display frame. An `XrRig` turns those into camera nodes and `RenderView`s, an `XrSceneLoop` renders a `Scene` through the rig into the frame's target for every frame, and an `XrInputSource` publishes the session's controllers and hands into `flutter_scene_input` so games bind them like any gamepad. Hit testing, anchors, planes, depth and light estimation sit on the session as features the runtime may grant.

Today the only runtime is WebXR, reached on the web through `dart:js_interop` with no native code. On every other platform the package compiles and `XrRuntime.instance.isSupported` is false; native OpenXR and handheld AR runtimes implement the same contract later.

```dart
final scene = Scene();
final rig = XrRig();
scene.add(rig.origin);

final session = await XrRuntime.instance.requestSession(
  const XrSessionRequest(mode: XrSessionMode.immersiveVr),
);
final loop = XrSceneLoop(
  scene: scene,
  rig: rig,
  session: session,
  input: XrInputSource(scene: scene, rig: rig),
)..start();
await session.ended;
```

## Running the example

The `XR` page of the example app (`examples/flutter_app`) shows a small lit scene with an in-world widget panel and offers Enter VR and Enter AR when the browser supports them.

- Desktop Chrome with the WebXR API Emulator extension: `flutter run -d chrome` from `examples/flutter_app`, open the XR example, pick a headset in the emulator's DevTools tab, and press Enter VR.
- A headset browser (Quest Browser, Wolvic): serve a release web build over HTTPS and open it on the device.
- Chrome on Android with ARCore: the same build offers Enter AR; the Flutter UI stays usable over the camera through the DOM overlay.

Immersive sessions need a user gesture to start and a secure context, so a `flutter run` dev server works on `localhost` and anything else needs HTTPS.
