import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/texture_transform_cache.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ByteData _patterned(int length, {int seed = 1}) {
  final list = Uint8List(length);
  var state = seed & 0xFF;
  for (var i = 0; i < length; i++) {
    state = ((state * 73) + i + 19) & 0xFF;
    list[i] = state;
  }
  return ByteData.sublistView(list);
}

List<int> _read(TransientStagingBuffer block, int offset, int length) => [
  for (var i = 0; i < length; i++) block.staging.getUint8(offset + i),
];

List<int> _bytesOf(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes).toList();

void main() {
  group('TransientStagingBuffer', () {
    const sizes = [4, 12, 17, 160, 704, 1028];

    test('stages up to the last byte of an odd capacity', () {
      for (final capacity in const [65, 1025]) {
        final block = TransientStagingBuffer(capacity);
        expect(block.staging.lengthInBytes, capacity);
        final source = _patterned(capacity, seed: 31);
        block.stage(0, source);
        expect(_read(block, 0, capacity), _bytesOf(source));
      }
    });

    test('stages aligned and unaligned slices without touching neighbors', () {
      for (final misalign in const [0, 2]) {
        final block = TransientStagingBuffer(8192);
        for (var i = 0; i < block.capacity; i++) {
          block.staging.setUint8(i, 0xCC);
        }
        var offset = 4 + misalign;
        for (final size in sizes) {
          // A subview whose own offset is not word aligned either.
          final backing = Uint8List(size + 2)
            ..setAll(2, _bytesOf(_patterned(size, seed: size)));
          final source = ByteData.sublistView(backing, 2);
          block.stage(offset, source);
          expect(block.staging.getUint8(offset - 1), 0xCC);
          expect(block.staging.getUint8(offset + size), 0xCC);
          expect(_read(block, offset, size), _bytesOf(source));
          offset = (offset + size + 8) & ~3 | misalign;
        }
      }
    });
  });

  group('TextureTransformCache', () {
    TextureTransform identity() => TextureTransform();

    test('packs once while unchanged', () {
      final cache = TextureTransformCache.standardFive();
      final transforms = List.generate(5, (_) => identity());
      ByteData pack() => cache.packFive(
        transforms[0],
        0,
        transforms[1],
        0,
        transforms[2],
        0,
        transforms[3],
        0,
        transforms[4],
        0,
      );
      final bytes = pack();
      expect(bytes.lengthInBytes, 160);
      expect(bytes.getFloat32(7 * 4, Endian.host), 0.0);
      for (var i = 0; i < 10; i++) {
        pack();
      }
      expect(cache.packCount, 1);
    });

    test('repacks on replacement, in-place edits, and UV set changes', () {
      final cache = TextureTransformCache.single();
      var transform = identity();
      var texCoord = 0;
      ByteData pack() => cache.packSingle(transform, texCoord);

      pack();
      transform.offset.x += 0.25;
      expect(pack().getFloat32(0, Endian.host), closeTo(0.25, 1e-6));
      transform.scale.y = 2.5;
      expect(pack().getFloat32(3 * 4, Endian.host), closeTo(2.5, 1e-6));
      transform.rotation = math.pi / 3;
      expect(
        pack().getFloat32(5 * 4, Endian.host),
        closeTo(math.sin(math.pi / 3), 1e-6),
      );
      transform = TextureTransform(offset: Vector2(0.5, 0));
      expect(pack().getFloat32(0, Endian.host), closeTo(0.5, 1e-6));
      texCoord = 1;
      expect(pack().getFloat32(6 * 4, Endian.host), 1.0);
      expect(cache.packCount, 6);
      pack();
      expect(cache.packCount, 6);
    });

    test('flags transformed UVs in the base record', () {
      final cache = TextureTransformCache.standardFive();
      final transforms = List.generate(5, (_) => identity());
      ByteData pack({int uv4 = 0}) => cache.packFive(
        transforms[0],
        0,
        transforms[1],
        0,
        transforms[2],
        0,
        transforms[3],
        0,
        transforms[4],
        uv4,
      );
      expect(pack().getFloat32(7 * 4, Endian.host), 0.0);
      expect(pack(uv4: 1).getFloat32(7 * 4, Endian.host), 1.0);
      transforms[2].rotation = 0.4;
      expect(pack().getFloat32(7 * 4, Endian.host), 1.0);
      expect(
        pack().getFloat32((16 + 4) * 4, Endian.host),
        closeTo(math.cos(0.4), 1e-6),
      );
    });
  });
}
