// Covers accessor.dart's null-bufferView (zero-filled base) handling and
// sparse accessor overrides, plus parser.dart's sparse JSON parsing. Pure
// data layer, no Flutter GPU involved.

import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:test/test.dart';

void main() {
  group('null bufferView', () {
    test('a dense-less float accessor reads as a zero-filled base', () {
      final accessor = GltfAccessor(
        componentType: GltfComponentType.float,
        count: 3,
        type: GltfAccessorType.vec3,
      );
      final out = readAccessorAsFloat32(accessor, const [], Uint8List(0));
      expect(out, Float32List(9));
    });

    test('a dense-less uint accessor reads as a zero-filled base', () {
      final accessor = GltfAccessor(
        componentType: GltfComponentType.unsignedShort,
        count: 4,
        type: GltfAccessorType.scalar,
      );
      final out = readAccessorAsUint32(accessor, const [], Uint8List(0));
      expect(out, Uint32List(4));
    });
  });

  group('sparse accessors', () {
    // 4 VEC3 float elements densely stored, then a sparse override of
    // elements 0 and 2. Layout: [dense 4*3 floats][2 indices][2*3 override
    // floats], each section 4-byte aligned already.
    ({Uint8List data, List<GltfBufferView> views}) buildFixture() {
      final dense = Float32List.fromList([
        1, 1, 1, // 0: overridden below
        2, 2, 2, // 1: untouched
        3, 3, 3, // 2: overridden below
        4, 4, 4, // 3: untouched
      ]);
      final indices = Uint16List.fromList([2, 0]); // out of order on purpose
      final overrides = Float32List.fromList([
        30, 30, 30, // -> element 2
        10, 10, 10, // -> element 0
      ]);
      final blob = BytesBuilder();
      blob.add(dense.buffer.asUint8List());
      final indicesOffset = blob.length;
      blob.add(indices.buffer.asUint8List());
      final overridesOffset = blob.length;
      blob.add(overrides.buffer.asUint8List());
      return (
        data: blob.toBytes(),
        views: [
          GltfBufferView(
            buffer: 0,
            byteOffset: 0,
            byteLength: dense.lengthInBytes,
          ),
          GltfBufferView(
            buffer: 0,
            byteOffset: indicesOffset,
            byteLength: indices.lengthInBytes,
          ),
          GltfBufferView(
            buffer: 0,
            byteOffset: overridesOffset,
            byteLength: overrides.lengthInBytes,
          ),
        ],
      );
    }

    test('sparse overrides apply on top of the dense base', () {
      final fixture = buildFixture();
      final accessor = GltfAccessor(
        componentType: GltfComponentType.float,
        count: 4,
        type: GltfAccessorType.vec3,
        bufferView: 0,
        sparse: GltfAccessorSparse(
          count: 2,
          indicesBufferView: 1,
          indicesComponentType: GltfComponentType.unsignedShort,
          valuesBufferView: 2,
        ),
      );
      final out = readAccessorAsFloat32(accessor, fixture.views, fixture.data);
      expect(out, [
        10, 10, 10, // overridden
        2, 2, 2, // untouched
        30, 30, 30, // overridden
        4, 4, 4, // untouched
      ]);
    });

    test('a sparse-only accessor (no bufferView) overrides a zero base', () {
      final fixture = buildFixture();
      final accessor = GltfAccessor(
        componentType: GltfComponentType.float,
        count: 4,
        type: GltfAccessorType.vec3,
        sparse: GltfAccessorSparse(
          count: 2,
          indicesBufferView: 1,
          indicesComponentType: GltfComponentType.unsignedShort,
          valuesBufferView: 2,
        ),
      );
      final out = readAccessorAsFloat32(accessor, fixture.views, fixture.data);
      expect(out, [
        10, 10, 10, // overridden
        0, 0, 0, // still zero
        30, 30, 30, // overridden
        0, 0, 0, // still zero
      ]);
    });

    test('readAccessorAsUint32 applies sparse overrides too', () {
      final dense = Uint32List.fromList([1, 2, 3, 4]);
      final indices = Uint16List.fromList([1]);
      final overrides = Uint32List.fromList([99]);
      final blob = BytesBuilder();
      blob.add(dense.buffer.asUint8List());
      final indicesOffset = blob.length;
      blob.add(indices.buffer.asUint8List());
      final overridesOffset = blob.length;
      blob.add(overrides.buffer.asUint8List());
      final views = [
        GltfBufferView(
          buffer: 0,
          byteOffset: 0,
          byteLength: dense.lengthInBytes,
        ),
        GltfBufferView(
          buffer: 0,
          byteOffset: indicesOffset,
          byteLength: indices.lengthInBytes,
        ),
        GltfBufferView(
          buffer: 0,
          byteOffset: overridesOffset,
          byteLength: overrides.lengthInBytes,
        ),
      ];
      final accessor = GltfAccessor(
        componentType: GltfComponentType.unsignedInt,
        count: 4,
        type: GltfAccessorType.scalar,
        bufferView: 0,
        sparse: GltfAccessorSparse(
          count: 1,
          indicesBufferView: 1,
          indicesComponentType: GltfComponentType.unsignedShort,
          valuesBufferView: 2,
        ),
      );
      final out = readAccessorAsUint32(accessor, views, blob.toBytes());
      expect(out, [1, 99, 3, 4]);
    });

    test('an out-of-range sparse index is rejected', () {
      final fixture = buildFixture();
      // count 4 but this index list names element 4, out of range.
      final badIndices = Uint16List.fromList([4]);
      final badOverrides = Float32List.fromList([1, 1, 1]);
      final blob = BytesBuilder();
      blob.add(fixture.data.sublist(0, 48)); // keep the dense base only
      final indicesOffset = blob.length;
      blob.add(badIndices.buffer.asUint8List());
      final overridesOffset = blob.length;
      blob.add(badOverrides.buffer.asUint8List());
      final views = [
        fixture.views[0],
        GltfBufferView(
          buffer: 0,
          byteOffset: indicesOffset,
          byteLength: badIndices.lengthInBytes,
        ),
        GltfBufferView(
          buffer: 0,
          byteOffset: overridesOffset,
          byteLength: badOverrides.lengthInBytes,
        ),
      ];
      final accessor = GltfAccessor(
        componentType: GltfComponentType.float,
        count: 4,
        type: GltfAccessorType.vec3,
        bufferView: 0,
        sparse: GltfAccessorSparse(
          count: 1,
          indicesBufferView: 1,
          indicesComponentType: GltfComponentType.unsignedShort,
          valuesBufferView: 2,
        ),
      );
      expect(
        () => readAccessorAsFloat32(accessor, views, blob.toBytes()),
        throwsA(isA<FormatException>()),
      );
    });

    test('parser.dart parses the sparse JSON object', () {
      final doc = parseGltfJson({
        'accessors': [
          {
            'componentType': 5126,
            'count': 4,
            'type': 'VEC3',
            'bufferView': 0,
            'sparse': {
              'count': 2,
              'indices': {'bufferView': 1, 'componentType': 5123},
              'values': {'bufferView': 2},
            },
          },
        ],
      });
      final sparse = doc.accessors.single.sparse;
      expect(sparse, isNotNull);
      expect(sparse!.count, 2);
      expect(sparse.indicesBufferView, 1);
      expect(sparse.indicesComponentType, GltfComponentType.unsignedShort);
      expect(sparse.valuesBufferView, 2);
    });
  });
}
