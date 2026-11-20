// ignore_for_file: implementation_imports

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

Future<bool> _gpuAvailable() async {
  try {
    await gpu.initializeGpuBackend();
    final buffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      4,
    );
    gpu.gpuHost.releaseBuffer(buffer);
    return true;
  } catch (_) {
    return false;
  }
}

class _RecordingGeometry extends MeshGeometry {
  _RecordingGeometry(MeshData data)
    : super.fromArrays(
        positions: data.positions,
        normals: data.normals,
        texCoords: data.texCoords,
        texCoords1: data.texCoords1,
        colors: data.colors,
        tangents: data.tangents,
        indices: data.indices,
        storage: GeometryStorage.updatable,
      );

  List<gpu.BufferView> streams = const [];
  int streamBindings = 0;

  @override
  void setVertexStreams(List<gpu.BufferView> streams, int vertexCount) {
    this.streams = streams;
    streamBindings++;
    super.setVertexStreams(streams, vertexCount);
  }
}

typedef _Update =
    void Function(Float32List values, {int? dirtyStart, int? dirtyCount});

final _attributes =
    <
      ({
        String name,
        int components,
        Float32List Function(MeshData) read,
        _Update Function(MeshGeometry) bind,
      })
    >[
      (
        name: 'positions',
        components: 3,
        read: (data) => data.positions,
        bind: (geometry) => geometry.updatePositions,
      ),
      (
        name: 'normals',
        components: 3,
        read: (data) => data.normals!,
        bind: (geometry) => geometry.updateNormals,
      ),
      (
        name: 'texCoords',
        components: 2,
        read: (data) => data.texCoords!,
        bind: (geometry) => geometry.updateTexCoords,
      ),
      (
        name: 'texCoords1',
        components: 2,
        read: (data) => data.texCoords1!,
        bind: (geometry) => geometry.updateTexCoords1,
      ),
      (
        name: 'colors',
        components: 4,
        read: (data) => data.colors!,
        bind: (geometry) => geometry.updateColors,
      ),
      (
        name: 'tangents',
        components: 4,
        read: (data) => data.tangents!,
        bind: (geometry) => geometry.updateTangents,
      ),
    ];

Float32List _values(int length, double offset) =>
    Float32List.fromList(List.generate(length, (index) => offset + index / 4));

