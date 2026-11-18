// ignore_for_file: implementation_imports

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ByteData _patternedBytes(int length, {int seed = 1}) {
  final list = Uint8List(length);
  var state = seed & 0xFF;
  for (var i = 0; i < length; i++) {
    state = ((state * 73) + i + 19) & 0xFF;
    list[i] = state;
  }
  return ByteData.sublistView(list);
}

Uint8List _readSlice(TransientStagingBuffer block, int offset, int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = block.staging.getUint8(offset + i);
  }
  return out;
}

final class _StagedSlice {
  const _StagedSlice(this.blockIndex, this.offsetInBytes, this.lengthInBytes);
  final int blockIndex;
  final int offsetInBytes;
  final int lengthInBytes;
}

final class _CpuDedupHarness {
  _CpuDedupHarness({this.alignment = 256, this.blockLength = 65536});

  final int alignment;
  final int blockLength;
  final List<TransientStagingBuffer> open = [];
  final UniformDedupTable<_StagedSlice> table =
      UniformDedupTable<_StagedSlice>();
  int stagedBytes = 0;

  _StagedSlice emplace(ByteData bytes) {
    final length = bytes.lengthInBytes;
    var block = open.isEmpty ? null : open.last;
    var offset = 0;
    if (block != null) {
      final plan = TransientArena.planEmplacement(
        cursor: block.cursor,
        alignment: alignment,
        length: length,
        blockLength: block.capacity,
      );
      if (plan.rollOver) {
        block = null;
      } else {
        offset = plan.offset;
      }
    }
    if (block == null) {
      block = TransientStagingBuffer(blockLength);
      open.add(block);
      offset = 0;
    }
    block.stage(offset, bytes);
    block.cursor = offset + length;
    stagedBytes += length;
    return _StagedSlice(open.length - 1, offset, length);
  }

  _StagedSlice emplaceDeduplicated(ByteData bytes) {
    final hit = table.lookup(bytes, open);
    if (hit != null) return hit;
    final slice = emplace(bytes);
    table.record(
      slice.blockIndex,
      slice.offsetInBytes,
      slice.lengthInBytes,
      slice,
    );
    return slice;
  }

  Uint8List read(_StagedSlice slice) => _readSlice(
    open[slice.blockIndex],
    slice.offsetInBytes,
    slice.lengthInBytes,
  );

  void resetEpoch() {
    open.clear();
    table.invalidate();
    stagedBytes = 0;
  }
}

final class _StubBufferView implements gpu.BufferView {
  _StubBufferView(this.offsetInBytes, this.lengthInBytes);

  @override
  final int offsetInBytes;

  @override
  final int lengthInBytes;

  @override
  gpu.DeviceBuffer get buffer => throw UnimplementedError();
}

final class _SpyTransientWriter implements TransientWriter {
  int emplaceCalls = 0;
  int _cursor = 0;

  @override
  gpu.BufferView emplace(ByteData bytes) {
    emplaceCalls++;
    final view = _StubBufferView(_cursor, bytes.lengthInBytes);
    _cursor += 256;
    return view;
  }
}

