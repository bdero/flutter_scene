// Draws through the WebGPU backend's shim API and reads the pixels back:
// uniforms, textures, blending, depth, scissor, MSAA resolve, and the
// synchronous handoff to Flutter.
//
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/webgpu/webgpu_render_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

final Uint8List _bundle = Uint8List.fromList(utf8.encode('render bundle'));

// A quad from (x0, y0) to (x1, y1) at depth z, in clip space.
const _vertexWgsl = '''
struct Quad { rect : vec4<f32>, z : vec4<f32> }
@group(0u) @binding(0u) var<uniform> quad : Quad;
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) corner : vec2<f32>) -> Out {
  let p = mix(quad.rect.xy, quad.rect.zw, corner);
  return Out(vec4<f32>(p, quad.z.x, 1.0), corner);
}
''';

const _fragmentWgsl = '''
struct Tint { color : vec4<f32> }
@group(0u) @binding(64u) var<uniform> tint : Tint;
@group(0u) @binding(65u) var albedo : texture_2d<f32>;
@group(0u) @binding(193u) var albedo_sampler : sampler;
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  return textureSample(albedo, albedo_sampler, uv) * tint.color;
}
''';

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
        {'name': 'corner', 'location': 0, 'vecSize': 2, 'offset': 0},
      ],
      'uniforms': [
        {
          'name': 'Quad',
          'group': 0,
          'binding': 0,
          'size': 32,
          'fields': [
            {'name': 'rect', 'offset': 0},
            {'name': 'z', 'offset': 16},
          ],
        },
      ],
      'textures': <Object?>[],
    },
    'TintFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _fragmentWgsl,
      'inputs': <Object?>[],
      'uniforms': [
        {
          'name': 'Tint',
          'group': 0,
          'binding': 64,
          'size': 16,
          'fields': [
            {'name': 'color', 'offset': 0},
          ],
        },
      ],
      'textures': [
        {'name': 'albedo', 'group': 0, 'binding': 65, 'sampler': 193},
      ],
    },
  },
});

ByteData _floats(List<double> values) =>
    ByteData.sublistView(Float32List.fromList(values));

