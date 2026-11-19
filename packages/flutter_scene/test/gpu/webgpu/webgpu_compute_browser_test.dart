// Dispatches a compute shader through the shim and reads its output back.
// WebGL2 has no compute, so there the shim must refuse it.
//
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/webgpu/webgpu_compute_browser_test.dart
//   flutter test --platform chrome \
//     test/gpu/webgpu/webgpu_compute_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';

// Tint's translation of this GLSL from a Flutter 3.51 shader bundle, by the
// build hook's sidecar step:
//
//   layout(local_size_x = 4) in;
//   layout(std430) buffer;
//   layout(binding = 0) readonly buffer Input { uint values[]; } input_data;
//   layout(binding = 1) writeonly buffer Output { uint values[]; } output_data;
//   uniform Params { uint count; uint offset; } params;
//   void main() {
//     uint index = gl_GlobalInvocationID.x;
//     if (index >= params.count) return;
//     output_data.values[index] = input_data.values[index] * 2u + params.offset;
//   }
const _scaleWgsl = r'''
diagnostic(off, derivative_uniformity);

struct tint_symbol_2 {
  tint_symbol : u32,
  tint_symbol_1 : u32,
}

@group(0u) @binding(2u) var<uniform> v : tint_symbol_2;

struct tint_symbol_4 {
  tint_symbol_3 : array<u32>,
}

@group(0u) @binding(1u) var<storage, read_write> v_1 : tint_symbol_4;

struct tint_symbol_6 {
  tint_symbol_5 : array<u32>,
}

@group(0u) @binding(0u) var<storage, read> v_2 : tint_symbol_6;

@compute @workgroup_size(4u, 1u, 1u)
fn main(@builtin(global_invocation_id) v_3 : vec3<u32>) {
  switch(0u) {
    default: {
      let v_4 = v_3.x;
      if ((v_4 >= v.tint_symbol)) {
        break;
      }
      v_1.tint_symbol_3[v_4] = ((v_2.tint_symbol_5[v_4] * 2u) + v.tint_symbol_1);
    }
  }
}
''';

String _sidecar({List<int> workgroupSize = const [4, 1, 1]}) => jsonEncode({
  'format': 2,
  'translator': 'test',
  'bundle': 'test',
  'shaders': {
    'Scale': {
      'stage': 'compute',
      'entryPoint': 'main',
      'wgsl': _scaleWgsl,
      'inputs': <Object?>[],
      'uniforms': [
        {
          'name': 'Params',
          'group': 0,
          'binding': 2,
          'size': 8,
          'fields': [
            {'name': 'count', 'offset': 0},
            {'name': 'offset', 'offset': 4},
          ],
        },
      ],
      'textures': <Object?>[],
      'storageBuffers': [
        {
          'name': 'Output',
          'group': 0,
          'binding': 1,
          'size': 0,
          'stride': 4,
          'access': 'read_write',
        },
        {
          'name': 'Input',
          'group': 0,
          'binding': 0,
          'size': 0,
          'stride': 4,
          'access': 'read',
        },
      ],
      'workgroupSize': workgroupSize,
    },
  },
});

gpu.BufferView _whole(gpu.DeviceBuffer buffer) =>
    gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: buffer.sizeInBytes);

ByteData _words(List<int> values) =>
    ByteData.sublistView(Uint32List.fromList(values));

