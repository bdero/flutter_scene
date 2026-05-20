# flutter_gpu_shim_smoke

Smoke test that answers one question: can a WebGL2-rendered offscreen
canvas be displayed inside a Flutter widget on web, on both CanvasKit
and Skwasm, without a CPU round-trip?

The app renders a clear-to-color using WebGL2 into an `OffscreenCanvas`,
calls `dart:ui_web`'s `createImageFromTextureSource`, and paints the
resulting `ui.Image` with `RawImage`. A toggle flips
`transferOwnership` so both code paths can be exercised.

## Run it

```sh
# CanvasKit
flutter run -d chrome --web-renderer=canvaskit

# Skwasm
flutter run -d chrome --web-renderer=skwasm
```

Only the web platform is committed. To regenerate it (or scaffold other
platforms locally):

```sh
flutter create . --platforms=web
```
