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
// The trailing vec3 makes the reflected size 28 while WGSL pads the struct
// to 32, as impellerc reflects an .fmat block of 60 bytes padded to 64.
struct Tint { color : vec4<f32>, unused : vec3<f32> }
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
          'size': 28,
          'fields': [
            {'name': 'color', 'offset': 0},
          ],
        },
      ],
      'textures': [
        {'name': 'albedo', 'group': 0, 'binding': 65, 'sampler': 193},
      ],
    },
    // Reads a varying QuadVertex never writes.
    'MismatchedFragment': _bareFragment('''
@fragment
fn main(@location(5u) v : vec4<f32>) -> @location(0u) vec4<f32> {
  return v;
}
'''),
    // Lines up with QuadVertex, but no color target takes a uint.
    'UintFragment': _bareFragment('''
@fragment
fn main() -> @location(0u) vec4<u32> {
  return vec4<u32>(1u);
}
'''),
  },
});

Map<String, Object?> _bareFragment(String wgsl) => {
  'stage': 'fragment',
  'entryPoint': 'main',
  'wgsl': wgsl,
  'inputs': <Object?>[],
  'uniforms': <Object?>[],
  'textures': <Object?>[],
};

ByteData _floats(List<double> values) =>
    ByteData.sublistView(Float32List.fromList(values));

