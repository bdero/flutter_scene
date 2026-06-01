// Marshalling layer over a WebAssembly instance of the Rapier shim.
//
// The shim exposes the same C ABI whether it is loaded as a native
// dynamic library (via dart:ffi) or as a WebAssembly module. On the
// WebAssembly side there are no pointers in the dart:ffi sense: a
// "pointer" is a byte offset into the module's linear memory, and
// structs are read and written by hand at those offsets using the same
// field layouts the native bindings describe.
//
// This file holds the typed reads and writes, which are plain Dart and
// run anywhere. A concrete subclass supplies the live memory view and
// the allocator exported by the module (fsr_alloc / fsr_free); see
// wasm_runtime_web.dart for the dart:js_interop implementation.

import 'dart:typed_data';

/// Typed access to a WebAssembly instance's linear memory plus the
/// module's exported allocator, used to marshal data across the C ABI.
abstract class WasmRuntime {
  /// A view over the module's current linear memory.
  ///
  /// Read this getter on every access rather than caching it: when the
  /// module grows its memory the backing buffer is replaced, which
  /// detaches any view taken beforehand.
  ByteData get memory;

  /// Allocates [byteCount] bytes in the module's memory and returns the
  /// pointer to them (a byte offset into [memory]). Returns 0 for a
  /// zero-byte request.
  int alloc(int byteCount);

  /// Frees a pointer previously returned by [alloc]. [byteCount] must
  /// match the value passed to the allocation.
  void free(int pointer, int byteCount);

  /// Reads a 32-bit float at [pointer].
  double readF32(int pointer) => memory.getFloat32(pointer, Endian.little);

  /// Writes a 32-bit float at [pointer].
  void writeF32(int pointer, double value) =>
      memory.setFloat32(pointer, value, Endian.little);

  /// Reads a signed 32-bit integer at [pointer].
  int readI32(int pointer) => memory.getInt32(pointer, Endian.little);

  /// Writes a signed 32-bit integer at [pointer].
  void writeI32(int pointer, int value) =>
      memory.setInt32(pointer, value, Endian.little);

  /// Reads an unsigned 32-bit integer at [pointer].
  int readU32(int pointer) => memory.getUint32(pointer, Endian.little);

  /// Writes an unsigned 32-bit integer at [pointer].
  void writeU32(int pointer, int value) =>
      memory.setUint32(pointer, value, Endian.little);

  /// Reads an unsigned byte at [pointer].
  int readU8(int pointer) => memory.getUint8(pointer);

  /// Writes an unsigned byte at [pointer].
  void writeU8(int pointer, int value) => memory.setUint8(pointer, value);

  /// Reads an unsigned 64-bit value (e.g. a packed Rapier handle) at
  /// [pointer] as two 32-bit halves, so it works on the web where
  /// [ByteData] has no 64-bit integer accessors.
  BigInt readU64(int pointer) {
    final low = BigInt.from(memory.getUint32(pointer, Endian.little));
    final high = BigInt.from(memory.getUint32(pointer + 4, Endian.little));
    return (high << 32) | low;
  }

  /// Writes an unsigned 64-bit value at [pointer] as two 32-bit halves.
  void writeU64(int pointer, BigInt value) {
    final mask = BigInt.from(0xFFFFFFFF);
    memory.setUint32(pointer, (value & mask).toInt(), Endian.little);
    memory.setUint32(
      pointer + 4,
      ((value >> 32) & mask).toInt(),
      Endian.little,
    );
  }

  /// Reads [count] consecutive 32-bit floats starting at [pointer].
  Float32List readF32List(int pointer, int count) {
    final view = memory;
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = view.getFloat32(pointer + i * 4, Endian.little);
    }
    return out;
  }

  /// Writes [values] as consecutive 32-bit floats starting at [pointer].
  void writeF32List(int pointer, List<double> values) {
    final view = memory;
    for (var i = 0; i < values.length; i++) {
      view.setFloat32(pointer + i * 4, values[i], Endian.little);
    }
  }
}
