// 2D-array textures on the WebGL2 backend, uploaded a layer at a time,
// sampled through a sampler2DArray, and read back.
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

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

const _layers = 3;

// One fragment shader per layer, so no uniform block is needed. Leaves out
// the uint64 reflection fields so dart2js can build the bundle too.
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
      for (var layer = 0; layer < _layers; layer++)
        shader(
          'Layer${layer}Fragment',
          fb.ShaderStage.kFragment,
          '#version 300 es\nprecision highp float;\n'
              'precision highp sampler2DArray;\n'
              'uniform sampler2DArray layers;\nin vec2 v_uv;\n'
              'out vec4 frag_color;\nvoid main() {\n'
              '  vec4 t = texture(layers, vec3(v_uv, $layer.0));\n'
              '  frag_color = vec4(t.r, t.g, 0.0, 1.0);\n}\n',
          textures: [fb.ShaderUniformTextureObjectBuilder(name: 'layers')],
        ),
    ],
  ).toBytes();
}

// The analyzer resolves package:flutter_scene/scene.dart against the native
// shim, while this test drives the web one; at runtime in a browser both are
// the web shim. This recovers the web type for scene-level textures.
gpu.Texture _texture(Object texture) => texture as gpu.Texture;

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
      ByteData.sublistView(_bundle()),
    ))!;
    triangle = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
    );
  });

  /// Fills a 4x4 target with [layer] of [texture] and returns its first
  /// texel.
  Future<List<int>> sample(Object texture, int layer) async {
    final fragment = library['Layer${layer}Fragment']!;
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
        fragment.getUniformSlot('layers'),
        _texture(texture),
        sampler: gpu.SamplerOptions(),
      )
      ..draw(3);
    commands.submit();
    final image = target.asImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return bytes.buffer.asUint8List(0, 4);
  }

  test('samples each r8 layer', () async {
    final layers = Texture2DArray.fromLayers(
      [
        for (final value in [10, 120, 250])
          Uint8List(16)..fillRange(0, 16, value),
      ],
      width: 4,
      height: 4,
      format: DataTextureFormat.r8,
    );
    for (final (layer, value) in [(0, 10), (1, 120), (2, 250)]) {
      expect(
        (await sample(layers.gpuTexture, layer))[0],
        value,
        reason: 'layer $layer',
      );
    }
  });

  test('uploads odd-width r8 layers with tightly packed rows', () async {
    // Three-byte rows fail to upload under GL's default four-byte unpack
    // alignment, leaving the layer empty.
    final layers = Texture2DArray.fromLayers(
      [Uint8List(9)..fillRange(0, 9, 77)],
      width: 3,
      height: 3,
      format: DataTextureFormat.r8,
    );
    expect((await sample(layers.gpuTexture, 0))[0], 77);
  });

  test('rewrites one rg8 layer in place', () async {
    final layers = Texture2DArray.fromLayers(
      [Uint8List(32), Uint8List(32)],
      width: 4,
      height: 4,
      format: DataTextureFormat.rg8,
    );
    layers.writeLayer(
      1,
      Uint8List.fromList([
        for (var i = 0; i < 16; i++) ...[200, 40],
      ]),
    );
    expect((await sample(layers.gpuTexture, 0)).sublist(0, 2), [0, 0]);
    expect((await sample(layers.gpuTexture, 1)).sublist(0, 2), [200, 40]);
    expect(() => layers.writeLayer(2, Uint8List(32)), throwsRangeError);
  });
}
