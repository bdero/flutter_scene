// Web backend factory: the shim is a WebAssembly module. The module is
// instantiated once (asynchronously) and shared by every world, so it
// must be loaded before the first world is created. ensureRapierReady
// does the load; createRapierBindings then spins up a world on the
// shared instance synchronously.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/wasm_rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/wasm_runtime_web.dart';

const _wasmAssetKey =
    'packages/flutter_scene_rapier/assets/flutter_scene_rapier_native.wasm';

JsWasmRuntime? _runtime;

/// Loads and instantiates the shim's WebAssembly module once. Safe to
/// call repeatedly; later calls return immediately.
Future<void> ensureRapierReady() async {
  if (_runtime != null) return;
  final data = await rootBundle.load(_wasmAssetKey);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  _runtime = await JsWasmRuntime.instantiate(bytes);
}

/// Creates a world on the shared module instance. Throws if the module
/// has not been loaded yet.
RapierBindings createRapierBindings() {
  final runtime = _runtime;
  if (runtime == null) {
    throw StateError(
      'The Rapier WebAssembly module is not loaded. Await '
      'RapierWorld.ensureInitialized() before constructing a RapierWorld '
      'on the web.',
    );
  }
  return WasmRapierBindings(runtime);
}
