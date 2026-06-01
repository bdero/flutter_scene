// Selects the RapierBindings backend for the target platform: the native
// dynamic library (dart:ffi) everywhere except the web, where the shim
// runs as a WebAssembly module. The conditional picks the web factory
// when dart:js_interop is available, keeping dart:ffi out of web builds.

export 'rapier_bindings_factory_io.dart'
    if (dart.library.js_interop) 'rapier_bindings_factory_web.dart';
