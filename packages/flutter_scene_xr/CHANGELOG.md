## 0.1.0-dev

* The session contract: `XrRuntime`, `XrSession`, `XrSessionRequest`, `XrFrame`, `XrView`, `XrPose`, with session modes, reference spaces and blend modes.
* `XrRig`, nodes for the head, eyes, controllers, target rays and hand joints, producing the `RenderView`s for `Scene.renderViewsToTargets`.
* `XrSceneLoop`, which ticks and renders a `Scene` through a rig for every session frame.
* `XrInputSource`, which publishes controllers and hands as gamepad devices into `flutter_scene_input` and points a `ScenePointer` along each target ray.
* A WebXR runtime behind a `dart.library.js_interop` conditional import, with immersive VR and AR, DOM overlay, hit test, anchors, planes, hands, CPU depth and light estimation.
* A layer without a framebuffer (an inline session, an emulated runtime) draws through a canvas the runtime owns: the frame renders into a texture the session allocates and is copied onto the canvas each frame.
* `XrFrame.submit` hands the runtime what the renderer reported for a frame. `XrSceneLoop` calls it for every frame.
* `XrSession.renderScale` resizes the eye images while a session runs, and `XrSessionRequest.renderScale` sets the size it starts at.
* `XrSession.layers` adds quad and cylinder layers the runtime's compositor places itself, each drawn into with `Scene.renderViewsToTargets`. On WebXR they need the `layers` feature.
* `XrSceneLoop.backgroundColor` puts a color behind the scene in every eye.
