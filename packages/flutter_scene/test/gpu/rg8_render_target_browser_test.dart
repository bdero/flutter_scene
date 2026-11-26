// Verifies two-channel RG8 color render targets (used for SMAA's edge texture
// when GpuHost.supportsRg8RenderTarget is true) on both WebGL2 and WebGPU:
// writing vec4 output into r8g8UNormInt and linearly sampling .rg in a
// follow-up pass.
//
//   flutter test --platform chrome test/gpu/rg8_render_target_browser_test.dart
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/rg8_render_target_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _bundle = Uint8List.fromList(utf8.encode('rg8 target bundle'));

const _vertexWgsl = '''
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) position : vec2<f32>) -> Out {
  return Out(vec4<f32>(position, 0.0, 1.0), position * 0.5 + vec2<f32>(0.5));
}
''';

const _writeRgWgsl = '''
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  return vec4<f32>(0.75, 0.25, 0.9, 1.0);
}
''';

const _sampleRgWgsl = '''
@group(0u) @binding(65u) var edges : texture_2d<f32>;
@group(0u) @binding(193u) var edges_sampler : sampler;
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  let e = textureSample(edges, edges_sampler, uv).rg;
  return vec4<f32>(e, 0.0, 1.0);
}
''';

String _webGpuSidecar() => jsonEncode({
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
    'WriteRgFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _writeRgWgsl,
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
    'SampleRgFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _sampleRgWgsl,
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': [
        {'name': 'edges', 'group': 0, 'binding': 65, 'sampler': 193},
      ],
    },
  },
});

Uint8List _webGlBundle() {
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
        'WriteRgFragment',
        fb.ShaderStage.kFragment,
        '#version 300 es\nprecision highp float;\n'
            'in vec2 v_uv;\nout vec4 frag_color;\n'
            'void main() {\n  frag_color = vec4(0.75, 0.25, 0.9, 1.0);\n}\n',
      ),
      shader(
        'SampleRgFragment',
        fb.ShaderStage.kFragment,
        '#version 300 es\nprecision highp float;\n'
            'uniform sampler2D edges;\nin vec2 v_uv;\nout vec4 frag_color;\n'
            'void main() {\n'
            '  frag_color = vec4(texture(edges, v_uv).rg, 0.0, 1.0);\n'
            '}\n',
        textures: [fb.ShaderUniformTextureObjectBuilder(name: 'edges')],
      ),
    ],
  ).toBytes();
}

void main() {
  late gpu.ShaderLibrary library;
  late gpu.BufferView triangleView;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    library = gpu.useWebGpuBackend
        ? await webGpuShaderLibraryFromSidecar(_webGpuSidecar())
        : (await gpu.loadShaderLibraryFromBytesAsync(
            ByteData.sublistView(_webGlBundle()),
          ))!;
    final triangle = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
    );
    triangleView = gpu.BufferView(
      triangle,
      offsetInBytes: 0,
      lengthInBytes: 6 * 4,
    );
  });

  test(
    'r8g8UNormInt target uses 2 B/px and round-trips through linear sampling',
    () async {
      expect(gpu.gpuHost.supportsRg8RenderTarget, isTrue);

      final edges = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
        format: gpu.PixelFormat.r8g8UNormInt,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      expect(edges.getMipLevelSizeInBytes(0), 4 * 4 * 2);

      final out = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );

      final vertex = library['QuadVertex']!;
      final writeFrag = library['WriteRgFragment']!;
      final sampleFrag = library['SampleRgFragment']!;
      const layout = gpu.VertexLayout(
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
      );

      // Pass 1: render vec4 fragment output into the two-channel RG8 target.
      {
        final commands = gpu.gpuContext.createCommandBuffer();
        final pass = commands.createRenderPass(
          gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: edges)),
        );
        pass.bindPipeline(
          gpu.gpuContext.createRenderPipeline(
            vertex,
            writeFrag,
            vertexLayout: layout,
          ),
        );
        pass.bindVertexBuffer(triangleView);
        pass.draw(3);
        commands.submit();
      }

      // Pass 2: sample RG8 with a linear sampler into an RGBA8 target.
      {
        final commands = gpu.gpuContext.createCommandBuffer();
        final pass = commands.createRenderPass(
          gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: out)),
        );
        pass.bindPipeline(
          gpu.gpuContext.createRenderPipeline(
            vertex,
            sampleFrag,
            vertexLayout: layout,
          ),
        );
        pass.bindVertexBuffer(triangleView);
        pass.bindTexture(
          sampleFrag.getUniformSlot('edges'),
          edges,
          sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
            heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
          ),
        );
        pass.draw(3);
        commands.submit();
      }

      final image = out.asImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();

      final offset = (2 * 4 + 2) * 4;
      expect(bytes[offset], inInclusiveRange(189, 193));
      expect(bytes[offset + 1], inInclusiveRange(62, 66));
      expect(bytes[offset + 2], 0);
      expect(bytes[offset + 3], 255);
    },
  );
}
