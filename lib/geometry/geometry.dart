import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/conversions.dart';
import 'package:flutter_scene/shaders.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:flutter_scene/generated/scene_impeller.fb_flatbuffers.dart'
    as fb;

abstract class Geometry {
  gpu.BufferView? _vertices;
  int _vertexCount = 0;

  gpu.BufferView? _indices;
  gpu.IndexType _indexType = gpu.IndexType.int16;
  int _indexCount = 0;

  gpu.Shader? _vertexShader;
  gpu.Shader get vertexShader {
    if (_vertexShader == null) {
      throw Exception('Vertex shader has not been set');
    }
    return _vertexShader!;
  }

  static Geometry fromFlatbuffer(fb.MeshPrimitive fbPrimitive) {
    gpu.IndexType indexType = fbPrimitive.indices!.type.toIndexType();

    Uint8List indices = Uint8List.fromList(fbPrimitive.indices!.data!);
    Float32List vertices;
    int verticesCount = 0;
    bool isSkinned = false;

    if (fbPrimitive.vertices! is fb.UnskinnedVertexBuffer) {
      fb.UnskinnedVertexBuffer unskinned =
          (fbPrimitive.vertices as fb.UnskinnedVertexBuffer?)!;
      // TODO(bdero): This is awful. 🤮 Add a way to grab a ByteData for lists of structs...
      //              https://github.com/google/flatbuffers/issues/8183
      // position: 3, normal: 3, tangent: 4, textureCoords: 2, color: 4 :: 16 floats
      verticesCount = unskinned.vertices!.length;
      int size = verticesCount * 16;
      vertices = Float32List(size);
      for (int i = 0; i < verticesCount; i++) {
        int offset = i * 16;
        vertices[offset + 0] = unskinned.vertices![i].position.x;
        vertices[offset + 1] = unskinned.vertices![i].position.y;
        vertices[offset + 2] = unskinned.vertices![i].position.z;
        vertices[offset + 3] = unskinned.vertices![i].normal.x;
        vertices[offset + 4] = unskinned.vertices![i].normal.y;
        vertices[offset + 5] = unskinned.vertices![i].normal.z;
        vertices[offset + 6] = unskinned.vertices![i].tangent.x;
        vertices[offset + 7] = unskinned.vertices![i].tangent.y;
        vertices[offset + 8] = unskinned.vertices![i].tangent.z;
        vertices[offset + 9] = unskinned.vertices![i].tangent.w;
        vertices[offset + 10] = unskinned.vertices![i].textureCoords.x;
        vertices[offset + 11] = unskinned.vertices![i].textureCoords.y;
        vertices[offset + 12] = unskinned.vertices![i].color.r;
        vertices[offset + 13] = unskinned.vertices![i].color.g;
        vertices[offset + 14] = unskinned.vertices![i].color.b;
        vertices[offset + 15] = unskinned.vertices![i].color.a;
      }
      isSkinned = false;
    } else if (fbPrimitive.vertices! is fb.SkinnedVertexBuffer) {
      fb.SkinnedVertexBuffer skinned =
          (fbPrimitive.vertices as fb.SkinnedVertexBuffer?)!;
      // TODO(bdero): This is awful. 🤮 Add a way to grab a ByteData for lists of structs...
      //              https://github.com/google/flatbuffers/issues/8183
      // vertex: 16, joints: 4, weights: 4 :: 24 floats
      verticesCount = skinned.vertices!.length;
      int size = verticesCount * 24;
      vertices = Float32List(size);
      for (int i = 0; i < verticesCount; i++) {
        int offset = i * 24;
        vertices[offset + 0] = skinned.vertices![i].vertex.position.x;
        vertices[offset + 1] = skinned.vertices![i].vertex.position.y;
        vertices[offset + 2] = skinned.vertices![i].vertex.position.z;
        vertices[offset + 3] = skinned.vertices![i].vertex.normal.x;
        vertices[offset + 4] = skinned.vertices![i].vertex.normal.y;
        vertices[offset + 5] = skinned.vertices![i].vertex.normal.z;
        vertices[offset + 6] = skinned.vertices![i].vertex.tangent.x;
        vertices[offset + 7] = skinned.vertices![i].vertex.tangent.y;
        vertices[offset + 8] = skinned.vertices![i].vertex.tangent.z;
        vertices[offset + 9] = skinned.vertices![i].vertex.tangent.w;
        vertices[offset + 10] = skinned.vertices![i].vertex.textureCoords.x;
        vertices[offset + 11] = skinned.vertices![i].vertex.textureCoords.y;
        vertices[offset + 12] = skinned.vertices![i].vertex.color.r;
        vertices[offset + 13] = skinned.vertices![i].vertex.color.g;
        vertices[offset + 14] = skinned.vertices![i].vertex.color.b;
        vertices[offset + 15] = skinned.vertices![i].vertex.color.a;
        vertices[offset + 16] = skinned.vertices![i].joints.x;
        vertices[offset + 17] = skinned.vertices![i].joints.y;
        vertices[offset + 18] = skinned.vertices![i].joints.z;
        vertices[offset + 19] = skinned.vertices![i].joints.w;
        vertices[offset + 20] = skinned.vertices![i].weights.x;
        vertices[offset + 21] = skinned.vertices![i].weights.y;
        vertices[offset + 22] = skinned.vertices![i].weights.z;
        vertices[offset + 23] = skinned.vertices![i].weights.w;
      }
      isSkinned = true;
    } else {
      throw Exception('Unknown vertex buffer type');
    }

    gpu.DeviceBuffer? buffer = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        vertices.lengthInBytes + indices.lengthInBytes);
    if (buffer == null) {
      throw Exception('Failed to allocate geometry buffer');
    }
    buffer.overwrite(vertices.buffer.asByteData(), destinationOffsetInBytes: 0);
    buffer.overwrite(indices.buffer.asByteData(),
        destinationOffsetInBytes: vertices.lengthInBytes);

