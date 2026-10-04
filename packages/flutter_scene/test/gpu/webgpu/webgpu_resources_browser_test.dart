// The WebGPU backend's resources through the shim API, checked by reading
// them back from the GPU.
//
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/webgpu/webgpu_resources_browser_test.dart
//
// Skips without the define, since the shim is WebGL2 then.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

ByteData _bytes(List<int> values) =>
    ByteData.sublistView(Uint8List.fromList(values));

double _srgbToLinear(double c) =>
    c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) =>
    c < 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

void main() {
  if (!gpu.useWebGpuBackend) {
    test('needs --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGL2 in this build.');
    });
    return;
  }

  setUpAll(() async {
    await gpu.initializeGpuBackend();
  });

  group('DeviceBuffer', () {
    test('aligned and unaligned writes land exactly', () async {
      final buffer = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        10,
      );
      expect(buffer.overwrite(_bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])), isTrue);
      expect(
        buffer.overwrite(_bytes([20, 30, 40]), destinationOffsetInBytes: 1),
        isTrue,
      );
      expect(
        buffer.overwrite(_bytes([77]), destinationOffsetInBytes: 9),
        isTrue,
      );
      expect(await webGpuReadBuffer(buffer, length: 10), [
        1, 20, 30, 40, 5, 6, 7, 8, 9, 77, //
      ]);
    });

    test('rejects out-of-range writes and device-private writes', () {
      final buffer = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        8,
      );
      expect(
        buffer.overwrite(_bytes([1, 2]), destinationOffsetInBytes: 7),
        isFalse,
      );
      final private = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.devicePrivate,
        8,
      );
      expect(() => private.overwrite(_bytes([1])), throwsException);
    });

    test('geometry buffers pad a short index tail', () async {
      final split = gpu.createGeometryBuffers(8, 6);
      expect(split.indexBaseOffset, 8);
      expect(identical(split.vertex, split.index), isTrue);
      gpu.writeGeometryData(
        split.vertex,
        Float32List.fromList([1.5, -2.0]),
        destinationOffsetInBytes: 0,
      );
      gpu.writeGeometryData(
        split.index,
        Uint16List.fromList([0, 1, 2]),
        destinationOffsetInBytes: split.indexBaseOffset,
      );
      final bytes = await webGpuReadBuffer(split.vertex, length: 14);
      expect(ByteData.sublistView(bytes).getFloat32(0, Endian.little), 1.5);
      expect(ByteData.sublistView(bytes).getFloat32(4, Endian.little), -2.0);
      expect(Uint16List.sublistView(bytes, 8, 14), [0, 1, 2]);
    });

    test('host buffer emplacements honor the uniform alignment', () async {
      final host = gpu.gpuContext.createHostBuffer();
      final alignment = gpu.gpuContext.minimumUniformByteAlignment;
      final a = host.emplace(_bytes([1, 2, 3, 4]));
      final b = host.emplace(_bytes([5, 6, 7, 8]));
      expect(a.offsetInBytes % alignment, 0);
      expect(b.offsetInBytes % alignment, 0);
      expect(b.offsetInBytes, greaterThan(a.offsetInBytes));
      expect(
        await webGpuReadBuffer(b.buffer, offset: b.offsetInBytes, length: 4),
        [5, 6, 7, 8],
      );
    });
  });

  group('Texture', () {
    test('writes each mip level of an RGBA8 texture', () async {
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        2,
        2,
        mipLevelCount: 2,
      );
      final level0 = List<int>.generate(16, (i) => i * 10);
      texture.overwrite(_bytes(level0));
      texture.overwrite(_bytes([9, 8, 7, 6]), mipLevel: 1);
      expect(await webGpuReadTexture(texture), level0);
      expect(await webGpuReadTexture(texture, mipLevel: 1), [9, 8, 7, 6]);
      expect(texture.getMipLevelSizeInBytes(1), 4);
    });

    test('float formats round-trip', () async {
      final r32 = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
        format: gpu.PixelFormat.r32Float,
      );
      final value = ByteData(4)..setFloat32(0, 3.25, Endian.little);
      r32.overwrite(value);
      expect(
        ByteData.sublistView(
          await webGpuReadTexture(r32),
        ).getFloat32(0, Endian.little),
        3.25,
      );
      final rgba16 = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
        format: gpu.PixelFormat.r16g16b16a16Float,
      );
      final half = _bytes([0x00, 0x3c, 0x00, 0x40, 0x00, 0x00, 0x00, 0x3c]);
      rgba16.overwrite(half);
      expect(await webGpuReadTexture(rgba16), half.buffer.asUint8List());
    });

    test('a cube map writes one face', () async {
      final cube = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
        textureType: gpu.TextureType.textureCube,
      );
      expect(cube.sliceCount, 6);
      cube.overwrite(_bytes([11, 22, 33, 44]), slice: 3);
      expect(await webGpuReadTexture(cube, slice: 3), [11, 22, 33, 44]);
    });

    test('compressed blocks upload when the device has the format', () async {
      if (!gpu.gpuContext.supportsTextureCompression(
        gpu.TextureCompressionFamily.bc,
      )) {
        markTestSkipped('No BC support on this device.');
        return;
      }
      final bc1 = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        4,
        4,
        format: gpu.PixelFormat.bc1RGBAUNormInt,
      );
      final block = List<int>.generate(8, (i) => i + 1);
      bc1.overwrite(_bytes(block));
      expect(await webGpuReadTexture(bc1), block);
    });

    test('refuses what WebGPU cannot represent', () {
      expect(
        () => gpu.gpuContext.createTexture(
          gpu.StorageMode.hostVisible,
          1,
          1,
          format: gpu.PixelFormat.a8UNormInt,
        ),
        throwsUnsupportedError,
      );
      if (gpu.gpuContext.supportsTextureCompression(
        gpu.TextureCompressionFamily.bc,
      )) {
        expect(
          () => gpu.gpuContext.createTexture(
            gpu.StorageMode.hostVisible,
            6,
            4,
            format: gpu.PixelFormat.bc1RGBAUNormInt,
          ),
          throwsUnsupportedError,
        );
      }
    });
  });

  group('createTextureFromEncodedImage', () {
    test('uploads and box-filters the mip chain in linear light', () async {
      // A 2x2 pattern tiled to 4x4, the smallest size given a second level.
      final image = img.Image(width: 4, height: 4, numChannels: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final (r, g, b, a) = switch ((x % 2, y % 2)) {
            (0, 0) => (255, 0, 0, 255),
            (1, 0) => (0, 255, 0, 255),
            (0, 1) => (0, 0, 255, 255),
            _ => (255, 255, 255, 128),
          };
          image.setPixelRgba(x, y, r, g, b, a);
        }
      }
      final texture = (await gpu.createTextureFromEncodedImage(
        img.encodePng(image),
        maxMipLevels: 2,
      ))!;
      expect((texture.width, texture.height, texture.mipLevelCount), (4, 4, 2));
      final level0 = await webGpuReadTexture(texture);
      expect(level0.sublist(0, 4), [255, 0, 0, 255]);
      expect(level0.sublist(20, 24), [255, 255, 255, 128]);

      final level1 = await webGpuReadTexture(texture, mipLevel: 1);
      // Each channel is one of four texels at full intensity, two of them
      // here, so the linear average is 0.5 for every channel.
      final channel = (_linearToSrgb((2 * _srgbToLinear(1.0)) / 4) * 255);
      for (var c = 0; c < 3; c++) {
        expect(level1[c], closeTo(channel, 1.5));
      }
      expect(level1[3], closeTo((255 * 3 + 128) / 4, 1.5));
    });
  });
}
