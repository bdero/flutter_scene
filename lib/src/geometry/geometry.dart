import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene_importer/constants.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

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
    Uint8List vertices;
    bool isSkinned =
        fbPrimitive.vertices!.runtimeType == fb.SkinnedVertexBuffer;
    int perVertexBytes =
        isSkinned ? kSkinnedPerVertexSize : kUnskinnedPerVertexSize;

    switch (fbPrimitive.vertices!.runtimeType) {
      case const (fb.UnskinnedVertexBuffer):
        fb.UnskinnedVertexBuffer unskinned =
            (fbPrimitive.vertices as fb.UnskinnedVertexBuffer?)!;
        vertices = unskinned.vertices! as Uint8List;
      case const (fb.SkinnedVertexBuffer):
        fb.SkinnedVertexBuffer skinned =
            (fbPrimitive.vertices as fb.SkinnedVertexBuffer?)!;
        vertices = skinned.vertices! as Uint8List;
      default:
        throw Exception('Unknown vertex buffer type');
    }

    if (vertices.length % perVertexBytes != 0) {
      debugPrint(
        'OH NO: Encountered an vertex buffer of size '
        '${vertices.lengthInBytes} bytes, which doesn\'t match the '
        'expected multiple of $perVertexBytes bytes. Possible data corruption! '
        'Attempting to use a vertex count of ${vertices.length ~/ perVertexBytes}. '
        'The last ${vertices.length % perVertexBytes} bytes will be ignored.',
      );
    }
    int vertexCount = vertices.length ~/ perVertexBytes;

    gpu.IndexType indexType = fbPrimitive.indices!.type.toIndexType();
    Uint8List indices = fbPrimitive.indices!.data! as Uint8List;

    Geometry geometry;
    switch (fbPrimitive.vertices!.runtimeType) {
      case const (fb.UnskinnedVertexBuffer):
        geometry = UnskinnedGeometry();
      case const (fb.SkinnedVertexBuffer):
        geometry = SkinnedGeometry();
      default:
        throw Exception('Unknown vertex buffer type');
    }

    geometry.uploadVertexData(
      ByteData.sublistView(vertices),
      vertexCount,
      ByteData.sublistView(indices),
      indexType: indexType,
    );
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

  void uploadVertexData(
    ByteData vertices,
    int vertexCount,
    ByteData? indices, {
    gpu.IndexType indexType = gpu.IndexType.int16,
  }) {
    gpu.DeviceBuffer deviceBuffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      indices == null
          ? vertices.lengthInBytes
          : vertices.lengthInBytes + indices.lengthInBytes,
    );

    deviceBuffer.overwrite(vertices, destinationOffsetInBytes: 0);
    setVertices(
      gpu.BufferView(
        deviceBuffer,
        offsetInBytes: 0,
        lengthInBytes: vertices.lengthInBytes,
      ),
      vertexCount,
    );

    if (indices != null) {
      deviceBuffer.overwrite(
        indices,
        destinationOffsetInBytes: vertices.lengthInBytes,
      );
      setIndices(
        gpu.BufferView(
          deviceBuffer,
          offsetInBytes: vertices.lengthInBytes,
          lengthInBytes: indices.lengthInBytes,
        ),
        indexType,
      );
    }
  }

  void setVertexShader(gpu.Shader shader) {
    _vertexShader = shader;
  }

  void setJointsTexture(gpu.Texture? texture, int width) {}

  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  );
}

class UnskinnedGeometry extends Geometry {
  UnskinnedGeometry() {
    setVertexShader(baseShaderLibrary['UnskinnedVertex']!);
  }

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  ) {
    if (_vertices == null) {
      throw Exception(
        'SetVertices must be called before GetBufferView for Geometry.',
      );
    }

    pass.bindVertexBuffer(_vertices!, _vertexCount);
    if (_indices != null) {
      pass.bindIndexBuffer(_indices!, _indexType, _indexCount);
    }

    // Unskinned vertex UBO.
    final frameInfoSlot = vertexShader.getUniformSlot('FrameInfo');
    final frameInfoFloats = Float32List.fromList([
      modelTransform.storage[0],
      modelTransform.storage[1],
      modelTransform.storage[2],
      modelTransform.storage[3],
      modelTransform.storage[4],
      modelTransform.storage[5],
      modelTransform.storage[6],
      modelTransform.storage[7],
      modelTransform.storage[8],
      modelTransform.storage[9],
      modelTransform.storage[10],
      modelTransform.storage[11],
      modelTransform.storage[12],
      modelTransform.storage[13],
      modelTransform.storage[14],
      modelTransform.storage[15],
      cameraTransform.storage[0],
      cameraTransform.storage[1],
      cameraTransform.storage[2],
      cameraTransform.storage[3],
      cameraTransform.storage[4],
      cameraTransform.storage[5],
      cameraTransform.storage[6],
      cameraTransform.storage[7],
      cameraTransform.storage[8],
      cameraTransform.storage[9],
      cameraTransform.storage[10],
      cameraTransform.storage[11],
      cameraTransform.storage[12],
      cameraTransform.storage[13],
      cameraTransform.storage[14],
      cameraTransform.storage[15],
      cameraPosition.x,
      cameraPosition.y,
      cameraPosition.z,
    ]);
    final frameInfoView = transientsBuffer.emplace(
      frameInfoFloats.buffer.asByteData(),
    );
    pass.bindUniform(frameInfoSlot, frameInfoView);
  }
}