void main() {
  if (!gpu.useWebGpuBackend) {
    test('WebGL2 reports no compute and refuses it', () async {
      await gpu.initializeGpuBackend();
      expect(gpu.supportsCompute, isFalse);
      expect(gpu.gpuHost.capabilities.compute, isFalse);
      expect(gpu.computeLimits.maxWorkgroupInvocations, 0);
      expect(
        () => gpu.createComputePass(gpu.gpuContext.createCommandBuffer()),
        throwsUnsupportedError,
      );
    });
    return;
  }

  late gpu.Shader scale;
  late gpu.GpuComputePipeline pipeline;
  late gpu.GpuStorageBufferSlot input;
  late gpu.GpuStorageBufferSlot output;
  late gpu.UniformSlot params;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    final library = await webGpuShaderLibraryFromSidecar(_sidecar());
    scale = library['Scale']!;
    await webGpuShaderChecked(scale);
    pipeline = gpu.createComputePipeline(scale);
    input = gpu.getStorageBufferSlot(scale, 'Input');
    output = gpu.getStorageBufferSlot(scale, 'Output');
    params = scale.getUniformSlot('Params');
  });

  test('reports compute and its limits', () {
    expect(gpu.supportsCompute, isTrue);
    expect(gpu.gpuHost.capabilities.compute, isTrue);
    final limits = gpu.computeLimits;
    expect(limits.maxWorkgroupInvocations, greaterThanOrEqualTo(256));
    expect(limits.maxWorkgroupSize.$1, greaterThanOrEqualTo(256));
    expect(limits.maxWorkgroupCount.$1, greaterThanOrEqualTo(65535));
    expect(limits.minStorageBufferOffsetAlignment, greaterThan(0));
  });

  test('reflects the storage buffers', () {
    expect(input.sizeInBytes, 0);
    expect(input.runtimeArrayStrideInBytes, 4);
    expect(input.storageBufferName, 'Input');
    expect(
      () => gpu.getStorageBufferSlot(scale, 'Missing'),
      throwsArgumentError,
    );
  });

  test('a dispatch writes what the shader computes', () async {
    // 18 elements in workgroups of 4 dispatch 20 invocations, so the shader's
    // bounds guard has to stop the last two.
    const count = 18;
    final values = [for (var i = 0; i < count; i++) i * 3 + 1];
    final source = gpu.gpuContext.createDeviceBufferWithCopy(_words(values));
    final result = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      count * 4,
    );
    final host = gpu.gpuContext.createHostBuffer();

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    gpu.createComputePass(commandBuffer)
      ..bindPipeline(pipeline)
      ..bindStorageBuffer(input, _whole(source))
      ..bindStorageBuffer(output, _whole(result))
      ..bindUniform(params, host.emplace(_words([count, 7])))
      ..dispatch((count + 3) ~/ 4);
    commandBuffer.submit();

    final bytes = await webGpuReadBuffer(result, length: count * 4);
    expect(bytes.buffer.asUint32List(0, count), [
      for (final v in values) v * 2 + 7,
    ]);
  });

  test('later dispatches see earlier writes and keep bindings', () async {
    const count = 8;
    final first = gpu.gpuContext.createDeviceBufferWithCopy(
      _words(List.generate(count, (i) => i)),
    );
    final second = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      count * 4,
    );
    final third = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      count * 4,
    );
    final host = gpu.gpuContext.createHostBuffer();

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = gpu.createComputePass(commandBuffer)
      ..bindPipeline(pipeline)
      ..bindUniform(params, host.emplace(_words([count, 1])))
      ..bindStorageBuffer(input, _whole(first))
      ..bindStorageBuffer(output, _whole(second))
      ..dispatch(2)
      // The uniform stays bound; only the buffers swap.
      ..bindStorageBuffer(input, _whole(second))
      ..bindStorageBuffer(output, _whole(third))
      ..dispatch(2)
      ..dispatch(0);
    pass.end();
    commandBuffer.submit();

    final bytes = await webGpuReadBuffer(third, length: count * 4);
    expect(bytes.buffer.asUint32List(0, count), [
      for (var i = 0; i < count; i++) (i * 2 + 1) * 2 + 1,
    ]);
  });

  test('a dispatch with a resource unbound throws naming it', () {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = gpu.createComputePass(commandBuffer)
      ..bindPipeline(pipeline)
      ..bindStorageBuffer(
        input,
        _whole(gpu.gpuContext.createDeviceBufferWithCopy(_words([1]))),
      );
    expect(
      () => pass.dispatch(1),
      throwsA(predicate((e) => '$e'.contains('storage buffer "Output"'))),
    );
    commandBuffer.submit();
  });

  test('storage views are checked as Flutter GPU checks them', () {
    final buffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.devicePrivate,
      1024,
    );
    final pass = gpu.createComputePass(gpu.gpuContext.createCommandBuffer());
    // A partial 4-byte element.
    expect(
      () => pass.bindStorageBuffer(
        input,
        gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 6),
      ),
      throwsArgumentError,
    );
    // An offset off the storage alignment.
    expect(
      () => pass.bindStorageBuffer(
        input,
        gpu.BufferView(buffer, offsetInBytes: 4, lengthInBytes: 8),
      ),
      throwsArgumentError,
    );
  });

  test('a compute shader is no render stage', () {
    expect(
      () => gpu.gpuContext.createRenderPipeline(scale, scale),
      throwsException,
    );
  });

  test('a workgroup past the device limits is refused', () async {
    final library = await webGpuShaderLibraryFromSidecar(
      _sidecar(workgroupSize: [4096, 1, 1]),
    );
    expect(
      () => gpu.createComputePipeline(library['Scale']!),
      throwsA(predicate((e) => '$e'.contains('4096 x 1 x 1'))),
    );
  });
}
