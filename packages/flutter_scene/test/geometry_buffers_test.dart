// Covers the buffers a geometry upload allocates and how the streams reach
// them: an arena allocation stays one contiguous block, a non-arena upload
// takes its storage from createGeometryBuffers, and both accept a stream as
// the typed list it already is. GPU-gated like the other buffer suites.
//
// The storage is backend-defined, so the layout expectations branch on
// [kIsWeb]: native packs one shared buffer with the indices after the vertex
// streams, web hands back a buffer per role with the indices at zero. Run the
// web half with `flutter test --platform chrome`.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_scene/scene.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

bool _gpuAvailable() {
  try {
    gpu.gpuContext.createDeviceBuffer(gpu.StorageMode.hostVisible, 4);
    return true;
  } catch (_) {
    return false;
  }
}

/// Records the views [Geometry._uploadStreams] binds, so a test can see which
/// buffer each stream landed in and at what offset.
class _RecordingGeometry extends UnskinnedGeometry {
  List<gpu.BufferView> streams = const [];
  gpu.BufferView? indices;

  @override
  void setVertexStreams(List<gpu.BufferView> streams, int vertexCount) {
    this.streams = streams;
    super.setVertexStreams(streams, vertexCount);
  }

  @override
  void setIndices(gpu.BufferView indices, gpu.IndexType indexType) {
    this.indices = indices;
    super.setIndices(indices, indexType);
  }
}

/// A triangle, as the structure-of-arrays upload path takes it.
final _positions = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);

_RecordingGeometry _upload({
  TypedData? indices,
  gpu.IndexType indexType = gpu.IndexType.int16,
  GeometryBufferArena? bufferArena,
}) {
  final geometry = _RecordingGeometry();
  geometry.uploadUnskinnedAttributes(
    positions: _positions,
    vertexCount: 3,
    indices: indices,
    indexType: indexType,
    bufferArena: bufferArena,
  );
  return geometry;
}

int _streamBytes(_RecordingGeometry geometry) =>
    geometry.streams.fold(0, (total, view) => total + view.lengthInBytes);

/// Checks where an upload put its indices, which is backend-defined: web gives
/// them their own buffer from offset zero, native appends them to the shared
/// one after the vertex streams.
void _expectIndexPlacement(_RecordingGeometry geometry) {
  final indices = geometry.indices!;
  if (kIsWeb) {
    for (final stream in geometry.streams) {
      expect(identical(stream.buffer, indices.buffer), isFalse);
    }
    expect(indices.offsetInBytes, 0);
    expect(indices.buffer.sizeInBytes, indices.lengthInBytes);
  } else {
    for (final stream in geometry.streams) {
      expect(identical(stream.buffer, indices.buffer), isTrue);
    }
    expect(indices.offsetInBytes, _streamBytes(geometry));
  }
}

