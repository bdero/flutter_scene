// Covers EXT_meshopt_compression decoding, both the bitstream itself and the
// buffer-view rewrite the importers run before any accessor is read.
//
// Two kinds of fixture. The hex streams below were produced by an external
// encoder for this extension, and each pairs with the exact bytes that
// encoder's own decoder produces for it; the Dart decoder must reproduce them
// byte for byte. The `.glb` pairs under test/fixtures/meshopt are the same
// asset written twice by the same external tool, once compressed and once
// plain, so decoding the compressed one must reproduce the plain one.
//
// Regenerating the `.glb` pairs, from examples/assets_src/two_triangles.glb:
//   two_triangles_plain.glb                   -noq
//   two_triangles_compressed.glb              -noq -cc
//   two_triangles_exponential_plain.glb       -vpf -vnf
//   two_triangles_exponential_compressed.glb  -vpf -vnf -c

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('attribute streams', () {
    test('decode a version 0 stream', () {
      expect(
        _decode(_attributesV0, count: 20, byteStride: 16),
        _hex(_attributesV0Decoded),
      );
    });

    test('decode a version 1 stream', () {
      expect(
        _decode(_attributesV1, count: 20, byteStride: 16),
        _hex(_attributesV1Decoded),
      );
    });

    test('decode a version 0 stream using every group width', () {
      expect(
        _decode(_attributesWideV0, count: 33, byteStride: 8),
        _hex(_attributesWideV0Decoded),
      );
    });

    test('decode a version 1 stream using every group width', () {
      expect(
        _decode(_attributesWideV1, count: 33, byteStride: 8),
        _hex(_attributesWideV1Decoded),
      );
    });

    test('decode a stream mixing narrow and byte-wide groups', () {
      expect(
        _decode(_attributesBurst, count: 64, byteStride: 4),
        _hex(_attributesBurstDecoded),
      );
    });

    test('decode a stream spanning two blocks', () {
      // A 256-byte stride caps a block at 32 elements, so 40 elements need a
      // second block that continues from the first block's last element.
      expect(
        _decodeBytes(
          _fixture('multi_block.stream'),
          count: 40,
          byteStride: 256,
        ),
        _fixture('multi_block.raw'),
      );
    });

    test('reject a stream whose header byte is not an attribute header', () {
      final broken = _hex(_attributesV0)..[0] = 0xb0;
      expect(
        () => _decodeBytes(broken, count: 20, byteStride: 16),
        throwsFormatContaining('header byte 0xb0'),
      );
    });

    test('reject a truncated stream', () {
      expect(
        () => _decodeBytes(
          Uint8List.sublistView(_hex(_attributesV0), 0, 40),
          count: 20,
          byteStride: 16,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('reject a stream whose body does not reach its tail', () {
      final source = _hex(_attributesV0);
      final padded = Uint8List(source.length + 8)
        ..setRange(0, source.length, source);
      expect(
        () => _decodeBytes(padded, count: 20, byteStride: 16),
        throwsFormatContaining('expected'),
      );
    });

    test('reject a stream too short to hold its tail', () {
      expect(
        () => _decodeBytes(
          Uint8List.fromList([0xa1, 0, 0, 0]),
          count: 1,
          byteStride: 4,
        ),
        throwsFormatContaining('too short to hold'),
      );
    });

    test('reject a stride that is not a multiple of four', () {
      expect(
        () => _decodeBytes(_hex(_attributesV0), count: 20, byteStride: 6),
        throwsFormatContaining('multiple of 4'),
      );
    });
  });

  group('index streams', () {
    test('decode a 32-bit triangle list', () {
      final decoded = _decode(
        _triangles32,
        count: 72,
        byteStride: 4,
        mode: 'TRIANGLES',
      );
      expect(decoded, _hex(_triangles32Decoded));
      // Runs of shared edges, then three isolated triangles and two that
      // reach back, which is what drives the codes off the shared-edge path.
      expect(Uint32List.sublistView(decoded).skip(60), [
        200, 201, 202, //
        90, 91, 92, //
        202, 201, 300, //
        5, 300, 7,
      ]);
    });

    test('decode a 16-bit triangle list', () {
      final decoded = _decode(
        _triangles16,
        count: 15,
        byteStride: 2,
        mode: 'TRIANGLES',
      );
      expect(decoded, _hex(_triangles16Decoded));
      expect(Uint16List.sublistView(decoded), [
        0, 1, 2, //
        2, 1, 3, //
        4, 5, 6, //
        2, 3, 0, //
        3, 2, 6,
      ]);
    });

    test('decode a 16-bit index sequence', () {
      final decoded = _decode(
        _sequence16,
        count: 10,
        byteStride: 2,
        mode: 'INDICES',
      );
      expect(decoded, _hex(_sequence16Decoded));
      // Two interleaved runs, which is what the pair of baselines is for.
      expect(Uint16List.sublistView(decoded), [
        0, 1000, 1, 1001, 2, //
        1002, 3, 1003, 65535, 4,
      ]);
    });

    test('decode a 32-bit index sequence', () {
      final decoded = _decode(
        _sequence32,
        count: 9,
        byteStride: 4,
        mode: 'INDICES',
      );
      expect(decoded, _hex(_sequence32Decoded));
      expect(Uint32List.sublistView(decoded), [
        0, 5, 4, //
        100000, 99999, 3, //
        2000000, 1, 2000001,
      ]);
    });

    test('reject an index count that is not whole triangles', () {
      expect(
        () => _decodeBytes(
          _hex(_triangles32),
          count: 71,
          byteStride: 4,
          mode: 'TRIANGLES',
        ),
        throwsFormatContaining('whole number of triangles'),
      );
    });

    test('reject an index stride that is neither 2 nor 4', () {
      expect(
        () => _decodeBytes(
          _hex(_sequence16),
          count: 10,
          byteStride: 3,
          mode: 'INDICES',
        ),
        throwsFormatContaining('neither 2 nor 4'),
      );
    });

    test('reject a filter on index data', () {
      expect(
        () => _decodeBytes(
          _hex(_triangles32),
          count: 72,
          byteStride: 4,
          mode: 'TRIANGLES',
          filter: 'OCTAHEDRAL',
        ),
        throwsFormatContaining('cannot carry'),
      );
    });

    test('reject a triangle stream with a wrong header byte', () {
      final broken = _hex(_triangles32)..[0] = 0xe0;
      expect(
        () => _decodeBytes(broken, count: 72, byteStride: 4, mode: 'TRIANGLES'),
        throwsFormatContaining('expected 0xe1'),
      );
    });

    test('reject a triangle stream too short for its codes', () {
      expect(
        () => _decodeBytes(
          Uint8List.fromList([0xe1, 0, 0, 0]),
          count: 72,
          byteStride: 4,
          mode: 'TRIANGLES',
        ),
        throwsFormatContaining('too short'),
      );
    });

    test('reject a triangle stream that stops short of its lookup table', () {
      final source = _hex(_triangles32);
      final padded = Uint8List(source.length + 12)
        ..setRange(0, source.length - 16, source)
        ..setRange(
          source.length - 4,
          source.length + 12,
          Uint8List.sublistView(source, source.length - 16),
        );
      expect(
        () => _decodeBytes(padded, count: 72, byteStride: 4, mode: 'TRIANGLES'),
        throwsFormatContaining('between its data and its lookup table'),
      );
    });

    test('reject a garbage index sequence', () {
      final garbage = Uint8List.fromList([0xd1, ...List.filled(80, 0xff)]);
      expect(
        () => _decodeBytes(garbage, count: 64, byteStride: 4, mode: 'INDICES'),
        throwsA(isA<FormatException>()),
      );
    });

    test('reject an index sequence that stops short of its tail', () {
      final source = _hex(_sequence16);
      final padded = Uint8List(source.length + 6)
        ..setRange(0, source.length, source);
      expect(
        () => _decodeBytes(padded, count: 10, byteStride: 2, mode: 'INDICES'),
        throwsFormatContaining('between its data and its tail'),
      );
    });
  });

  group('filters', () {
    test('octahedral rebuilds 8-bit unit vectors', () {
      final decoded = _decode(
        _octahedral8,
        count: 6,
        byteStride: 4,
        filter: 'OCTAHEDRAL',
      );
      expect(decoded, _hex(_octahedral8Decoded));
      // Components scale by the type's maximum, so +Z reads as (0, 0, 127),
      // and the fourth component passes through untouched.
      expect(Int8List.sublistView(decoded).take(12), [
        0, 0, 127, 127, //
        127, 0, 0, 127, //
        0, -127, 0, -127,
      ]);
      // 8-bit components leave the off-axis vectors a little short of unit.
      _expectUnitVectors(
        Int8List.sublistView(decoded),
        6,
        127,
        tolerance: 1e-2,
      );
    });

    test('octahedral rebuilds 16-bit unit vectors', () {
      final decoded = _decode(
        _octahedral16,
        count: 6,
        byteStride: 8,
        filter: 'OCTAHEDRAL',
      );
      expect(decoded, _hex(_octahedral16Decoded));
      expect(Int16List.sublistView(decoded).take(12), [
        0, 0, 32767, 32767, //
        32767, 0, 0, 32767, //
        0, -32767, 0, -32767,
      ]);
      _expectUnitVectors(Int16List.sublistView(decoded), 6, 32767);
    });

    test('octahedral rebuilds vectors stored below full precision', () {
      // The same vectors at 12 bits, which is what makes the third component
      // carry the encoding's 1.0 instead of the type's maximum.
      final decoded = _decode(
        _octahedral12,
        count: 6,
        byteStride: 8,
        filter: 'OCTAHEDRAL',
      );
      expect(decoded, _hex(_octahedral12Decoded));
      _expectUnitVectors(Int16List.sublistView(decoded), 6, 32767);
    });

    test('quaternion rebuilds the dropped component', () {
      final decoded = _decode(
        _quaternion,
        count: 6,
        byteStride: 8,
        filter: 'QUATERNION',
      );
      expect(decoded, _hex(_quaternionDecoded));
      final values = Int16List.sublistView(decoded);
      // Identity, then a 90 degree turn about x. The third rotation comes back
      // negated, which names the same rotation.
      expect(values.take(4), [0, 0, 0, 32767]);
      expect(values.skip(4).take(4), [23170, 0, 0, 23170]);
      expect(values.skip(8).take(4), [0, 23170, 0, -23170]);
      _expectUnitVectors(values, 6, 32767, components: 4);
    });

    test('quaternion rebuilds rotations stored below full precision', () {
      final decoded = _decode(
        _quaternion12,
        count: 6,
        byteStride: 8,
        filter: 'QUATERNION',
      );
      expect(decoded, _hex(_quaternion12Decoded));
      _expectUnitVectors(
        Int16List.sublistView(decoded),
        6,
        32767,
        components: 4,
      );
    });

    test('exponential rebuilds floats', () {
      final decoded = _decode(
        _exponential,
        count: 5,
        byteStride: 12,
        filter: 'EXPONENTIAL',
      );
      expect(decoded, _hex(_exponentialDecoded));
      // The encoder shares one exponent across each element, so the small
      // components of a wide-ranging element quantize away.
      expect(Float32List.sublistView(decoded), [
        0, 0, 0, //
        1, -1, 0.5, //
        123.5, 0, 4096, //
        -8, 0, 65536, //
        0.5, -0.5, 0.125,
      ]);
    });

    test('exponential rebuilds a single-component stride', () {
      final decoded = _decode(
        _exponential4,
        count: 6,
        byteStride: 4,
        filter: 'EXPONENTIAL',
      );
      expect(decoded, _hex(_exponential4Decoded));
      expect(Float32List.sublistView(decoded), [0, 1, -2.5, 1024, -0.03125, 7]);
    });

    test('reject an octahedral stride other than 4 or 8', () {
      expect(
        () => _decodeBytes(
          _hex(_octahedral8),
          count: 6,
          byteStride: 12,
          filter: 'OCTAHEDRAL',
        ),
        throwsFormatContaining('stride of 4 or 8'),
      );
    });

    test('reject a quaternion stride other than 8', () {
      expect(
        () => _decodeBytes(
          _hex(_quaternion),
          count: 6,
          byteStride: 4,
          filter: 'QUATERNION',
        ),
        throwsFormatContaining('stride of 8'),
      );
    });

    test('reject an exponential stride that is not a multiple of four', () {
      expect(
        () => _decodeBytes(
          _hex(_exponential),
          count: 5,
          byteStride: 10,
          filter: 'EXPONENTIAL',
        ),
        throwsFormatContaining('multiple of 4'),
      );
    });

    test('reject an unknown filter', () {
      expect(
        () => _decodeBytes(
          _hex(_attributesV0),
          count: 20,
          byteStride: 16,
          filter: 'COLOR',
        ),
        throwsFormatContaining(
          'Unknown EXT_meshopt_compression filter "COLOR"',
        ),
      );
    });
  });

  group('buffer view rewrite', () {
    test('leaves an uncompressed document alone', () {
      final doc = GltfDocument(
        buffers: [GltfBuffer(byteLength: 4)],
        bufferViews: [GltfBufferView(buffer: 0, byteLength: 4)],
      );
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final decoded = decodeMeshoptBufferViews(doc, data);
      expect(decoded.doc, same(doc));
      expect(decoded.bufferData, same(data));
    });

    test('keeps uncompressed views addressing the original bytes', () {
      final source = _hex(_sequence16);
      final data = Uint8List(source.length + 8)
        ..setRange(0, 4, [9, 8, 7, 6])
        ..setRange(8, 8 + source.length, source);
      final doc = GltfDocument(
        buffers: [GltfBuffer(byteLength: data.length)],
        bufferViews: [
          GltfBufferView(buffer: 0, byteOffset: 0, byteLength: 4),
          GltfBufferView(
            buffer: 0,
            byteOffset: 0,
            byteLength: 20,
            meshopt: GltfMeshoptCompression(
              buffer: 0,
              byteOffset: 8,
              byteLength: source.length,
              byteStride: 2,
              count: 10,
              mode: 'INDICES',
            ),
          ),
        ],
      );
      final decoded = decodeMeshoptBufferViews(doc, data);
      final plain = decoded.doc.bufferViews[0];
      final rewritten = decoded.doc.bufferViews[1];
      expect(plain.byteOffset, 0);
      expect(decoded.bufferData.sublist(0, 4), [9, 8, 7, 6]);
      expect(rewritten.meshopt, isNull);
      expect(rewritten.byteOffset, greaterThanOrEqualTo(data.length));
      expect(rewritten.byteLength, 20);
      expect(
        Uint8List.sublistView(
          decoded.bufferData,
          rewritten.byteOffset,
          rewritten.byteOffset + rewritten.byteLength,
        ),
        _hex(_sequence16Decoded),
      );
    });

    test('names the placeholder buffer but not the compressed source', () {
      final doc = GltfDocument(
        buffers: [
          GltfBuffer(byteLength: 8),
          GltfBuffer(byteLength: 4096, meshoptFallback: true),
        ],
        bufferViews: [
          GltfBufferView(
            buffer: 1,
            byteLength: 20,
            meshopt: GltfMeshoptCompression(
              buffer: 0,
              byteLength: 8,
              byteStride: 2,
              count: 10,
              mode: 'INDICES',
            ),
          ),
        ],
      );
      expect(meshoptPlaceholderBuffers(doc), {1});
    });

    test('reports an unknown mode without reading the fallback buffer', () {
      final doc = GltfDocument(
        buffers: [
          GltfBuffer(byteLength: 8),
          GltfBuffer(byteLength: 4096, meshoptFallback: true),
        ],
        bufferViews: [
          GltfBufferView(
            buffer: 1,
            byteLength: 20,
            meshopt: GltfMeshoptCompression(
              buffer: 0,
              byteLength: 8,
              byteStride: 2,
              count: 10,
              mode: 'SEQUENCE',
            ),
          ),
        ],
      );
      expect(
        () => decodeMeshoptBufferViews(doc, Uint8List(8)),
        throwsFormatContaining(
          'Unknown EXT_meshopt_compression mode '
          '"SEQUENCE"',
        ),
      );
    });

    test('rejects compressed data sourced from a secondary buffer', () {
      final doc = GltfDocument(
        buffers: [GltfBuffer(byteLength: 8), GltfBuffer(byteLength: 8)],
        bufferViews: [
          GltfBufferView(
            buffer: 0,
            byteLength: 20,
            meshopt: GltfMeshoptCompression(
              buffer: 1,
              byteLength: 8,
              byteStride: 2,
              count: 10,
              mode: 'INDICES',
            ),
          ),
        ],
      );
      expect(
        () => decodeMeshoptBufferViews(doc, Uint8List(8)),
        throwsFormatContaining('only the primary buffer'),
      );
    });

    test('rejects a view reaching past the end of its buffer', () {
      final doc = GltfDocument(
        buffers: [GltfBuffer(byteLength: 8)],
        bufferViews: [
          GltfBufferView(
            buffer: 0,
            byteLength: 20,
            meshopt: GltfMeshoptCompression(
              buffer: 0,
              byteOffset: 4,
              byteLength: 64,
              byteStride: 2,
              count: 10,
              mode: 'INDICES',
            ),
          ),
        ],
      );
      expect(
        () => decodeMeshoptBufferViews(doc, Uint8List(8)),
        throwsFormatContaining('spans bytes 4..68'),
      );
    });

    test('rejects a decoded index that overruns its primitive', () {
      final source = _hex(_triangles32);
      final doc = GltfDocument(
        buffers: [GltfBuffer(byteLength: source.length)],
        bufferViews: [
          GltfBufferView(
            buffer: 0,
            byteLength: 288,
            meshopt: GltfMeshoptCompression(
              buffer: 0,
              byteLength: source.length,
              byteStride: 4,
              count: 72,
              mode: 'TRIANGLES',
            ),
          ),
        ],
        accessors: [
          GltfAccessor(
            componentType: GltfComponentType.unsignedInt,
            count: 72,
            type: GltfAccessorType.scalar,
            bufferView: 0,
          ),
          GltfAccessor(
            componentType: GltfComponentType.float,
            count: 4,
            type: GltfAccessorType.vec3,
          ),
        ],
        meshes: [
          GltfMesh(
            primitives: [
              GltfMeshPrimitive(attributes: {'POSITION': 1}, indices: 0),
            ],
          ),
        ],
      );
      expect(
        () => decodeMeshoptBufferViews(doc, source),
        throwsFormatContaining('addresses a primitive with 4 vertices'),
      );
    });

    test('rejects an accessor that overruns its decoded view', () {
      final source = _hex(_sequence16);
      final doc = GltfDocument(
        buffers: [GltfBuffer(byteLength: source.length)],
        bufferViews: [
          GltfBufferView(
            buffer: 0,
            byteLength: 20,
            meshopt: GltfMeshoptCompression(
              buffer: 0,
              byteLength: source.length,
              byteStride: 2,
              count: 10,
              mode: 'INDICES',
            ),
          ),
        ],
        accessors: [
          GltfAccessor(
            componentType: GltfComponentType.unsignedShort,
            count: 24,
            type: GltfAccessorType.scalar,
            bufferView: 0,
          ),
        ],
      );
      expect(
        () => decodeMeshoptBufferViews(doc, source),
        throwsFormatContaining('needs 48 bytes'),
      );
    });
  });

  group('compressed assets', () {
    test('two_triangles decodes to the plain asset', () {
      final compressed = _fixture('two_triangles_compressed.glb');
      final decoded = _decodeGlb(compressed);
      final reference = _decodeGlb(_fixture('two_triangles_plain.glb'));
      expect(decoded.doc.bufferViews.length, reference.doc.bufferViews.length);

      final filters = [
        for (final view in parseGltfJson(parseGlb(compressed).json).bufferViews)
          view.meshopt?.filter,
      ];
      expect(filters, contains('QUATERNION'));

      for (int i = 0; i < decoded.doc.bufferViews.length; i++) {
        final got = _slice(decoded.bufferData, decoded.doc.bufferViews[i]);
        final want = _slice(reference.bufferData, reference.doc.bufferViews[i]);
        expect(got.length, want.length, reason: 'view $i length');
        if (filters[i] == 'QUATERNION') {
          // The filter re-encodes rotations as a max-component triple, so this
          // view is close to the plain asset rather than equal to it.
          final a = Int16List.sublistView(got);
          final b = Int16List.sublistView(want);
          for (int c = 0; c < a.length; c++) {
            expect(
              a[c] / 32767.0,
              closeTo(b[c] / 32767.0, 2e-3),
              reason: 'view $i component $c',
            );
          }
          continue;
        }
        expect(got, want, reason: 'view $i bytes');
      }
    });

    test('two_triangles packs the same geometry as the plain asset', () {
      _expectSameGeometry(
        _fixture('two_triangles_compressed.glb'),
        _fixture('two_triangles_plain.glb'),
      );
    });

    test('exponential-filtered asset decodes to the plain asset', () {
      final compressed = _fixture('two_triangles_exponential_compressed.glb');
      final plain = _fixture('two_triangles_exponential_plain.glb');
      final decoded = _decodeGlb(compressed);
      final reference = _decodeGlb(plain);
      expect(decoded.doc.bufferViews.length, reference.doc.bufferViews.length);
      for (int i = 0; i < decoded.doc.bufferViews.length; i++) {
        expect(
          _slice(decoded.bufferData, decoded.doc.bufferViews[i]),
          _slice(reference.bufferData, reference.doc.bufferViews[i]),
          reason: 'view $i bytes',
        );
      }
      _expectSameGeometry(compressed, plain);
    });

    test('exponential-filtered asset imports identically', () {
      // Through the public entry point, so the decode pass is proven to run
      // ahead of everything the importer does.
      expect(
        _stableFsceneb(_fixture('two_triangles_exponential_compressed.glb')),
        _stableFsceneb(_fixture('two_triangles_exponential_plain.glb')),
      );
    });
  });
}

Matcher throwsFormatContaining(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(message)),
);

// Every decoded vector the octahedral and quaternion filters emit is unit
// length, which is the property the filters exist to restore.
void _expectUnitVectors(
  List<int> values,
  int count,
  double maxInt, {
  int components = 3,
  double tolerance = 2e-3,
}) {
  final stride = values.length ~/ count;
  for (int i = 0; i < count; i++) {
    double sum = 0;
    for (int c = 0; c < components; c++) {
      final v = values[i * stride + c] / maxInt;
      sum += v * v;
    }
    expect(sum, closeTo(1.0, tolerance), reason: 'element $i');
  }
}

// Packs every primitive of both assets and compares the packed bytes.
void _expectSameGeometry(Uint8List compressed, Uint8List plain) {
  final got = _packAll(compressed);
  final want = _packAll(plain);
  expect(got.length, want.length);
  expect(got, isNotEmpty);
  for (int i = 0; i < got.length; i++) {
    expect(got[i].vertexCount, want[i].vertexCount, reason: 'primitive $i');
    expect(got[i].indexCount, want[i].indexCount, reason: 'primitive $i');
    expect(
      got[i].vertexBytes,
      want[i].vertexBytes,
      reason: 'primitive $i vertices',
    );
    expect(
      got[i].indexBytes,
      want[i].indexBytes,
      reason: 'primitive $i indices',
    );
  }
}

List<PackedPrimitive> _packAll(Uint8List glbBytes) {
  final gltf = _decodeGlb(glbBytes);
  return [
    for (final mesh in gltf.doc.meshes)
      for (final primitive in mesh.primitives)
        if (primitive.mode == 4)
          packGltfPrimitive(
            primitive: primitive,
            accessors: gltf.doc.accessors,
            bufferViews: gltf.doc.bufferViews,
            bufferData: gltf.bufferData,
            coordinatePolicy: GltfCoordinatePolicy.bakeNative,
            includeSkinning: primitive.attributes.containsKey('JOINTS_0'),
          ),
  ];
}

// Emitted documents carry a freshly generated id, which is the one thing that
// differs between two imports of the same geometry.
Uint8List _stableFsceneb(Uint8List glbBytes) {
  final bytes = importGlbToFscenebBytes(glbBytes);
  const marker = '"documentId": "';
  final needle = marker.codeUnits;
  outer:
  for (int i = 0; i + needle.length < bytes.length; i++) {
    for (int j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    int end = i + needle.length;
    while (end < bytes.length && bytes[end] != 0x22) {
      bytes[end++] = 0x78;
    }
    return bytes;
  }
  fail('emitted document has no id to mask');
}

({GltfDocument doc, Uint8List bufferData}) _decodeGlb(Uint8List glbBytes) {
  final container = parseGlb(glbBytes);
  return decodeMeshoptBufferViews(
    parseGltfJson(container.json),
    container.binaryChunk,
  );
}

Uint8List _slice(Uint8List data, GltfBufferView view) => Uint8List.sublistView(
  data,
  view.byteOffset,
  view.byteOffset + view.byteLength,
);

Uint8List _fixture(String name) {
  for (final prefix in ['', 'packages/flutter_scene/']) {
    final file = File('${prefix}test/fixtures/meshopt/$name');
    if (file.existsSync()) return file.readAsBytesSync();
  }
  throw StateError('Missing meshopt fixture $name');
}

// Decodes a single-view document holding [source], which arrives as hex.
Uint8List _decode(
  String source, {
  required int count,
  required int byteStride,
  String mode = 'ATTRIBUTES',
  String filter = 'NONE',
}) {
  return _decodeBytes(
    _hex(source),
    count: count,
    byteStride: byteStride,
    mode: mode,
    filter: filter,
  );
}

Uint8List _decodeBytes(
  Uint8List source, {
  required int count,
  required int byteStride,
  String mode = 'ATTRIBUTES',
  String filter = 'NONE',
}) {
  final doc = GltfDocument(
    buffers: [GltfBuffer(byteLength: source.length)],
    bufferViews: [
      GltfBufferView(
        buffer: 0,
        byteLength: count * byteStride,
        meshopt: GltfMeshoptCompression(
          buffer: 0,
          byteLength: source.length,
          byteStride: byteStride,
          count: count,
          mode: mode,
          filter: filter,
        ),
      ),
    ],
  );
  final decoded = decodeMeshoptBufferViews(doc, source);
  return _slice(decoded.bufferData, decoded.doc.bufferViews.single);
}

Uint8List _hex(String value) {
  final out = Uint8List(value.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

// Golden pairs: each stream and the exact bytes it decodes to.

const _attributesV0 =
    'a00000000007004a4a4a4a4a4a4a4a4a4a4a4a4a4a4aff0000004a4a4a4a0120008002'
    '0700b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5ff000000b5b5b5b505044104104400000000'
    '000700404020202020202020201010101010ff00000010101010010800000007000893'
    '3f4318b33f3f7b005c3f18bfbfff0000005c20a39f0700fffcc08535a3c0d1c66cc0d3'
    '3340e0ff000000d3933f1f0700ffb33ff4933f3f964e033f4323bf9fff00000043fcc0'
    '600700ffa3d387fcc0c021c94cc08740404cff000000a0b33fe0000000000000000000'
    '0000000000000000000000e80360ea0000c03f2c507010';

const _attributesV0Decoded =
    '00000000e80360ea0000c03f2c507010000000000d0405ea0000e03f30d0f090000000'
    '003204aae900000040e64e963e0000000057044fe900001040c6ae76d4000000007c04'
    'f4e800002040a46bf09000000000a10499e800003040b050a60e00000000c6043ee800'
    '00404056fe866e00000000eb04e3e700005040365e66ce00000000100588e700006040'
    '16f5b1bd0000000035052de700007040d858d858000000005a05d2e600008040d88ed6'
    '7e000000007f0577e60000884006eeb6de00000000a4051ce600009040e684949a0000'
    '0000c905c1e500009840f26a82ba00000000ee0566e50000a040928a22da0000000013'
    '060be50000a84032fad200000000003806b0e40000b0406090b050000000005d0655e4'
    '0000b84070462ef6000000008206fae30000c0401e268ed600000000a7069fe30000c8'
    '40ce16be46';

const _attributesV1 =
    'a1aabb68ff004a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a00b5b5b5b5b5b5b5b5b5'
    'b5b5b5b5b5b5b5b5b5b50104000f0204f262e262f13171fc1e0f0003010f010008933f'
    '4318b33f3f7b005c3f18bfbf5c20a39f00fffcc08535a3c0d1c66cc0d33340e0d3933f'
    '1f00ffb33ff4933f3f964e033f4323bf9f43fcc06000ffa3d387fcc0c021c94cc08740'
    '404ca0b33fe00000000000000000e80360ea0000c03f2c50701000015200';

const _attributesV1Decoded =
    '00000000e80360ea0000c03f2c507010000000000d0405ea0000e03f30d0f090000000'
    '003204aae900000040e64e963e0000000057044fe900001040c6ae76d4000000007c04'
    'f4e800002040a46bf09000000000a10499e800003040b050a60e00000000c6043ee800'
    '00404056fe866e00000000eb04e3e700005040365e66ce00000000100588e700006040'
    '16f5b1bd0000000035052de700007040d858d858000000005a05d2e600008040d88ed6'
    '7e000000007f0577e60000884006eeb6de00000000a4051ce600009040e684949a0000'
    '0000c905c1e500009840f26a82ba00000000ee0566e50000a040928a22da0000000013'
    '060be50000a84032fad200000000003806b0e40000b0406090b050000000005d0655e4'
    '0000b84070462ef6000000008206fae30000c0401e268ed600000000a7069fe30000c8'
    '40ce16be46';

const _attributesWideV0 =
    'a01a080b75117a4d3a88766d326277a98b83400000001a0ed12de607b8ae95e97e0855'
    'ae22e3e3c00000000a1f00993e7d689854204682a85b75a525515f7b2a92c0ab966f29'
    'b61a233ca9917ac0000000161f00a90f2a02ac102d329390201000933085825bc79e5d'
    '201594ad180491095d1ac00000001e051210294211558045151918824a0a50aa614000'
    '00001f00360819301b0913283c0828093107241b29380a362f1a2b200b04040d011320'
    'c0000000121f00122630051a182b2e032419242708261735152d30032e00233911281f'
    '0a1e36c000000030000000000000000000000000000000000000000000000000000000'
    '0000000000';

const _attributesWideV0Decoded =
    '00000000000000000407b3abffff1b090400d2a3ff001f1cfeff93b800ff1234fa00c7'
    'b900ff2a31f7f9130ffffe1c3ef6003d17ffff174af5034d00ffff0d34f1037019ff00'
    '214bf6ffb1cf00003f49f8f905170100435bf1fdd7270001574eef029c2fff005260f4'
    '09492fff00394cf80436e5ff013550fc010dfd00024763f808ddba00023957fb039ffb'
    'ff02243cfeffb4cdff034031f706fd69fe04451af5065db8fd036032f60a0789fc0248'
    '30f9075299fb025547fa041a8efa023f47f60905d8fb034f35f2106081fb044918f711'
    '6d8dfb054b0ff2125b8ffb064d23f6197946fa054613f0172441fa064518f41edb12f9'
    '063b27f21c181ff8054b42f121232ef804545a';

const _attributesWideV1 =
    'a1f5f40a080b75117a4d3a88766d326277a98b830100010a0ed12de607b8ae95e97e08'
    '55ae22e3e301000a00993e7d689854204682a85b75a525515f7b2a92c0ab966f29b61a'
    '233ca9917a1600a90f2a02ac102d329390201000933085825bc79e5d201594ad180491'
    '095d1a1e0a1210294211558045051918824a0a50aa6101000100360819301b0913283c'
    '0828093107241b29380a362f1a2b200b04040d0113201200122630051a182b2e032419'
    '242708261735152d30032e00233911281f0a1e36300000000000000000000000000000'
    '00000000000000000000';

const _attributesWideV1Decoded =
    '00000000000000000407b3abffff1b090400d2a3ff001f1cfeff93b800ff1234fa00c7'
    'b900ff2a31f7f9130ffffe1c3ef6003d17ffff174af5034d00ffff0d34f1037019ff00'
    '214bf6ffb1cf00003f49f8f905170100435bf1fdd7270001574eef029c2fff005260f4'
    '09492fff00394cf80436e5ff013550fc010dfd00024763f808ddba00023957fb039ffb'
    'ff02243cfeffb4cdff034031f706fd69fe04451af5065db8fd036032f60a0789fc0248'
    '30f9075299fb025547fa041a8efa023f47f60905d8fb034f35f2106081fb044918f711'
    '6d8dfb054b0ff2125b8ffb064d23f6197946fa054613f0172441fa064518f41edb12f9'
    '063b27f21c181ff8054b42f121232ef804545a';

const _attributesBurst =
    'a155d5149880020286812112248a220120d5436890066533b5cde423c8054fd511a4a9'
    '2a262800059602109a73786992d5363d87445b529c3caa57ded5061996a84910a410a1'
    '4919997469ca0fcbefbe5a562e429d1293d803d52459a94a0a181242480515a9acc5c9'
    'cca58194f059c5668fc6bc197400000000000000000000000000000000000000000000'
    '0000';

const _attributesBurstDecoded =
    '00000000ffff0001feffff00fefe0000ffff00fffe00fffeffff00fffffffffe000000'
    'ff0001ff000002fe010001ff00000100ff000201ff0003020001040201010401010105'
    '0101010402020205010303050103030600020207000303070003040701030407020204'
    '0701020307010303070102040700020406000203050003030601020205020202040203'
    '0305010303050003040500030305010203060001040600010405ff00050500ff0605ff'
    'fe060600ff0705ff00070600010807ff0007cd3956170904f3acd4698e8a1d61f4beb2'
    'fba106cd836009aee2aad66a0f22bc8c3af5615e5192fa8772c56cd5237d5af32ce0be'
    '48e23ebb1c4e31938b4c6b';

const _octahedral8 =
    'a1ef00fefd547d960000fdad00e5000004030403000000000000000000000000000000'
    '0000000000007f7f00';

const _octahedral8Decoded = '00007f7f7f00007f0081008149494a7fde4366814c9a007f';

const _octahedral16 =
    'a1ffba000102ab105200fefd547f98000002ad0e560000ffab00e70000040304030000'
    '00000000000000000000000000000000ff7fff7f0001';

const _octahedral16Decoded =
    '00000000ff7fff7fff7f00000000ff7f0000018000000180e549e549e749ff7fd7dd74'
    '449e660180cc4c9a990000ff7f';

const _octahedral12 =
    'a1ffba000102ab027b000e0d04070a000002ad027900000f14000d0000040304030000'
    '00000000000000000000000000000000ff07ff7f0001';

const _octahedral12Decoded =
    '00000000ff7fff7fff7f00000000ff7f0000018000000180dd49dd49f949ff7fcedd7d'
    '4495660180c54c95990000ff7f';

const _quaternion =
    'a1ffbf00000031c93d0000009c186b00000201fb2b0000ffffb4de00010200fb8600fe'
    'fd00b4230005020203060000000000000000000000000000000000000000ff7f0000';

const _quaternionDecoded =
    '000000000000ff7f825a00000000825a0000825a00007ea5000000003273cb37ff3f00'
    '4000400040bb1968d97533a16b';

const _quaternion12 =
    'a1ffbf000000238dc100000008020500000201b11f00000f100a1100010200b135000e'
    '0d000a010005020203060000000000000000000000000000000000000000ff070000';

const _quaternion12Decoded =
    '000000000000ff7f825a00000000825a0000825a00007ea5000000003273cc370f40fa'
    '3ffa3ffa3fbc1967d977339f6b';

const _exponential =
    'a1fffeee000011100200403f0142000000010200ca180821003f40003f000102000100'
    'ca180821002020002f00ca1808210000000000000000000000008e0000008e0000008e'
    '000000';

const _exponentialDecoded =
    '0000000000000000000000000000803f000080bf0000003f0000f74200000000000080'
    '45000000c100000000000080470000003f000000bf0000003e';

const _exponential4 =
    'a1fa000811120f1600ca02121d0e000000000000000000000000000000000000000000'
    '008900';

const _exponential4Decoded = '000000000000803f000020c000008044000000bd0000e040';

const _triangles32 =
    'e1f01002fe010002fe010002fe010002fe010002feffff4fff1212121212ff90030202'
    'ffdf010202a0031dcd04007687566778a9866589689801690000';

const _triangles32Decoded =
    '0000000001000000020000000200000001000000030000000200000003000000010000'
    '0004000000030000000200000004000000020000000300000004000000030000000500'
    '0000040000000500000003000000060000000500000004000000060000000400000005'
    '0000000600000005000000070000000600000007000000050000000800000007000000'
    '0600000008000000060000000700000008000000070000000900000008000000090000'
    '00070000000a00000009000000080000000a00000008000000090000000a0000000900'
    '00000b0000000a0000000b000000090000000c0000000b0000000a000000c8000000c9'
    '000000ca0000005a0000005b0000005c000000ca000000c90000002c01000005000000'
    '2c01000007000000';

const _triangles16 = 'e1f010f036ff5106007687566778a9866589689801690000';

const _triangles16Decoded =
    '000001000200020001000300040005000600020003000000030002000600';

const _sequence16 = 'd100a11f040504050405f0ff0f9b1f00000000';

const _sequence16Decoded = '0000e8030100e9030200ea030300eb03ffff0400';

const _sequence32 = 'd100140281b518030285efcf03060500000000';

const _sequence32Decoded =
    '000000000500000004000000a08601009f8601000300000080841e000100000081841e'
    '00';
