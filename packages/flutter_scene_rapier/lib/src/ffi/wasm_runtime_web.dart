// dart:js_interop implementation of [WasmRuntime]: instantiates the
// Rapier shim's WebAssembly module and binds its exported memory and
// allocator. Only compiled on the web; the per-function bindings for the
// rest of the C ABI are layered on top of the instance separately.

import 'dart:js_interop';
import 'dart:typed_data';

import 'wasm_runtime.dart';

/// A [WasmRuntime] backed by an instantiated WebAssembly module.
class JsWasmRuntime extends WasmRuntime {
  JsWasmRuntime._(this.exports);

  /// The instance's exports. The per-function C ABI bindings reach the
  /// `fsr_*` functions through this object.
  final WasmExports exports;

  /// Instantiates the Rapier shim module from its [bytes] and returns a
  /// runtime bound to its memory and allocator.
  static Future<JsWasmRuntime> instantiate(Uint8List bytes) async {
    final result = await _instantiate(bytes.toJS).toDart;
    return JsWasmRuntime._(result.instance.exports);
  }

  @override
  ByteData get memory => exports.memory.buffer.toDart.asByteData();

  @override
  int alloc(int byteCount) {
    if (byteCount == 0) return 0;
    return exports.callAlloc(byteCount.toJS).toDartInt;
  }

  @override
  void free(int pointer, int byteCount) {
    if (pointer == 0 || byteCount == 0) return;
    exports.callFree(pointer.toJS, byteCount.toJS);
  }
}

@JS('WebAssembly.instantiate')
external JSPromise<_InstantiatedSource> _instantiate(JSUint8Array bytes);

extension type _InstantiatedSource(JSObject _) implements JSObject {
  external _Instance get instance;
}

extension type _Instance(JSObject _) implements JSObject {
  external WasmExports get exports;
}

/// The module's exported functions and memory. Members map to the C ABI
/// export names; the rest of the `fsr_*` surface is declared on this
/// type by the bindings that drive [JsWasmRuntime].
extension type WasmExports(JSObject _) implements JSObject {
  external WasmMemory get memory;

  @JS('fsr_alloc')
  external JSNumber callAlloc(JSNumber size);

  @JS('fsr_free')
  external void callFree(JSNumber pointer, JSNumber size);
}

extension type WasmMemory(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
}
