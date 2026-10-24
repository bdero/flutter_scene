// 2D-array and 3D textures on the WebGL2 backend: uploaded a layer or slice
// at a time, sampled through sampler2DArray and sampler3D in a bundle compiled
// by impellerc, and read back.
//
//   flutter test --platform chrome test/gpu/data_texture_webgl_browser_test.dart
//
// Skips under the WebGPU define, since the shim is not WebGL2 then.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/gpu.dart' show PixelFormat;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/data_textures/data_textures_bundle.dart';

// The analyzer resolves package:flutter_scene/scene.dart against the native
// shim, while this test drives the web one; at runtime in a browser both are
// the web shim. These recover the web types for scene-level textures.
gpu.Texture _texture(Object texture) => texture as gpu.Texture;
gpu.SamplerOptions _sampler(Object sampler) => sampler as gpu.SamplerOptions;

void main() {
  if (gpu.useWebGpuBackend) {
    test('runs without --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  late gpu.ShaderLibrary library;
  late gpu.DeviceBuffer triangle;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    library = (await gpu.loadShaderLibraryFromBytesAsync(
      ByteData.sublistView(base64Decode(dataTexturesBundleBase64)),
    ))!;
    triangle = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
    );
  });

  /// Fills a 4x4 target sampling [texture] through [fragmentName] with the
  /// uniform [block] set to [coordinate], and returns its first texel.
  Future<List<int>> sample(
    String fragmentName,
    String block,
    gpu.Texture texture,
    String samplerName,
    double coordinate, {
    gpu.SamplerOptions? sampler,
  }) async {
    final fragment = library[fragmentName]!;
    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      4,
      4,
    );
    final commands = gpu.gpuContext.createCommandBuffer();
    final pass = commands.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    pass
      ..bindPipeline(
        gpu.gpuContext.createRenderPipeline(library['QuadVertex']!, fragment),
      )
      ..bindVertexBuffer(
        gpu.BufferView(triangle, offsetInBytes: 0, lengthInBytes: 24),
      )
      ..bindUniform(
        fragment.getUniformSlot(block),
        gpu.gpuContext.createHostBuffer().emplace(
          ByteData.sublistView(Float32List.fromList([coordinate, 0, 0, 0])),
        ),
      )
      ..bindTexture(
        fragment.getUniformSlot(samplerName),
        texture,
        sampler: sampler ?? gpu.SamplerOptions(),
      )
      ..draw(3);
    commands.submit();
    final image = target.asImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return bytes.buffer.asUint8List(0, 4);
  }

  test('reports the WebGL2 limits', () {
    final limits = gpu.gpuLimits;
    expect(limits.supportsTextureArrays, isTrue);
    expect(limits.supports3DTextures, isTrue);
    // WebGL2's guaranteed minimums.
    expect(limits.maxArrayLayers, greaterThanOrEqualTo(256));
    expect(limits.max3DTextureSize, greaterThanOrEqualTo(256));
    expect(limits.maxTextureSize, greaterThanOrEqualTo(2048));
    expect(Texture3D.isSupported, isTrue);
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
        'ArrayParams',
        _texture(layers.gpuTexture),
        'layers',
        layer.toDouble(),
      );
      expect(texel[0], value, reason: 'layer $layer');
    }
  });

  test('a 3D texture filters linearly across depth slices', () async {
    // Four r8 slices of 0, 80, 160 and 240. Halfway between the centers of
    // slices 1 and 2, a linear sampler returns their mean.
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
    expect(volume.byteSize, 16);
    expect(gpu.isTexture3D(_texture(volume.gpuTexture)), isTrue);
    final nearest = await sample(
      'VolumeFragment',
      'VolumeParams',
      _texture(volume.gpuTexture),
      'volume',
      2.5 / 4,
    );
    expect(nearest[0], 160);
    final linear = await sample(
      'VolumeFragment',
      'VolumeParams',
      _texture(volume.gpuTexture),
      'volume',
      2.0 / 4,
      sampler: _sampler(volume.sampledSampler),
    );
    expect(linear[0], closeTo(120, 1));
  });

  test('a 3D texture rewrites one rg8 slice in place', () async {
    final volume = Texture3D.empty(
      width: 2,
      height: 2,
      depth: 2,
      format: PixelFormat.r8g8UNormInt,
    );
    volume.writeSlice(0, Uint8List(8));
    volume.writeSlice(
      1,
      Uint8List.fromList([
        for (var i = 0; i < 4; i++) ...[200, 40],
      ]),
    );
    expect(
      (await sample(
        'VolumeFragment',
        'VolumeParams',
        _texture(volume.gpuTexture),
        'volume',
        0.75,
      )).sublist(0, 2),
      [200, 40],
    );
    expect(() => volume.writeSlice(2, Uint8List(8)), throwsRangeError);
  });
}