    Geometry geometry = UnskinnedGeometry();
    geometry.uploadVertexData(vertices.buffer.asByteData(), verticesCount,
        indices.buffer.asByteData(),
        indexType: indexType);
    return geometry;
  }

  void setVertices(gpu.BufferView vertices, int vertexCount) {
    _vertices = vertices;
    _vertexCount = vertexCount;
  }

  void setIndices(gpu.BufferView indices, gpu.IndexType indexType) {
    _indices = indices;
    _indexType = indexType;
    switch (indexType) {
      case gpu.IndexType.int16:
        _indexCount = indices.lengthInBytes ~/ 2;
      case gpu.IndexType.int32:
        _indexCount = indices.lengthInBytes ~/ 4;
    }
  }

  void uploadVertexData(ByteData vertices, int vertexCount, ByteData? indices,
      {gpu.IndexType indexType = gpu.IndexType.int16}) {
    gpu.DeviceBuffer? deviceBuffer = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        indices == null
            ? vertices.lengthInBytes
            : vertices.lengthInBytes + indices!.lengthInBytes);

    if (deviceBuffer == null) {
      throw Exception('Failed to allocate geometry buffer');
    }

    deviceBuffer.overwrite(vertices, destinationOffsetInBytes: 0);
    setVertices(
        gpu.BufferView(deviceBuffer,
            offsetInBytes: 0, lengthInBytes: vertices.lengthInBytes),
        vertexCount);

    if (indices != null) {
      deviceBuffer.overwrite(indices,
          destinationOffsetInBytes: vertices.lengthInBytes);
      setIndices(
          gpu.BufferView(deviceBuffer,
              offsetInBytes: vertices.lengthInBytes,
              lengthInBytes: indices.lengthInBytes),
          indexType);
    }
  }

  void setVertexShader(gpu.Shader shader) {
    _vertexShader = shader;
  }

  @mustCallSuper
  void bind(
      gpu.RenderPass pass, gpu.HostBuffer transientsBuffer, vm.Matrix4 mvp) {
    if (_vertices == null) {
      throw Exception(
          'SetBuffer must be called before GetBufferView for Geometry.');
    }

    pass.bindVertexBuffer(_vertices!, _vertexCount);
    if (_indices != null) {
      pass.bindIndexBuffer(_indices!, _indexType, _indexCount);
    }

    final mvpSlot = vertexShader.getUniformSlot('FrameInfo');
    final mvpView = transientsBuffer.emplace(mvp.storage.buffer.asByteData());
    pass.bindUniform(mvpSlot, mvpView);
  }
}

class UnskinnedGeometry extends Geometry {
  UnskinnedGeometry() {
    setVertexShader(baseShaderLibrary['UnskinnedVertex']!);
  }
}

class CuboidGeometry extends UnskinnedGeometry {
  CuboidGeometry(vm.Vector3 extents) {
    final e = extents / 2;
    // Layout: Position, normal, tangent, uv, color
    final vertices = Float32List.fromList(<double>[
      -e.x, -e.y, -e.z, /* */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 0, 0, /* */ 1,
      0, 0, 1, //
      e.x, -e.y, -e.z, /*  */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 1, 0, /* */ 0,
      1, 0, 1, //
      e.x, e.y, -e.z, /*   */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 1, 1, /* */ 0,
      0, 1, 1, //
      -e.x, e.y, -e.z, /*  */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 0, 1, /* */ 0,
      0, 0, 1, //
      -e.x, -e.y, e.z, /*  */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 0, 0, /* */ 0,
      1, 1, 1, //
      e.x, -e.y, e.z, /*   */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 1, 0, /* */ 1,
      0, 1, 1, //
      e.x, e.y, e.z, /*    */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 1, 1, /* */ 1,
      1, 0, 1, //
      -e.x, e.y, e.z, /*   */ 0, 0, -1, /* */ 1, 0, 0, 0, /* */ 0, 1, /* */ 1,
      1, 1, 1, //
    ]);

    final indices = Uint16List.fromList(<int>[
      0, 1, 3, 3, 1, 2, //
      1, 5, 2, 2, 5, 6, //
      5, 4, 6, 6, 4, 7, //
      4, 0, 7, 7, 0, 3, //
      3, 2, 7, 7, 2, 6, //
      4, 5, 0, 0, 5, 1, //
    ]);

    uploadVertexData(
        vertices.buffer.asByteData(), 8, indices.buffer.asByteData(),
        indexType: gpu.IndexType.int16);
  }
}
