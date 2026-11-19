// Dispatches a compute shader through the native shim, which reaches Flutter
// GPU's compute by name. On an engine older than Flutter 3.53, or on OpenGL
// ES, the shim must report no compute and refuse it instead.
//
//   flutter test --enable-impeller --enable-flutter-gpu test/compute_gpu_test.dart
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

const _scaleSource = '''
layout(local_size_x = 4) in;

layout(std430) buffer;

layout(binding = 0) readonly buffer Input {
  uint values[];
}
input_data;

layout(binding = 1) writeonly buffer Output {
  uint values[];
}
output_data;

uniform Params {
  uint count;
  uint offset;
}
params;

void main() {
  uint index = gl_GlobalInvocationID.x;
  if (index >= params.count) {
    return;
  }
  output_data.values[index] = input_data.values[index] * 2u + params.offset;
}
''';

/// Compiles [_scaleSource] with the impellerc beside the running engine, so
/// the bundle always matches it. Null when the SDK layout has none.
ByteData? _compileScaleBundle() {
  final engineDir = File(Platform.resolvedExecutable).parent;
  final impellerc = File('${engineDir.path}/impellerc');
  final shaderLib = Directory('${engineDir.path}/shader_lib');
  if (!impellerc.existsSync()) return null;
  final dir = Directory.systemTemp.createTempSync('compute_gpu_test_');
  try {
    final source = File('${dir.path}/scale.comp')
      ..writeAsStringSync(_scaleSource);
    final bundle = File('${dir.path}/scale.shaderbundle');
    final result = Process.runSync(impellerc.path, [
      '--sl=${bundle.path}',
      '--shader-bundle={"Scale": {"type": "compute", "file": "${source.path}"}}',
      '--include=${dir.path}',
      '--include=${shaderLib.path}',
    ]);
    if (result.exitCode != 0) {
      fail('impellerc failed: ${result.stdout}${result.stderr}');
    }
    return ByteData.sublistView(bundle.readAsBytesSync());
  } finally {
    dir.deleteSync(recursive: true);
  }
}

bool _hasContext() {
  try {
    gpu.gpuContext;
    return true;
  } on Exception {
    return false;
  }
}

gpu.BufferView _whole(gpu.DeviceBuffer buffer) =>
    gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: buffer.sizeInBytes);

ByteData _words(List<int> values) =>
    ByteData.sublistView(Uint32List.fromList(values));

void main() {
  if (!_hasContext()) {
    test('needs a Flutter GPU context', () {
      markTestSkipped('Run with --enable-impeller --enable-flutter-gpu.');
    });
    return;
  }

  test('capabilities agree with the context', () {
    expect(gpu.gpuHost.capabilities.compute, gpu.supportsCompute);
    if (!gpu.supportsCompute) {
      expect(gpu.computeLimits.maxWorkgroupInvocations, 0);
    }
  });

  test('refuses compute where the engine has none', () {
    if (gpu.supportsCompute) {
      markTestSkipped('This engine has compute.');
      return;
    }
    expect(
      () => gpu.createComputePass(gpu.gpuContext.createCommandBuffer()),
      throwsUnsupportedError,
    );
  });

  test('a dispatch writes what the shader computes', () async {
    if (!gpu.supportsCompute) {
      markTestSkipped('Compute needs Flutter 3.53 on Metal or Vulkan.');
      return;
    }
    final limits = gpu.computeLimits;
    expect(limits.maxWorkgroupInvocations, greaterThanOrEqualTo(128));
    expect(limits.minStorageBufferOffsetAlignment, greaterThan(0));

    final bundle = _compileScaleBundle();
    if (bundle == null) {
      markTestSkipped('No impellerc beside ${Platform.resolvedExecutable}.');
      return;
    }
    final library = (await gpu.loadShaderLibraryFromBytesAsync(bundle))!;
    final scale = library['Scale']!;
    final pipeline = gpu.createComputePipeline(scale);
    expect(identical(pipeline.shader, scale), isTrue);
    final input = gpu.getStorageBufferSlot(scale, 'Input');
    final output = gpu.getStorageBufferSlot(scale, 'Output');
    expect(input.runtimeArrayStrideInBytes, 4);

    // 16 words, read back as a 4x4 RGBA8 texture. Five workgroups of four
    // run 20 invocations, so the shader's bounds guard stops the last four.
    // The offset makes every texel opaque, so no alpha conversion touches it.
    const count = 16;
    const offset = 0x01000000;
    final values = [for (var i = 0; i < count; i++) 0x7f000000 | i * 0x010203];
    final source = gpu.gpuContext.createDeviceBufferWithCopy(_words(values));
    final result = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      count * 4,
    );
    final host = gpu.gpuContext.createHostBuffer();
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      4,
      4,
      enableRenderTargetUsage: false,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    gpu.createComputePass(commandBuffer)
      ..bindPipeline(pipeline)
      ..bindStorageBuffer(input, _whole(source))
      ..bindStorageBuffer(output, _whole(result))
      ..bindUniform(
        scale.getUniformSlot('Params'),
        host.emplace(_words([count, offset])),
      )
      ..dispatch(5);
    commandBuffer.copyBufferToTexture(
      _whole(result),
      gpu.TextureRegion(texture),
    );
    commandBuffer.submit();

    final image = texture.asImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(bytes.buffer.asUint32List(bytes.offsetInBytes, count), [
      for (final v in values) v * 2 + offset,
    ]);
  });
}