class SkinnedGeometry extends Geometry {
  gpu.Texture? _jointsTexture;
  int _jointsTextureWidth = 0;

  SkinnedGeometry() {
    setVertexShader(baseShaderLibrary['SkinnedVertex']!);
  }

  @override
  void setJointsTexture(gpu.Texture? texture, int width) {
    _jointsTexture = texture;
    _jointsTextureWidth = width;
  }

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition,
  ) {
    if (_jointsTexture == null) {
      throw Exception('Joints texture must be set for skinned geometry.');
    }

    pass.bindTexture(
      vertexShader.getUniformSlot('joints_texture'),
      _jointsTexture!,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        mipFilter: gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );

    if (_vertices == null) {
      throw Exception(
        'SetVertices must be called before GetBufferView for Geometry.',
      );
    }

    pass.bindVertexBuffer(_vertices!, _vertexCount);
    if (_indices != null) {
      pass.bindIndexBuffer(_indices!, _indexType, _indexCount);
    }

    // Skinned vertex UBO.
    final frameInfoSlot = vertexShader.getUniformSlot('FrameInfo');
    final frameInfoFloats = Float32List.fromList([
      modelTransform.storage[0],
      modelTransform.storage[1],
      modelTransform.storage[2],
      modelTransform.storage[3],
      modelTransform.storage[4],
      modelTransform.storage[5],
      modelTransform.storage[6],
      modelTransform.storage[7],
      modelTransform.storage[8],
      modelTransform.storage[9],
      modelTransform.storage[10],
      modelTransform.storage[11],
      modelTransform.storage[12],
      modelTransform.storage[13],
      modelTransform.storage[14],
      modelTransform.storage[15],
      cameraTransform.storage[0],
      cameraTransform.storage[1],
      cameraTransform.storage[2],
      cameraTransform.storage[3],
      cameraTransform.storage[4],
      cameraTransform.storage[5],
      cameraTransform.storage[6],
      cameraTransform.storage[7],
      cameraTransform.storage[8],
      cameraTransform.storage[9],
      cameraTransform.storage[10],
      cameraTransform.storage[11],
      cameraTransform.storage[12],
      cameraTransform.storage[13],
      cameraTransform.storage[14],
      cameraTransform.storage[15],
      cameraPosition.x,
      cameraPosition.y,
      cameraPosition.z,
      _jointsTexture != null ? 1 : 0,
      _jointsTexture != null ? _jointsTextureWidth.toDouble() : 1.0,
    ]);
    final frameInfoView = transientsBuffer.emplace(
      frameInfoFloats.buffer.asByteData(),
    );
    pass.bindUniform(frameInfoSlot, frameInfoView);
  }
}

class CuboidGeometry extends UnskinnedGeometry {
  CuboidGeometry(vm.Vector3 extents) {
    final e = extents / 2;
    // Layout: Position, normal, uv, color
    final vertices = Float32List.fromList(<double>[
      -e.x, -e.y, -e.z, /* */ 0, 0, -1, /* */ 0, 0, /* */ 1, 0, 0, 1, //
      e.x, -e.y, -e.z, /*  */ 0, 0, -1, /* */ 1, 0, /* */ 0, 1, 0, 1, //
      e.x, e.y, -e.z, /*   */ 0, 0, -1, /* */ 1, 1, /* */ 0, 0, 1, 1, //
      -e.x, e.y, -e.z, /*  */ 0, 0, -1, /* */ 0, 1, /* */ 0, 0, 0, 1, //
      -e.x, -e.y, e.z, /*  */ 0, 0, -1, /* */ 0, 0, /* */ 0, 1, 1, 1, //
      e.x, -e.y, e.z, /*   */ 0, 0, -1, /* */ 1, 0, /* */ 1, 0, 1, 1, //
      e.x, e.y, e.z, /*    */ 0, 0, -1, /* */ 1, 1, /* */ 1, 1, 0, 1, //
      -e.x, e.y, e.z, /*   */ 0, 0, -1, /* */ 0, 1, /* */ 1, 1, 1, 1, //
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
      ByteData.sublistView(vertices),
      8,
      ByteData.sublistView(indices),
      indexType: gpu.IndexType.int16,
    );
  }
}
