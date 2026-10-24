// 2D-array and 3D textures on the WebGPU backend, sampled through
// texture_2d_array and texture_3d bindings and read back.
//
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/webgpu/webgpu_data_texture_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' show PixelFormat;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _bundle = Uint8List.fromList(utf8.encode('data textures'));

const _vertexWgsl = '''
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) position : vec2<f32>) -> Out {
  return Out(vec4<f32>(position, 0.0, 1.0), position * 0.5 + 0.5);
}
''';

// [dimension] is the WGSL texture type; [coordinate] builds its sample
// coordinate (and array index) from `uv` and `params.at`.
String _fragmentWgsl(String dimension, String coordinate) =>
    '''
struct Params { at : vec4<f32> }
@group(0u) @binding(64u) var<uniform> params : Params;
@group(0u) @binding(65u) var data : $dimension<f32>;
@group(0u) @binding(193u) var data_sampler : sampler;
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  let texel = textureSample(data, data_sampler, $coordinate);
  return vec4<f32>(texel.r, texel.g, 0.0, 1.0);
}
''';

Map<String, Object?> _fragment(String wgsl) => {
  'stage': 'fragment',
  'entryPoint': 'main',
  'wgsl': wgsl,
  'inputs': [
    {'name': 'uv', 'location': 0, 'vecSize': 2, 'offset': 0},
  ],
  'uniforms': [
    {
      'name': 'Params',
      'group': 0,
      'binding': 64,
      'size': 16,
      'fields': [
        {'name': 'at', 'offset': 0},
      ],
    },
  ],
  'textures': [
    {'name': 'data', 'group': 0, 'binding': 65, 'sampler': 193},
  ],
};

String _sidecar() => jsonEncode({
  'format': 2,
  'translator': 'test',
  'bundle': sidecarBundleHash(_bundle),
  'shaders': {
    'QuadVertex': {
      'stage': 'vertex',
      'entryPoint': 'main',
      'wgsl': _vertexWgsl,
      'inputs': [
        {'name': 'position', 'location': 0, 'vecSize': 2, 'offset': 0},
      ],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
    'ArrayFragment': _fragment(
      _fragmentWgsl('texture_2d_array', 'uv, i32(params.at.x)'),
    ),
    'VolumeFragment': _fragment(
      _fragmentWgsl('texture_3d', 'vec3<f32>(uv, params.at.x)'),
    ),
  },
});

// The analyzer resolves package:flutter_scene/scene.dart against the native
// shim, while this test drives the web one; at runtime in a browser both are
// the web shim. These recover the web types for scene-level textures.
gpu.Texture _texture(Object texture) => texture as gpu.Texture;
gpu.SamplerOptions _sampler(Object sampler) => sampler as gpu.SamplerOptions;

void main() {
  if (!gpu.useWebGpuBackend) {
    test('needs --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGL2 in this build.');
    });
    return;
  }

  late gpu.ShaderLibrary library;
  late gpu.BufferView triangle;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    library = await webGpuShaderLibraryFromSidecar(_bundle, _sidecar());
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
    );
    triangle = gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 24);
  });

  Future<List<int>> sample(
    String fragmentName,
    gpu.Texture texture,
    double at, {
    gpu.SamplerOptions? sampler,
  }) async {
    final fragment = library[fragmentName]!;
    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      4,
      4,
    );
    final commands = gpu.gpuContext.createCommandBuffer();
    commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
      )
      ..bindPipeline(
        gpu.gpuContext.createRenderPipeline(library['QuadVertex']!, fragment),
      )
      ..bindVertexBuffer(triangle)
      ..bindUniform(
        fragment.getUniformSlot('Params'),
        gpu.gpuContext.createHostBuffer().emplace(
          ByteData.sublistView(Float32List.fromList([at, 0, 0, 0])),
        ),
      )
      ..bindTexture(
        fragment.getUniformSlot('data'),
        texture,
        sampler: sampler ?? gpu.SamplerOptions(),
      )
      ..draw(3);
    commands.submit();
    return (await webGpuReadTexture(target)).sublist(0, 4);
  }

  test('reports the device limits', () {
    final limits = gpu.gpuLimits;
    expect(limits.supportsTextureArrays, isTrue);
    expect(limits.supports3DTextures, isTrue);
    // WebGPU's guaranteed minimums.
    expect(limits.maxTextureSize, greaterThanOrEqualTo(8192));
    expect(limits.maxArrayLayers, greaterThanOrEqualTo(256));
    expect(limits.max3DTextureSize, greaterThanOrEqualTo(2048));
  });

  test('a 2D array samples each r8 layer', () async {
    final layers = Texture2DArray.fromLayers(
      [
        for (final value in [10, 120, 250])
          Uint8List(16)..fillRange(0, 16, value),
      ],
      width: 4,
      height: 4,
      format: PixelFormat.r8UNormInt,
    );
    for (final (layer, value) in [(0, 10), (1, 120), (2, 250)]) {
      final texel = await sample(
        'ArrayFragment',
        _texture(layers.gpuTexture),
        layer.toDouble(),
      );
      expect(texel[0], value, reason: 'layer $layer');
    }
  });

  test('a 3D texture filters linearly across depth slices', () async {
    final voxels = Uint8List(2 * 2 * 4);
    for (var z = 0; z < 4; z++) {
      voxels.fillRange(z * 4, z * 4 + 4, z * 80);
    }
    final volume = Texture3D.fromVoxels(
      voxels,
      width: 2,
      height: 2,
      depth: 4,
      format: PixelFormat.r8UNormInt,
    );
    expect(
      (await sample('VolumeFragment', _texture(volume.gpuTexture), 2.5 / 4))[0],
      160,
    );
    expect(
      (await sample(
        'VolumeFragment',
        _texture(volume.gpuTexture),
        2.0 / 4,
        sampler: _sampler(volume.sampledSampler),
      ))[0],
      closeTo(120, 1),
    );
  });
}
