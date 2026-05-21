// Internal flutter_gpu shim. Selects a backend by Dart library: native
// re-exports package:flutter_gpu verbatim (zero cost); web is a WebGL2
// implementation; the analyzer fallback is a throwing stub. flutter_scene
// imports this internally; the curated public surface lives in
// `package:flutter_scene/gpu.dart`.
export 'stub/_gpu.dart'
    if (dart.library.io) 'impeller/_gpu.dart'
    if (dart.library.js_interop) 'web/_gpu.dart';

// Platform-independent helpers.
export 'shared/glsl_transpile.dart';