void main() {
  if (!_gpuAvailable()) {
    test(
      'geometry buffer allocation requires a GPU context',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  group('createGeometryBuffers', () {
    test('gives each role the storage its backend allocates', () {
      final buffers = gpu.createGeometryBuffers(64, 32);

      if (kIsWeb) {
        // WebGL2 types a buffer on first bind, so the roles cannot share one.
        expect(identical(buffers.vertex, buffers.index), isFalse);
        expect(buffers.indexBaseOffset, 0);
        expect(buffers.vertex.sizeInBytes, 64);
        expect(buffers.index.sizeInBytes, 32);
      } else {
        expect(identical(buffers.vertex, buffers.index), isTrue);
        expect(buffers.indexBaseOffset, 64);
        expect(buffers.vertex.sizeInBytes, 96);
      }
    });

    test(
      'sizes the buffer for vertex data alone when there are no indices',
      () {
        final buffers = gpu.createGeometryBuffers(64, 0);

        expect(identical(buffers.vertex, buffers.index), isTrue);
        expect(buffers.vertex.sizeInBytes, 64);
      },
    );
  });

  group('writeGeometryData', () {
    test('takes a stream as a float, integer, or byte list alike', () {
      final buffers = gpu.createGeometryBuffers(64, 16);

      expect(
        gpu.writeGeometryData(
          buffers.vertex,
          Float32List(16),
          destinationOffsetInBytes: 0,
        ),
        isTrue,
      );
      expect(
        gpu.writeGeometryData(
          buffers.index,
          Uint16List(8),
          destinationOffsetInBytes: buffers.indexBaseOffset,
        ),
        isTrue,
      );
      expect(
        gpu.writeGeometryData(
          buffers.vertex,
          ByteData(64),
          destinationOffsetInBytes: 0,
        ),
        isTrue,
      );
    });

    test('refuses a write that runs past the end of the buffer', () {
      final buffers = gpu.createGeometryBuffers(64, 0);

      expect(
        gpu.writeGeometryData(
          buffers.vertex,
          Float32List(17),
          destinationOffsetInBytes: 0,
        ),
        isFalse,
      );
    });
  });

  group('upload', () {
    test('binds the indices where its backend put them', () {
      final geometry = _upload(indices: Uint16List.fromList([0, 1, 2]));

      expect(geometry.streams, isNotEmpty);
      expect(geometry.indices, isNotNull);
      expect(geometry.indices!.lengthInBytes, 6);
      _expectIndexPlacement(geometry);
    });

    test('lays the vertex streams out back to back from offset zero', () {
      final geometry = _upload();

      var offset = 0;
      for (final stream in geometry.streams) {
        expect(stream.offsetInBytes, offset);
        offset += stream.lengthInBytes;
      }
      expect(geometry.indices, isNull);
    });

    test('takes 32-bit indices as a Uint32List', () {
      final geometry = _upload(
        indices: Uint32List.fromList([0, 1, 2]),
        indexType: gpu.IndexType.int32,
      );

      expect(geometry.indices!.lengthInBytes, 12);
      expect(geometry.indexType, gpu.IndexType.int32);
    });

    test('takes indices as ByteData as well', () {
      final geometry = _upload(
        indices: ByteData.sublistView(Uint16List.fromList([0, 1, 2])),
      );

      expect(geometry.indices!.lengthInBytes, 6);
      _expectIndexPlacement(geometry);
    });

    test('an arena allocation stays one contiguous block', () {
      final arena = GeometryBufferArena();
      final geometry = _upload(
        indices: Uint16List.fromList([0, 1, 2]),
        bufferArena: arena,
      );

      final base = geometry.streams.first.offsetInBytes;
      expect(arena.bufferCount, 1);
      // One allocation for the whole upload (the arena aligns its tail).
      expect(
        arena.usedInBytes,
        greaterThanOrEqualTo(_streamBytes(geometry) + 6),
      );
      for (final stream in geometry.streams) {
        expect(identical(stream.buffer, geometry.indices!.buffer), isTrue);
      }
      expect(geometry.indices!.offsetInBytes, base + _streamBytes(geometry));
    });
  });

  group('uploadVertexData element types', () {
    // An upload must accept the element type its data was packed as, since
    // that is what makes the web crossing cheap, and lay it out identically
    // whichever type it arrives as.
    test('lays a Float32List out exactly like the same bytes as ByteData', () {
      final floats = Float32List(3 * kUnskinnedPerVertexSize ~/ 4);
      for (var i = 0; i < floats.length; i++) {
        floats[i] = i.toDouble();
      }

      final fromFloats = _RecordingGeometry()
        ..uploadVertexData(floats, 3, Uint16List.fromList([0, 1, 2]));
      final fromBytes = _RecordingGeometry()
        ..uploadVertexData(
          ByteData.sublistView(floats),
          3,
          ByteData.sublistView(Uint16List.fromList([0, 1, 2])),
        );

      expect(
        fromFloats.streams.map((v) => (v.offsetInBytes, v.lengthInBytes)),
        fromBytes.streams.map((v) => (v.offsetInBytes, v.lengthInBytes)),
      );
      expect(
        fromFloats.indices!.offsetInBytes,
        fromBytes.indices!.offsetInBytes,
      );
      expect(
        fromFloats.indices!.lengthInBytes,
        fromBytes.indices!.lengthInBytes,
      );
    });

    test('retains CPU data whichever element type it was given', () {
      final floats = Float32List(3 * kUnskinnedPerVertexSize ~/ 4);

      final geometry = _RecordingGeometry()
        ..uploadVertexData(floats, 3, Uint16List.fromList([0, 1, 2]));

      expect(geometry.isReadable, isTrue);
    });
  });
}