MeshData _data() => MeshData(
  positions: _values(9, 0),
  vertexCount: 3,
  normals: _values(9, 10),
  texCoords: _values(6, 20),
  texCoords1: _values(6, 30),
  colors: _values(12, 40),
  tangents: _values(12, 50),
  indices: Uint16List.fromList([0, 1, 2]),
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _gpuAvailable() ? false : 'Requires a GPU device.';

  group('MeshGeometry update snapshots', skip: skip, () {
    test('construction owns all input attributes', () {
      final input = _data();
      final geometry = MeshGeometry.fromMeshData(
        input,
        storage: GeometryStorage.updatable,
      );
      final expected = geometry.extractMeshData();
      for (final attribute in _attributes) {
        final values = attribute.read(input);
        values.fillRange(0, values.length, -100);
      }
      final actual = geometry.extractMeshData();
      for (final attribute in _attributes) {
        expect(
          attribute.read(actual),
          orderedEquals(attribute.read(expected)),
          reason: attribute.name,
        );
      }
    });

    for (final attribute in _attributes) {
      test('${attribute.name} rejects invalid hints without changing data', () {
        final geometry = _RecordingGeometry(_data());
        final update = attribute.bind(geometry);
        final before = geometry.extractMeshData();
        final packed = geometry.packedData;
        final packedBytes = Uint8List.fromList(packed.vertexBytes);
        final soa = geometry.soaData;
        final streams = geometry.streams;
        final streamViews = List<gpu.BufferView>.of(streams);
        final streamBindings = geometry.streamBindings;
        final bounds = geometry.localBounds!;
        final boundsMin = bounds.min.storage.toList();
        final boundsMax = bounds.max.storage.toList();
        final sphere = geometry.localBoundingSphere!;
        final sphereCenter = sphere.center.storage.toList();
        final sphereRadius = sphere.radius;
        final boundsVersion = geometry.localBoundsVersion;
        final input = _values(3 * attribute.components, 900);

        for (final range in <(int?, int?)>[
          (-1, null),
          (null, -1),
          (null, 4),
          (3, 1),
          (4, 0),
          (4, null),
        ]) {
          expect(
            () => update(input, dirtyStart: range.$1, dirtyCount: range.$2),
            throwsRangeError,
          );
          final actual = geometry.extractMeshData();
          for (final other in _attributes) {
            expect(other.read(actual), orderedEquals(other.read(before)));
          }
          expect(actual.indices, before.indices);
          expect(actual.vertexCount, before.vertexCount);
          expect(geometry.packedData.vertexBytes, same(packed.vertexBytes));
          expect(geometry.packedData.vertexBytes, orderedEquals(packedBytes));
          expect(geometry.packedData.indexBytes, same(packed.indexBytes));
          expect(geometry.packedData.indices32Bit, packed.indices32Bit);
          expect(geometry.soaData.vertexBytes, orderedEquals(soa.vertexBytes));
          expect(geometry.streams, same(streams));
          expect(geometry.streams.length, streamViews.length);
          for (var i = 0; i < streamViews.length; i++) {
            expect(geometry.streams[i], same(streamViews[i]));
          }
          expect(geometry.streamBindings, streamBindings);
          expect(geometry.localBounds, same(bounds));
          expect(geometry.localBounds!.min.storage, orderedEquals(boundsMin));
          expect(geometry.localBounds!.max.storage, orderedEquals(boundsMax));
          expect(geometry.localBoundingSphere, same(sphere));
          expect(sphere.center.storage, orderedEquals(sphereCenter));
          expect(sphere.radius, sphereRadius);
          expect(geometry.localBoundsVersion, boundsVersion);
        }

        update(input);
        expect(
          attribute.read(geometry.extractMeshData()),
          orderedEquals(input),
        );
        expect(
          geometry.packedData.vertexBytes,
          isNot(same(packed.vertexBytes)),
        );
      });

      test('${attribute.name} isolates inputs and earlier snapshots', () {
        final geometry = MeshGeometry.fromMeshData(
          _data(),
          storage: GeometryStorage.updatable,
        );
        final update = attribute.bind(geometry);
        final before = geometry.extractMeshData();
        final original = Float32List.fromList(attribute.read(before));
        final input = _values(3 * attribute.components, 100);
        final expected = Float32List.fromList(input);

        update(input);
        final first = geometry.extractMeshData();
        input.fillRange(0, input.length, -1);
        expect(
          attribute.read(geometry.extractMeshData()),
          orderedEquals(expected),
        );
        expect(attribute.read(before), orderedEquals(original));

        final replacement = _values(input.length, 200);
        update(replacement);
        expect(attribute.read(first), orderedEquals(expected));
        expect(attribute.read(before), orderedEquals(original));
        expect(
          attribute.read(geometry.extractMeshData()),
          orderedEquals(replacement),
        );

        attribute.read(first).fillRange(0, expected.length, -2);
        expect(
          attribute.read(geometry.extractMeshData()),
          orderedEquals(replacement),
        );
      });

      test('${attribute.name} copies a full subview with a dirty hint', () {
        final geometry = MeshGeometry.fromMeshData(
          _data(),
          storage: GeometryStorage.updatable,
        );
        final length = 3 * attribute.components;
        final backing = Float32List(length + 4)..fillRange(0, length + 4, -10);
        final input = Float32List.sublistView(backing, 2, length + 2)
          ..setAll(0, _values(length, 300));
        final expected = Float32List.fromList(input);
        final update = attribute.bind(geometry);

        expect(input.offsetInBytes, greaterThan(0));
        update(input, dirtyStart: 1, dirtyCount: 1);
        final snapshot = geometry.extractMeshData();
        expect(attribute.read(snapshot), orderedEquals(expected));
        if (attribute.name == 'positions') {
          expect(geometry.localBounds!.min.storage, expected.sublist(0, 3));
          expect(geometry.localBounds!.max.storage, expected.sublist(6, 9));
        }

        backing.fillRange(0, backing.length, -20);
        expect(
          attribute.read(geometry.extractMeshData()),
          orderedEquals(expected),
        );
        update(_values(length, 400), dirtyStart: 1, dirtyCount: 1);
        expect(attribute.read(snapshot), orderedEquals(expected));
      });
    }
  });
}