void main() {
  if (!gpu.useWebGpuBackend) {
    test('needs --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGL2 in this build.');
    });
    return;
  }

  late gpu.ShaderLibrary library;
  late gpu.Shader vertex;
  late gpu.Shader fragment;
  late gpu.RenderPipeline pipeline;
  late gpu.BufferView corners;
  late gpu.Texture white;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    library = await webGpuShaderLibraryFromSidecar(_sidecar());
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
    final completionOrder = <int>[];
    commands.submit(
      completionCallback: (status) {
        expect(status, gpu.CompletionStatus.successful);
        completed = true;
        completionOrder.add(0);
      },
    );
    gpu.gpuContext.createCommandBuffer().submit(
      completionCallback: (status) {
        expect(status, gpu.CompletionStatus.successful);
        completionOrder.add(1);
      },
    );
    expect(await pixel(color, 0, 0), [255, 0, 0, 255]);
    expect(await pixel(color, 3, 3), [0, 255, 0, 255]);
    expect(completed, isTrue);
    expect(completionOrder, [0, 1]);
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

  test('a refused draw throws and spares the rest of the frame', () async {
    /// Draws a red quad, then [refused] over it, and reads the result.
    Future<List<int>> frame(gpu.RenderPipeline refused, Matcher draw) async {
      final color = target();
      final host = gpu.gpuContext.createHostBuffer();
      final commands = gpu.gpuContext.createCommandBuffer();
      final pass = commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: color)),
      );
      quad(pass, host, color: const [1, 0, 0, 1]);
      pass
        ..bindPipeline(refused)
        ..bindVertexBuffer(corners)
        ..bindUniform(
          vertex.getUniformSlot('Quad'),
          host.emplace(_floats([-1, -1, 1, 1, 0.5, 0, 0, 0])),
        );
      expect(() => pass.draw(4), draw);
      commands.submit();
      return pixel(color, 1, 1);
    }

    const red = [255, 0, 0, 255];
    final refused = throwsA(isA<Exception>());

    // Caught from the WGSL before the pipeline is built, so even the first
    // frame keeps its red quad.
    final mismatched = gpu.gpuContext.createRenderPipeline(
      vertex,
      library['MismatchedFragment']!,
    );
    expect(await frame(mismatched, refused), red);
    expect(await frame(mismatched, refused), red);

    // Only WebGPU's asynchronous validation catches this one, so the first
    // frame draws with it (and loses its command buffer); once validation
    // has reported, later frames refuse it.
    final invalid = gpu.gpuContext.createRenderPipeline(
      vertex,
      library['UintFragment']!,
    );
    await frame(invalid, returnsNormally);
    expect(await frame(invalid, refused), red);
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

  test(
    'DeviceBuffer.overwrite preserves neighbor bytes across aligned, unaligned, and float-backed writes',
    () async {
      const totalLen = 4096;
      final expected = Uint8List(totalLen);
      final staging = ByteData(totalLen);
      for (var i = 0; i < totalLen; i++) {
        final v = (i * 73 + 19) & 0xff;
        expected[i] = v;
        staging.setUint8(i, v);
      }

      final devBuf = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        totalLen,
      );
      expect(
        devBuf.overwrite(ByteData.sublistView(staging, 0, totalLen)),
        isTrue,
      );

      void applyPatch(int offset, List<int> patchBytes) {
        final patch = ByteData(patchBytes.length);
        for (var i = 0; i < patchBytes.length; i++) {
          patch.setUint8(i, patchBytes[i]);
          expected[offset + i] = patchBytes[i];
        }
        expect(
          devBuf.overwrite(patch, destinationOffsetInBytes: offset),
          isTrue,
        );
      }

      applyPatch(1, [0xaa, 0xbb]);
      applyPatch(3, [1, 2, 3, 4, 5, 6, 7]);
      applyPatch(17, [9, 8, 7, 6, 5]);

      final floats = Float32List.fromList([1.5, -2.25, 3.75, 16.0]);
      final floatBytes = floats.buffer.asUint8List();
      for (var i = 0; i < floatBytes.length; i++) {
        expected[64 + i] = floatBytes[i];
      }
      expect(
        devBuf.overwrite(
          ByteData.sublistView(floats),
          destinationOffsetInBytes: 64,
        ),
        isTrue,
      );

      final actual = await webGpuReadBuffer(devBuf, length: totalLen);
      expect(actual, expected);

      final geom = gpu.createGeometryBuffers(16, 10);
      final idxSrc = Uint16List.fromList([10, 20, 30, 40, 50]);
      expect(
        gpu.writeGeometryData(
          geom.index,
          idxSrc,
          destinationOffsetInBytes: geom.indexBaseOffset,
        ),
        isTrue,
      );
      final geomRead = await webGpuReadBuffer(
        geom.index,
        offset: geom.indexBaseOffset,
        length: 10,
      );
      expect(geomRead, idxSrc.buffer.asUint8List());
    },
  );

  test('cross-stage bindings mirror implicitly, preserve explicit overrides, '
      'and clear cleanly', () async {
    final sharedLib = await webGpuShaderLibraryFromSidecar(
      jsonEncode({
        'format': 2,
        'translator': 'test',
        'bundle': sidecarBundleHash(_bundle),
        'shaders': {
          'SharedVertex': {
            'stage': 'vertex',
            'entryPoint': 'main',
            'wgsl': '''
struct Quad { rect : vec4<f32> }
struct Shared { value : vec4<f32> }
@group(0u) @binding(0u) var<uniform> quad : Quad;
@group(0u) @binding(1u) var<uniform> shared_u : Shared;
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) v_color : vec4<f32>,
  @location(1u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) corner : vec2<f32>) -> Out {
  let p = mix(quad.rect.xy, quad.rect.zw, corner);
  return Out(vec4<f32>(p, 0.5, 1.0), shared_u.value, corner);
}
''',
            'inputs': [
              {'name': 'corner', 'location': 0, 'vecSize': 2, 'offset': 0},
            ],
            'uniforms': [
              {
                'name': 'Quad',
                'group': 0,
                'binding': 0,
                'size': 16,
                'fields': [
                  {'name': 'rect', 'offset': 0},
                ],
              },
              {
                'name': 'Shared',
                'group': 0,
                'binding': 1,
                'size': 16,
                'fields': [
                  {'name': 'value', 'offset': 0},
                ],
              },
            ],
            'textures': <Object?>[],
          },
          'SharedFragment': {
            'stage': 'fragment',
            'entryPoint': 'main',
            'wgsl': '''
struct Shared { value : vec4<f32> }
@group(0u) @binding(64u) var<uniform> shared_u : Shared;
@group(0u) @binding(65u) var albedo : texture_2d<f32>;
@group(0u) @binding(193u) var albedo_sampler : sampler;
@fragment
fn main(
  @location(0u) v_color : vec4<f32>,
  @location(1u) uv : vec2<f32>,
) -> @location(0u) vec4<f32> {
  return (v_color + shared_u.value) *
      textureSampleLevel(albedo, albedo_sampler, uv, 0.0);
}
''',
            'inputs': <Object?>[],
            'uniforms': [
              {
                'name': 'Shared',
                'group': 0,
                'binding': 64,
                'size': 16,
                'fields': [
                  {'name': 'value', 'offset': 0},
                ],
              },
            ],
            'textures': [
              {'name': 'albedo', 'group': 0, 'binding': 65, 'sampler': 193},
            ],
          },
        },
      }),
    );
    final sVert = sharedLib['SharedVertex']!;
    final sFrag = sharedLib['SharedFragment']!;
    await webGpuShaderChecked(sVert);
    await webGpuShaderChecked(sFrag);
    final sPipe = gpu.gpuContext.createRenderPipeline(sVert, sFrag);

    final indexBuf = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Uint16List.fromList([0, 1, 2, 2, 1, 3])),
    );
    final indices = gpu.BufferView(
      indexBuf,
      offsetInBytes: 0,
      lengthInBytes: 12,
    );

    final color = target();
    final host = gpu.gpuContext.createHostBuffer();
    final commands = gpu.gpuContext.createCommandBuffer();
    final pass = commands.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: color, clearValue: vm.Vector4(0, 0, 1, 1)),
      ),
    );

    final quadSlot = sVert.getUniformSlot('Quad');
    final vertShared = sVert.getUniformSlot('Shared');
    final fragShared = sFrag.getUniformSlot('Shared');
    final albedoSlot = sFrag.getUniformSlot('albedo');
    expect(identical(sVert.getUniformSlot('Shared'), vertShared), isTrue);

    // Top-left: binding vertex Shared mirrors implicitly into fragment Shared.
    pass
      ..bindPipeline(sPipe)
      ..bindVertexBuffer(corners)
      ..bindIndexBuffer(indices, gpu.IndexType.int16)
      ..bindUniform(quadSlot, host.emplace(_floats([-1, 0, 0, 1])))
      ..bindUniform(vertShared, host.emplace(_floats([0.5, 0, 0, 0.5])))
      ..bindTexture(albedoSlot, white)
      ..drawIndexed(6);

    // Top-right: explicit fragment Shared is preserved when vertex Shared is
    // bound afterward.
    pass
      ..clearBindings()
      ..bindPipeline(sPipe)
      ..bindVertexBuffer(corners)
      ..bindIndexBuffer(indices, gpu.IndexType.int16)
      ..bindUniform(quadSlot, host.emplace(_floats([0, 0, 1, 1])))
      ..bindUniform(fragShared, host.emplace(_floats([0, 1, 0, 0.5])))
      ..bindUniform(vertShared, host.emplace(_floats([1, 0, 0, 0.5])))
      ..bindTexture(albedoSlot, white)
      ..drawIndexed(6);

    // Bottom-left: clearBindings drops Shared from both stages -> zero.
    pass
      ..clearBindings()
      ..bindPipeline(sPipe)
      ..bindVertexBuffer(corners)
      ..bindIndexBuffer(indices, gpu.IndexType.int16)
      ..bindUniform(quadSlot, host.emplace(_floats([-1, -1, 0, 0])))
      ..bindTexture(albedoSlot, white)
      ..drawIndexed(6);

    commands.submit();
    expect(await pixel(color, 0, 0), [255, 0, 0, 255]);
    expect(await pixel(color, 3, 0), [255, 255, 0, 255]);
    expect(await pixel(color, 0, 3), [0, 0, 0, 0]);
    expect(await pixel(color, 3, 3), [0, 0, 255, 255]);
  });

  test(
    'reloading a shader updates cached uniform slots and pipeline bindings',
    () async {
      String reloadSidecar({required int binding, required String expr}) =>
          jsonEncode({
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
              'ReloadFragment': {
                'stage': 'fragment',
                'entryPoint': 'main',
                'wgsl':
                    '''
struct Tint { color : vec4<f32> }
@group(0u) @binding(${binding}u) var<uniform> tint : Tint;
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  return $expr;
}
''',
                'inputs': <Object?>[],
                'uniforms': [
                  {
                    'name': 'Tint',
                    'group': 0,
                    'binding': binding,
                    'size': 16,
                    'fields': [
                      {'name': 'color', 'offset': 0},
                    ],
                  },
                ],
                'textures': <Object?>[],
              },
            },
          });

      final reloadLib = await webGpuShaderLibraryFromSidecar(
        reloadSidecar(binding: 64, expr: 'tint.color'),
      );
      final rVert = reloadLib['QuadVertex']!;
      final rFrag = reloadLib['ReloadFragment']!;
      await webGpuShaderChecked(rVert);
      await webGpuShaderChecked(rFrag);
      final rPipe = gpu.gpuContext.createRenderPipeline(rVert, rFrag);
      final quadSlot = rVert.getUniformSlot('Quad');
      final tintSlot = rFrag.getUniformSlot('Tint');

      Future<List<int>> drawOnce() async {
        final out = target();
        final host = gpu.gpuContext.createHostBuffer();
        final commands = gpu.gpuContext.createCommandBuffer();
        commands.createRenderPass(
            gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: out)),
          )
          ..bindPipeline(rPipe)
          ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
          ..bindVertexBuffer(corners)
          ..bindUniform(
            quadSlot,
            host.emplace(_floats([-1, -1, 1, 1, 0.5, 0, 0, 0])),
          )
          ..bindUniform(tintSlot, host.emplace(_floats([1, 0, 0, 1])))
          ..draw(4);
        commands.submit();
        return pixel(out, 1, 1);
      }

      expect(await drawOnce(), [255, 0, 0, 255]);

      await webGpuReloadShaderLibrary(
        reloadLib,
        reloadSidecar(binding: 66, expr: 'tint.color.bgra'),
      );
      expect(await drawOnce(), [0, 0, 255, 255]);
    },
  );
}
