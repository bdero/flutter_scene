/// The emulated WebXR device behind the `webxr_emulated_*` smoke scenes, and
/// raw framebuffers on the web backend's context. Web only; the stub throws.
library;

export 'emulated_xr_stub.dart'
    if (dart.library.js_interop) 'emulated_xr_web.dart';
