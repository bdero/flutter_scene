## 0.1.0-dev.2

* `XrRig.defaultXrToScene` is the identity, since flutter_scene 0.25.0 shares the runtime's right-handed, `-Z` forward convention. Poses, eye cameras, and target rays map straight through.

## 0.1.0-dev.1

* `XrRuntime`, `XrSession`, `XrFrame`, `XrView` and `XrPose`, a session contract any XR runtime can implement.
* `XrRig` turns each frame's views into camera nodes and the `RenderView`s for `Scene.renderViewsToTargets`.
* `XrSceneLoop` ticks and renders a `Scene` through a rig for every session frame, with an optional `backgroundColor`.
* `XrInputSource` publishes controllers and hands into `flutter_scene_input` and points a `ScenePointer` along each target ray.
* A WebXR runtime for immersive VR and AR on the WebGL2 backend, with DOM overlay, hit test, anchors, planes, hands, CPU depth and light estimation.
* `XrSession.layers` adds quad and cylinder layers that the runtime's compositor places.
* `XrSession.renderScale` resizes the eye images while a session runs.
* `XrFrame.submit` reports each rendered frame back to the runtime.
