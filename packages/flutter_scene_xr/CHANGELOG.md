## 0.1.0-dev

* The session contract: `XrRuntime`, `XrSession`, `XrSessionRequest`, `XrFrame`, `XrView`, `XrPose`, with session modes, reference spaces and blend modes.
* `XrRig`, nodes for the head, eyes, controllers, target rays and hand joints, producing the `RenderView`s for `Scene.renderViewsToTargets`.
* `XrSceneLoop`, which ticks and renders a `Scene` through a rig for every session frame.
* `XrInputSource`, which publishes controllers and hands as gamepad devices into `flutter_scene_input` and points a `ScenePointer` along each target ray.
* A WebXR runtime behind a `dart.library.js_interop` conditional import, with immersive VR and AR, DOM overlay, hit test, anchors, planes, hands, CPU depth and light estimation.
