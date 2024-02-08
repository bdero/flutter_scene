import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

class Geometry {
  ByteBuffer? _vertices;
  int _vertexCount = 0;

  ByteBuffer? _indices;
  gpu.IndexType _indexType = gpu.IndexType.int16;
  int _indexCount = 0;

  gpu.DeviceBuffer? _deviceBuffer;

  // TODO(bdero): This should have an attribute map instead and be fully SoA,
  //              but vertex attributes in Impeller aren't flexible enough yet.
  //              See also https://github.com/flutter/flutter/issues/139560.
  void setVertices(ByteBuffer vertices, int strideInBytes) {
    _vertices = vertices;
    _vertexCount = vertices.lengthInBytes ~/ strideInBytes;
    _deviceBuffer = null;
  }

  void setIndices(ByteBuffer indices, gpu.IndexType indexType) {
    _indices = indices;
    _indexType = indexType;
    switch (indexType) {
      case gpu.IndexType.int16:
        _indexCount = indices.lengthInBytes ~/ 2;
      case gpu.IndexType.int32:
        _indexCount = indices.lengthInBytes ~/ 4;
    }
  }

  void bind(gpu.RenderPass pass) {
    if (_vertices == null) {
      throw Exception(
          'SetBuffer must be called before GetBufferView for Geometry.');
    }

    _deviceBuffer ??= gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        _indices == null
            ? _vertices!.lengthInBytes
            : _vertices!.lengthInBytes + _indices!.lengthInBytes);

    _deviceBuffer?.overwrite(_vertices!.asByteData());
    pass.bindVertexBuffer(
        gpu.BufferView(_deviceBuffer!,
            offsetInBytes: 0, lengthInBytes: _vertices!.lengthInBytes),
        _vertexCount);

    if (_indices != null) {
      _deviceBuffer?.overwrite(_indices!.asByteData(),
          destinationOffsetInBytes: _vertices!.lengthInBytes);
      pass.bindIndexBuffer(
          gpu.BufferView(_deviceBuffer!,
              offsetInBytes: _vertices!.lengthInBytes,
              lengthInBytes: _indices!.lengthInBytes),
          _indexType,
          _indexCount);
    }
  }
}

class CuboidGeometry extends Geometry {
  CuboidGeometry(vm.Vector3 extents) {
    final e = extents / 2;

    final vertices = Float32List.fromList(<double>[
      -e.x, -e.y, -e.z, /* */ 0, 0, /* */ 1, 0, 0, 1, //
      e.x, -e.y, -e.z, /*  */ 1, 0, /* */ 0, 1, 0, 1, //
      e.x, e.y, -e.z, /*   */ 1, 1, /* */ 0, 0, 1, 1, //
      -e.x, e.y, -e.z, /*  */ 0, 1, /* */ 0, 0, 0, 1, //
      -e.x, -e.y, e.z, /*  */ 0, 0, /* */ 0, 1, 1, 1, //
      e.x, -e.y, e.z, /*   */ 1, 0, /* */ 1, 0, 1, 1, //
      e.x, e.y, e.z, /*    */ 1, 1, /* */ 1, 1, 0, 1, //
      -e.x, e.y, e.z, /*   */ 0, 1, /* */ 1, 1, 1, 1, //
    ]);
    setVertices(vertices.buffer, 36);

    final indices = Uint16List.fromList(<int>[
      0, 1, 3, 3, 1, 2, //
      1, 5, 2, 2, 5, 6, //
      5, 4, 6, 6, 4, 7, //
      4, 0, 7, 7, 0, 3, //
      3, 2, 7, 7, 2, 6, //
      4, 5, 0, 0, 5, 1, //
    ]);
    setIndices(indices.buffer, gpu.IndexType.int16);
  }
}