void main() {
  group('TransientStagingBuffer', () {
    const sizes = <int>[4, 12, 17, 160, 256, 704, 1028];

    test('backs staging ByteData directly with 32-bit word storage', () {
      final block = TransientStagingBuffer(4096);
      expect(block.words.length, 1024);
      expect(block.staging.lengthInBytes, 4096);
      block.words[0] = 0x11223344;
      expect(block.staging.getUint32(0, Endian.host), 0x11223344);
    });

    test(
      'supports non-multiple-of-4 block capacities up to the final byte',
      () {
        for (final cap in const <int>[65, 1025]) {
          final block = TransientStagingBuffer(cap);
          expect(block.capacity, cap);
          expect(block.staging.lengthInBytes, cap);
          expect(block.words.length, (cap + 3) >> 2);

          final src = _patternedBytes(cap, seed: 31);
          block.stage(0, src);
          final expected = Uint8List.fromList(
            src.buffer.asUint8List(src.offsetInBytes, cap),
          );
          expect(_readSlice(block, 0, cap), expected);
          expect(block.staging.getUint8(cap - 1), expected.last);
          expect(block.matches(0, src), isTrue);

          // Also exercise _CpuDedupHarness with a 65-byte block capacity.
          final harness = _CpuDedupHarness(alignment: 16, blockLength: 65);
          final slice1 = harness.emplaceDeduplicated(
            _patternedBytes(65, seed: 9),
          );
          final slice2 = harness.emplaceDeduplicated(
            _patternedBytes(65, seed: 9),
          );
          expect(identical(slice2, slice1), isTrue);
          expect(
            harness.read(slice1).last,
            _patternedBytes(65, seed: 9).getUint8(64),
          );
        }
      },
    );

    test(
      'stages aligned slices accurately without touching neighbor bytes',
      () {
        final block = TransientStagingBuffer(8192);
        for (var i = 0; i < block.capacity; i++) {
          block.staging.setUint8(i, 0xCC);
        }

        var cursor = 0;
        final prior = <(int, int, Uint8List)>[];
        for (var idx = 0; idx < sizes.length; idx++) {
          final size = sizes[idx];
          final offset = (cursor + 255) & ~255;
          final src = _patternedBytes(size, seed: idx + 11);
          block.stage(offset, src);

          for (var pad = cursor; pad < offset; pad++) {
            expect(block.staging.getUint8(pad), 0xCC);
          }
          expect(block.staging.getUint8(offset + size), 0xCC);

          final expected = Uint8List.fromList(
            src.buffer.asUint8List(src.offsetInBytes, size),
          );
          expect(_readSlice(block, offset, size), expected);
          expect(block.matches(offset, src), isTrue);
          prior.add((offset, size, expected));
          cursor = offset + size;
        }

        for (final (offset, size, expected) in prior) {
          expect(_readSlice(block, offset, size), expected);
        }
      },
    );

    test('stages and matches unaligned offsets and ByteData subviews', () {
      final block = TransientStagingBuffer(8192);
      for (var i = 0; i < block.capacity; i++) {
        block.staging.setUint8(i, 0xAA);
      }

      var dstOffset = 2;
      for (final size in sizes) {
        final backing = Uint8List(size + 8)..fillRange(0, size + 8, 0xEE);
        final expected = Uint8List(size);
        for (var i = 0; i < size; i++) {
          final value = ((i * 37) + size + 5) & 0xFF;
          backing[2 + i] = value;
          expected[i] = value;
        }
        final unalignedView = ByteData.sublistView(backing, 2, 2 + size);
        expect(unalignedView.offsetInBytes & 3, 2);

        block.stage(dstOffset, unalignedView);
        expect(block.staging.getUint8(dstOffset - 1), 0xAA);
        expect(block.staging.getUint8(dstOffset + size), 0xAA);
        expect(_readSlice(block, dstOffset, size), expected);
        expect(block.matches(dstOffset, unalignedView), isTrue);
        dstOffset += size + 6; // keeps destination offsets non-4-byte aligned
      }
    });
  });

  group('UniformDedupTable & TransientWriterDeduplication', () {
    test('deduplicates 200 identical 160B and 704B uniform blocks', () {
      for (final blockSize in const <int>[160, 704]) {
        final harness = _CpuDedupHarness(alignment: 256);
        final payload = _patternedBytes(blockSize, seed: blockSize);

        final first = harness.emplaceDeduplicated(payload);
        expect(first.offsetInBytes, 0);
        expect(harness.stagedBytes, blockSize);
        expect(harness.table.hitCount, 0);

        for (var draw = 1; draw < 200; draw++) {
          final copy = ByteData(blockSize);
          for (var b = 0; b < blockSize; b++) {
            copy.setUint8(b, payload.getUint8(b));
          }
          final next = harness.emplaceDeduplicated(copy);
          expect(identical(next, first), isTrue);
        }

        expect(harness.stagedBytes, blockSize);
        expect(harness.table.hitCount, 199);
        expect(harness.table.hitBytes, 199 * blockSize);
      }
    });

    test('matches unaligned ByteData subviews against aligned slices', () {
      final harness = _CpuDedupHarness(alignment: 256);
      final aligned = _patternedBytes(160, seed: 42);
      final padded = Uint8List(166);
      for (var i = 0; i < 160; i++) {
        padded[2 + i] = aligned.getUint8(i);
      }
      final unaligned = ByteData.sublistView(padded, 2, 162);

      final first = harness.emplaceDeduplicated(aligned);
      final second = harness.emplaceDeduplicated(unaligned);
      expect(identical(second, first), isTrue);
      expect(harness.stagedBytes, 160);
      expect(harness.table.hitCount, 1);
    });

    test('stages a fresh slice when any byte changes and across rollovers', () {
      final harness = _CpuDedupHarness(alignment: 256, blockLength: 1024);

      for (final size in const <int>[704, 705]) {
        harness.resetEpoch();
        final base = _patternedBytes(size, seed: 7);
        final baseSlice = harness.emplaceDeduplicated(base);

        final positions = <int>[0, size >> 1, size - 1];
        var expectedStaged = size;
        for (final pos in positions) {
          final mutated = ByteData(size);
          for (var i = 0; i < size; i++) {
            mutated.setUint8(i, base.getUint8(i));
          }
          mutated.setUint8(pos, base.getUint8(pos) ^ 0x01);

          final nextSlice = harness.emplaceDeduplicated(mutated);
          expect(identical(nextSlice, baseSlice), isFalse);
          expectedStaged += size;
          expect(harness.stagedBytes, expectedStaged);

          // Earlier block entries remain reachable after rolling over to new blocks.
          expect(
            identical(harness.emplaceDeduplicated(base), baseSlice),
            isTrue,
          );
        }
        expect(harness.open.length, greaterThan(1));
      }
    });

    test('invalidate clears the epoch in O(1)', () {
      final harness = _CpuDedupHarness(alignment: 256);
      final data = _patternedBytes(704, seed: 99);

      final v1 = harness.emplaceDeduplicated(data);
      expect(identical(harness.emplaceDeduplicated(data), v1), isTrue);
      expect(harness.table.hitCount, 1);

      harness.resetEpoch();
      expect(harness.table.hitCount, 0);
      expect(harness.table.hitBytes, 0);

      final v2 = harness.emplaceDeduplicated(data);
      expect(identical(v2, v1), isFalse);
      expect(harness.stagedBytes, 704);
    });

    test('non-arena TransientWriter implementations fall back to emplace', () {
      final spy = _SpyTransientWriter();
      final TransientWriter writer = spy;
      final bytes = _patternedBytes(64, seed: 3);

      final a = writer.emplaceDeduplicated(bytes);
      final b = writer.emplaceDeduplicated(bytes);
      expect(spy.emplaceCalls, 2);
      expect(a.offsetInBytes, 0);
      expect(b.offsetInBytes, 256);
    });

    test('deduplicates MaterialParameters rawBlock across shared draws', () {
      final harness = _CpuDedupHarness(alignment: 256);
      final params =
          MaterialParameters.withLayout(
              blockName: 'MaterialParams',
              blockSizeBytes: 64,
              parameters: {
                'tint': (type: FmatType.vec4, offset: 0, sourceColor: false),
                'roughness': (
                  type: FmatType.float_,
                  offset: 16,
                  sourceColor: false,
                ),
              },
            )
            ..setVec4('tint', Vector4(0.3, 0.5, 0.7, 1.0))
            ..setFloat('roughness', 0.4);

      final first = harness.emplaceDeduplicated(params.rawBlock);
      for (var i = 0; i < 50; i++) {
        expect(
          identical(harness.emplaceDeduplicated(params.rawBlock), first),
          isTrue,
        );
      }
      expect(harness.stagedBytes, 64);

      params.setFloat('roughness', 0.8);
      final updated = harness.emplaceDeduplicated(params.rawBlock);
      expect(identical(updated, first), isFalse);
      expect(harness.stagedBytes, 128);
    });
  });

  group('TextureTransformCache & Material transform packing', () {
    test('packs once when clean and shares one slice across 206 draws', () {
      final harness = _CpuDedupHarness(alignment: 256);
      final materials = List<PhysicallyBasedMaterial>.generate(
        30,
        (i) => PhysicallyBasedMaterial()
          ..metallicFactor = (i % 5) * 0.25
          ..roughnessFactor = 0.2 + (i % 4) * 0.2,
      );

      _StagedSlice? sharedSlice;
      for (var draw = 0; draw < 206; draw++) {
        final material = materials[draw % materials.length];
        final bytes = packStandardTextureTransforms(material);
        expect(bytes.lengthInBytes, 160);
        final slice = harness.emplaceDeduplicated(bytes);
        sharedSlice ??= slice;
        expect(identical(slice, sharedSlice), isTrue);
      }

      for (final material in materials) {
        expect(standardTextureTransformPackCount(material), 1);
      }
      expect(harness.stagedBytes, 160);
      expect(harness.table.hitCount, 205);

      // Non-transform scalar/factor mutations do not repack TextureTransforms.
      materials.first
        ..baseColorFactor = Vector4(0.8, 0.2, 0.1, 1.0)
        ..metallicFactor = 0.9
        ..roughnessFactor = 0.1
        ..normalScale = 0.5
        ..occlusionStrength = 0.7;
      packStandardTextureTransforms(materials.first);
      expect(standardTextureTransformPackCount(materials.first), 1);
    });

    test(
      'repacks on standard slot replacements and sets transformedUvs flag',
      () {
        final material = PhysicallyBasedMaterial();
        final initial = packStandardTextureTransforms(material);
        expect(standardTextureTransformPackCount(material), 1);
        expect(initial.getFloat32(7 * 4, Endian.host), 0.0);

        material.baseColorTextureTransform = TextureTransform(
          offset: Vector2(0.25, -0.5),
          scale: Vector2(2.0, 3.0),
          rotation: math.pi / 3,
        );
        final repacked = packStandardTextureTransforms(material);
        expect(standardTextureTransformPackCount(material), 2);
        expect(repacked.getFloat32(0 * 4, Endian.host), closeTo(0.25, 1e-6));
        expect(repacked.getFloat32(1 * 4, Endian.host), closeTo(-0.5, 1e-6));
        expect(repacked.getFloat32(2 * 4, Endian.host), closeTo(2.0, 1e-6));
        expect(repacked.getFloat32(3 * 4, Endian.host), closeTo(3.0, 1e-6));
        expect(
          repacked.getFloat32(4 * 4, Endian.host),
          closeTo(math.cos(math.pi / 3), 1e-6),
        );
        expect(
          repacked.getFloat32(5 * 4, Endian.host),
          closeTo(math.sin(math.pi / 3), 1e-6),
        );
        expect(repacked.getFloat32(7 * 4, Endian.host), 1.0);

        final mutators = <String, void Function(PhysicallyBasedMaterial)>{
          'baseColorTextureTransform': (m) =>
              m.baseColorTextureTransform = TextureTransform(),
          'baseColorTextureTexCoord': (m) => m.baseColorTextureTexCoord = 1,
          'metallicRoughnessTextureTransform': (m) =>
              m.metallicRoughnessTextureTransform = TextureTransform(
                scale: Vector2.all(2),
              ),
          'metallicRoughnessTextureTexCoord': (m) =>
              m.metallicRoughnessTextureTexCoord = 1,
          'normalTextureTransform': (m) =>
              m.normalTextureTransform = TextureTransform(rotation: 0.4),
          'normalTextureTexCoord': (m) => m.normalTextureTexCoord = 1,
          'emissiveTextureTransform': (m) => m.emissiveTextureTransform =
              TextureTransform(offset: Vector2(0.1, 0.2)),
          'emissiveTextureTexCoord': (m) => m.emissiveTextureTexCoord = 1,
          'occlusionTextureTransform': (m) => m.occlusionTextureTransform =
              TextureTransform(scale: Vector2(1, 2)),
          'occlusionTextureTexCoord': (m) => m.occlusionTextureTexCoord = 1,
        };

        var expectedPacks = 2;
        for (final entry in mutators.entries) {
          entry.value(material);
          packStandardTextureTransforms(material);
          expectedPacks++;
          expect(
            standardTextureTransformPackCount(material),
            expectedPacks,
            reason: ' did not trigger a repack',
          );
        }
      },
    );

    test('repacks on in-place scalar mutations without setter calls', () {
      final harness = _CpuDedupHarness(alignment: 256);

      // 1) UnlitMaterial in-place mutation (e.g. UV scrolling via offset.x += ...)
      final unlit = UnlitMaterial();
      final unlitSlice1 = harness.emplaceDeduplicated(
        packUnlitTextureTransform(unlit),
      );
      final unlitBytes1 = harness.read(unlitSlice1);
      expect(unlitTextureTransformPackCount(unlit), 1);
      expect(harness.stagedBytes, 32);

      expect(
        identical(
          harness.emplaceDeduplicated(packUnlitTextureTransform(unlit)),
          unlitSlice1,
        ),
        isTrue,
      );
      expect(unlitTextureTransformPackCount(unlit), 1);

      unlit.baseColorTextureTransform.offset.x += 0.25;
      final unlitRepacked = packUnlitTextureTransform(unlit);
      final unlitSlice2 = harness.emplaceDeduplicated(unlitRepacked);
      expect(unlitTextureTransformPackCount(unlit), 2);
      expect(identical(unlitSlice2, unlitSlice1), isFalse);
      expect(harness.read(unlitSlice2), isNot(equals(unlitBytes1)));
      expect(unlitRepacked.getFloat32(0, Endian.host), closeTo(0.25, 1e-6));

      unlit.baseColorTextureTransform
        ..scale.y = -1.0
        ..rotation = math.pi / 7;
      final unlitSlice3 = harness.emplaceDeduplicated(
        packUnlitTextureTransform(unlit),
      );
      expect(unlitTextureTransformPackCount(unlit), 3);
      for (var i = 0; i < 10; i++) {
        expect(
          identical(
            harness.emplaceDeduplicated(packUnlitTextureTransform(unlit)),
            unlitSlice3,
          ),
          isTrue,
        );
      }
      expect(unlitTextureTransformPackCount(unlit), 3);

      // 2) PhysicallyBasedMaterial in-place mutations across slots
      harness.resetEpoch();
      final pbr = PhysicallyBasedMaterial();
      final pbrInitial = packStandardTextureTransforms(pbr);
      final pbrSlice1 = harness.emplaceDeduplicated(pbrInitial);
      expect(standardTextureTransformPackCount(pbr), 1);
      expect(pbrInitial.getFloat32(7 * 4, Endian.host), 0.0);

      pbr.baseColorTextureTransform.offset.x += 0.25;
      final pbrAfterBase = packStandardTextureTransforms(pbr);
      final pbrSlice2 = harness.emplaceDeduplicated(pbrAfterBase);
      expect(standardTextureTransformPackCount(pbr), 2);
      expect(identical(pbrSlice2, pbrSlice1), isFalse);
      expect(pbrAfterBase.getFloat32(0, Endian.host), closeTo(0.25, 1e-6));
      expect(pbrAfterBase.getFloat32(7 * 4, Endian.host), 1.0);

      pbr.emissiveTextureTransform.rotation = math.pi / 4;
      final pbrAfterEmissive = packStandardTextureTransforms(pbr);
      final pbrSlice3 = harness.emplaceDeduplicated(pbrAfterEmissive);
      expect(standardTextureTransformPackCount(pbr), 3);
      expect(identical(pbrSlice3, pbrSlice2), isFalse);
      expect(
        pbrAfterEmissive.getFloat32((24 + 4) * 4, Endian.host),
        closeTo(math.cos(math.pi / 4), 1e-6),
      );

      pbr.normalTextureTransform.scale.y = 2.5;
      final pbrAfterNormal = packStandardTextureTransforms(pbr);
      final pbrSlice4 = harness.emplaceDeduplicated(pbrAfterNormal);
      expect(standardTextureTransformPackCount(pbr), 4);
      expect(
        pbrAfterNormal.getFloat32((16 + 3) * 4, Endian.host),
        closeTo(2.5, 1e-6),
      );

      for (var i = 0; i < 10; i++) {
        expect(
          identical(
            harness.emplaceDeduplicated(packStandardTextureTransforms(pbr)),
            pbrSlice4,
          ),
          isTrue,
        );
      }
      expect(standardTextureTransformPackCount(pbr), 4);
    });
  });
}
