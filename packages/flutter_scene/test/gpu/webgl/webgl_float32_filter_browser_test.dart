// A 32-bit float texture sampled with linear filtering on a context without
// OES_texture_float_linear samples nearest instead of reading as zero.
//
//   flutter test --platform chrome test/gpu/webgl/webgl_float32_filter_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bundle() {
  fb.ShaderObjectBuilder shader(
    String name,
    fb.ShaderStage stage,
    String source, {
    List<fb.ShaderInputObjectBuilder> inputs = const [],
    List<fb.ShaderUniformTextureObjectBuilder> textures = const [],
  }) => fb.ShaderObjectBuilder(
    name: name,
    openglEs: fb.BackendShaderObjectBuilder(
      stage: stage,
      entrypoint: 'main',
      inputs: inputs,
      uniformStructs: const [],
      uniformTextures: textures,
      shader: utf8.encode(source),
    ),
  );
  return fb.ShaderBundleObjectBuilder(
    formatVersion: 2,
    shaders: [
      shader(
        'QuadVertex',
        fb.ShaderStage.kVertex,
        '#version 300 es\nin vec2 position;\nout vec2 v_uv;\n'
            'void main() {\n  v_uv = position * 0.5 + 0.5;\n'
            '  gl_Position = vec4(position, 0.0, 1.0);\n}\n',
        inputs: [fb.ShaderInputObjectBuilder(name: 'position')],
      ),
      shader(
        'DepthFragment',
        fb.ShaderStage.kFragment,
        '#version 300 es\nprecision highp float;\n'
            'uniform sampler2D depth;\nin vec2 v_uv;\n'
            'out vec4 frag_color;\nvoid main() {\n'
            '  frag_color = vec4(texture(depth, v_uv).r, 0.0, 0.0, 1.0);\n}\n',
        textures: [fb.ShaderUniformTextureObjectBuilder(name: 'depth')],
      ),
    ],
  ).toBytes();
}

void main() {
  if (gpu.useWebGpuBackend) {
    test('runs without --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  late gpu.ShaderLibrary library;
  late gpu.DeviceBuffer triangle;
  late WebGlContext context;
  late bool supported;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    context = gpu.gpuContext as WebGlContext;
    supported = context.float32Filterable;
    library = (await gpu.loadShaderLibraryFromBytesAsync(
      ByteData.sublistView(_bundle()),
    ))!;
    triangle = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
    );
  });

  tearDown(() => context.float32Filterable = supported);

  /// Draws a 2x1 [format] texture holding 0 and 1 across an 8x1 target with
  /// linear filtering and returns the red channel of each target texel.
  Future<List<int>> stretch(gpu.PixelFormat format) async {
    final channels = format == gpu.PixelFormat.r32Float ? 1 : 4;
    final source = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      2,
      1,
      format: format,
    );
    source.overwrite(
      ByteData.sublistView(
        Float32List.fromList([
          for (final v in [0.0, 1.0]) ...List.filled(channels, v),
        ]),
      ),
    );
    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      8,
      1,
    );
    final fragment = library['DepthFragment']!;
    final commands = gpu.gpuContext.createCommandBuffer();
    commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
      )
      ..bindPipeline(
        gpu.gpuContext.createRenderPipeline(
          library['QuadVertex']!,
          fragment,
          vertexLayout: const gpu.VertexLayout(
            buffers: [
              gpu.VertexBuffer(
                strideInBytes: 8,
                attributes: [
                  gpu.VertexAttribute(
                    name: 'position',
                    format: gpu.VertexFormat.float32x2,
                  ),
                ],
              ),
            ],
          ),
        ),
      )
      ..bindVertexBuffer(
        gpu.BufferView(triangle, offsetInBytes: 0, lengthInBytes: 24),
      )
      ..bindTexture(
        fragment.getUniformSlot('depth'),
        source,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.linear,
          magFilter: gpu.MinMagFilter.linear,
        ),
      )
      ..draw(3);
    commands.submit();
    final image = target.asImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    gpu.gpuHost.releaseTexture(source);
    gpu.gpuHost.releaseTexture(target);
    return [for (var x = 0; x < 8; x++) bytes.getUint8(x * 4)];
  }

  for (final format in [
    gpu.PixelFormat.r32Float,
    gpu.PixelFormat.r32g32b32a32Float,
  ]) {
    test('$format without float filtering samples nearest', () async {
      context.float32Filterable = false;
      final red = await stretch(format);
      expect(red.sublist(0, 4), everyElement(0), reason: '$red');
      expect(red.sublist(4), everyElement(255), reason: '$red');
    });

    test('$format with float filtering interpolates', () async {
      if (!supported) {
        markTestSkipped('This browser cannot filter 32-bit float textures.');
        return;
      }
      final red = await stretch(format);
      expect(red.where((r) => r > 10 && r < 245), isNotEmpty, reason: '$red');
    });
  }
}