void main() {
  if (!gpu.useWebGpuBackend) {
    test('needs --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGL2 in this build.');
    });
    return;
  }

  late gpu.Shader vertex;
  late gpu.Shader fragment;
  late gpu.RenderPipeline pipeline;
  late gpu.BufferView corners;
  late gpu.Texture white;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    final library = await webGpuShaderLibraryFromSidecar(_bundle, _sidecar());
    vertex = library['QuadVertex']!;
    fragment = library['TintFragment']!;
    pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);
    final quad = gpu.gpuContext.createDeviceBufferWithCopy(
      _floats([0, 0, 1, 0, 0, 1, 1, 1]),
    );
    corners = gpu.BufferView(quad, offsetInBytes: 0, lengthInBytes: 32);
    white = gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 1, 1)
      ..overwrite(
        ByteData.sublistView(Uint8List.fromList([255, 255, 255, 255])),
      );
  });

  gpu.Texture target({int samples = 1}) => gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    4,
    4,
    sampleCount: samples,
  );

  /// Draws a quad over [rect] (clip space x0, y0, x1, y1) at depth [z].
  void quad(
    gpu.RenderPass pass,
    gpu.HostBuffer host, {
    List<double> rect = const [-1, -1, 1, 1],
    double z = 0.5,
    required List<double> color,
    gpu.Texture? texture,
  }) {
    pass
      ..bindPipeline(pipeline)
      ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
      ..bindVertexBuffer(corners)
      ..bindUniform(
        vertex.getUniformSlot('Quad'),
        host.emplace(_floats([...rect, z, 0, 0, 0])),
      )
      ..bindUniform(
        fragment.getUniformSlot('Tint'),
        host.emplace(_floats(color)),
      )
      ..bindTexture(fragment.getUniformSlot('albedo'), texture ?? white)
      ..draw(4);
  }

  Future<List<int>> pixel(gpu.Texture texture, int x, int y) async {
    final bytes = await webGpuReadTexture(texture);
    final i = (y * texture.width + x) * 4;
    return bytes.sublist(i, i + 4);
  }

  test('a tinted, textured quad lands in its target', () async {
    final color = target();
    final host = gpu.gpuContext.createHostBuffer();
    final checker =
        gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 2, 1)
          ..overwrite(
            ByteData.sublistView(
              Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]),
            ),
          );
    final commands = gpu.gpuContext.createCommandBuffer();
    final pass = commands.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: color, clearValue: vm.Vector4(0, 1, 0, 1)),
      ),
    );
    // The left half only, sampling the left (red) texel of the checker.
    quad(
      pass,
      host,
      rect: const [-1, -1, 0, 1],
      color: const [1, 1, 1, 1],
      texture: checker,
    );
    var completed = false;
    commands.submit(completionCallback: (_) => completed = true);
    expect(await pixel(color, 0, 0), [255, 0, 0, 255]);
    expect(await pixel(color, 3, 3), [0, 255, 0, 255]);
    expect(completed, isTrue);
  });

  test('passes in one command buffer run in order, with blending', () async {
    final color = target();
    final host = gpu.gpuContext.createHostBuffer();
    final commands = gpu.gpuContext.createCommandBuffer();
    quad(
      commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: color)),
      ),
      host,
      color: const [1, 0, 0, 1],
    );
    final second = commands.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: color, loadAction: gpu.LoadAction.load),
      ),
    )..setColorBlendEnable(true);
    // Premultiplied half-transparent blue over the red.
    quad(second, host, color: const [0, 0, 0.5, 0.5]);
    commands.submit();
    final p = await pixel(color, 1, 1);
    expect(p[0], closeTo(128, 1));
    expect(p[1], 0);
    expect(p[2], closeTo(128, 1));
    expect(p[3], 255);
  });

  test('depth testing keeps the nearer quad', () async {
    final color = target();
    final depth = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      4,
      4,
      format: gpu.gpuContext.defaultDepthStencilFormat,
    );
    final host = gpu.gpuContext.createHostBuffer();
    final commands = gpu.gpuContext.createCommandBuffer();
    final pass =
        commands.createRenderPass(
            gpu.RenderTarget.singleColor(
              gpu.ColorAttachment(texture: color),
              depthStencilAttachment: gpu.DepthStencilAttachment(
                texture: depth,
                depthClearValue: 1,
              ),
            ),
          )
          ..setDepthWriteEnable(true)
          ..setDepthCompareOperation(gpu.CompareFunction.less);
    quad(pass, host, z: 0.25, color: const [1, 0, 0, 1]);
    quad(pass, host, z: 0.75, color: const [0, 0, 1, 1]);
    commands.submit();
    expect(await pixel(color, 2, 2), [255, 0, 0, 255]);
  });

  test('a scissor clips the draw', () async {
    final color = target();
    final host = gpu.gpuContext.createHostBuffer();
    final commands = gpu.gpuContext.createCommandBuffer();
    final pass = commands.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: color)),
    )..setScissor(gpu.Scissor(x: 2, y: 0, width: 10, height: 10));
    quad(pass, host, color: const [1, 1, 1, 1]);
    commands.submit();
    expect(await pixel(color, 0, 0), [0, 0, 0, 0]);
    expect(await pixel(color, 3, 0), [255, 255, 255, 255]);
  });

  test('MSAA resolves into the resolve texture', () async {
    final msaa = target(samples: 4);
    final resolve = target();
    final host = gpu.gpuContext.createHostBuffer();
    final commands = gpu.gpuContext.createCommandBuffer();
    quad(
      commands.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: msaa,
            resolveTexture: resolve,
            storeAction: gpu.StoreAction.multisampleResolve,
          ),
        ),
      ),
      host,
      color: const [0, 1, 0, 1],
    );
    commands.submit();
    expect(await pixel(resolve, 1, 2), [0, 255, 0, 255]);
  });

  test(
    'an unbound uniform reads zeros and asImage hands the frame over',
    () async {
      final color = target();
      final host = gpu.gpuContext.createHostBuffer();
      final commands = gpu.gpuContext.createCommandBuffer();
      final pass = commands.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: color,
            clearValue: vm.Vector4(1, 0, 0, 1),
          ),
        ),
      );
      // Draw the top half only; Tint is never bound, so it multiplies by zero.
      pass
        ..bindPipeline(pipeline)
        ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
        ..bindVertexBuffer(corners)
        ..bindUniform(
          vertex.getUniformSlot('Quad'),
          host.emplace(_floats([-1, 0, 1, 1, 0.5, 0, 0, 0])),
        )
        ..bindTexture(fragment.getUniformSlot('albedo'), white)
        ..draw(4);
      commands.submit();

      final image = color.asImage();
      expect((image.width, image.height), (4, 4));
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      // Rows are top-down, as Impeller stores render targets: clip-space +y is
      // the top.
      expect(bytes.sublist(0, 4), [0, 0, 0, 0]);
      expect(bytes.sublist(4 * 12, 4 * 13), [255, 0, 0, 255]);
      image.dispose();
    },
  );
}
