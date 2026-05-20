## 0.0.1

Initial scaffold. Conditional-export entry point plus a minimal web `Surface`
that wraps an `OffscreenCanvas` + WebGL2 context and snapshots to a
`ui.Image` via `dart:ui_web`'s `createImageFromTextureSource`. Exists only
to validate the WebGL2 -> Flutter widget bridge on CanvasKit and Skwasm
before designing the rest of the API.
