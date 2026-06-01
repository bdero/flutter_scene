// Unit tests for the WasmRuntime marshalling layer. These exercise the
// typed reads and writes and the memory-growth contract against a fake
// backend, so they run on the VM with no browser or wasm module. The
// dart:js_interop subclass (JsWasmRuntime) is thin and is exercised by
// running the Rapier backend on the web.

import 'dart:typed_data';

import 'package:flutter_scene_rapier/src/ffi/wasm_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('WasmRuntime typed access', () {
    late _FakeWasmRuntime runtime;
    setUp(() => runtime = _FakeWasmRuntime(1024));

    test('f32 round-trips, including negatives', () {
      final p = runtime.alloc(12);
      runtime.writeF32(p, 1.5);
      runtime.writeF32(p + 4, -2.0);
      runtime.writeF32(p + 8, 3.25);
      expect(runtime.readF32(p), 1.5);
      expect(runtime.readF32(p + 4), -2.0);
      expect(runtime.readF32(p + 8), 3.25);
    });

    test('i32, u32, and u8 round-trip', () {
      final p = runtime.alloc(16);
      runtime.writeI32(p, -123456);
      runtime.writeU32(p + 4, 0xDEADBEEF);
      runtime.writeU8(p + 8, 200);
      expect(runtime.readI32(p), -123456);
      expect(runtime.readU32(p + 4), 0xDEADBEEF);
      expect(runtime.readU8(p + 8), 200);
    });

    test('u64 round-trips a value above 2^32 as two halves', () {
      final p = runtime.alloc(8);
      // A packed handle: generation 7 in the high word, index 42 low.
      final value = (BigInt.from(7) << 32) | BigInt.from(42);
      runtime.writeU64(p, value);
      expect(runtime.readU64(p), value);
      // Little-endian: low word first.
      expect(runtime.readU32(p), 42);
      expect(runtime.readU32(p + 4), 7);
    });

    test('f32 lists round-trip', () {
      final p = runtime.alloc(16);
      runtime.writeF32List(p, const [0.0, 1.0, -1.0, 42.5]);
      expect(runtime.readF32List(p, 4), [0.0, 1.0, -1.0, 42.5]);
    });

    test('alloc hands out distinct, non-zero pointers', () {
      final a = runtime.alloc(12);
      final b = runtime.alloc(12);
      expect(a, isNot(0));
      expect(b, greaterThanOrEqualTo(a + 12));
    });
  });

  test('reads see memory after the backing buffer grows', () {
    final runtime = _FakeWasmRuntime(32);
    final p = runtime.alloc(4);
    runtime.writeF32(p, 9.0);
    // Growing replaces the backing buffer; a cached view would be stale.
    runtime.grow(4096);
    expect(runtime.readF32(p), 9.0);
    // And the freshly grown region is usable.
    runtime.writeF32(2048, -7.5);
    expect(runtime.readF32(2048), -7.5);
  });
}

// A WasmRuntime backed by a plain Dart buffer and a bump allocator, so
// the shared marshalling logic can be tested off the web.
class _FakeWasmRuntime extends WasmRuntime {
  _FakeWasmRuntime(int sizeBytes) : _bytes = Uint8List(sizeBytes);

  Uint8List _bytes;
  int _bump = 16; // leave offset 0 as a null sentinel

  @override
  ByteData get memory => _bytes.buffer.asByteData();

  @override
  int alloc(int byteCount) {
    if (byteCount == 0) return 0;
    final pointer = _bump;
    _bump += (byteCount + 15) & ~15; // 16-byte aligned, matching fsr_alloc
    return pointer;
  }

  @override
  void free(int pointer, int byteCount) {}

  // Simulates WebAssembly.Memory.grow: a new, larger backing buffer that
  // preserves existing contents and detaches the old one.
  void grow(int newSizeBytes) {
    final grown = Uint8List(newSizeBytes)..setAll(0, _bytes);
    _bytes = grown;
  }
}
