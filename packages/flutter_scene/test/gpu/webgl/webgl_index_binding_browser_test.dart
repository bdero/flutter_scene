// An index buffer upload between draws on the WebGL2 backend must not
// re-point the index buffer of the vertex array the last draw left bound.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_index_binding_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/_gpu.dart' show useWebGpuBackend;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

// Leaves out the uint64 reflection fields so dart2js can build it too. The
// explicit vertex layout supplies the attribute's format and offset.
Uint8List _bundle() {
  fb.ShaderObjectBuilder shader(
    String name,
    fb.ShaderStage stage,
    String source, {
    List<fb.ShaderInputObjectBuilder> inputs = const [],
  }) => fb.ShaderObjectBuilder(
    name: name,
    openglEs: fb.BackendShaderObjectBuilder(
      stage: stage,
      entrypoint: 'main',
      inputs: inputs,
      uniformStructs: const [],
      uniformTextures: const [],
      shader: utf8.encode(source),
    ),
  );
  return fb.ShaderBundleObjectBuilder(
    formatVersion: 2,
    shaders: [
      shader(
        'PointVertex',
        fb.ShaderStage.kVertex,
        '#version 100\nattribute vec2 position;\n'
            'void main() { gl_Position = vec4(position, 0.0, 1.0); }\n',
        inputs: [fb.ShaderInputObjectBuilder(name: 'position')],
      ),
      shader(
        'WhiteFragment',
        fb.ShaderStage.kFragment,
        '#version 100\nprecision mediump float;\n'
            'void main() { gl_FragColor = vec4(1.0); }\n',
      ),
      shader(
        'StateVertex',
        fb.ShaderStage.kVertex,
        '#version 100\nattribute vec4 position;\n'
            'varying vec4 v_color;\n'
            'void main() { gl_Position = vec4(position.xyz, 1.0); '
            'v_color = mod(floor(position.wwww / '
            'vec4(4096.0, 256.0, 16.0, 1.0)), 16.0) / 8.0; }\n',
        inputs: [fb.ShaderInputObjectBuilder(name: 'position')],
      ),
      shader(
        'StateFragment',
        fb.ShaderStage.kFragment,
        '#version 100\nprecision mediump float;\n'
            'varying vec4 v_color;\n'
            'void main() { gl_FragColor = v_color; }\n',
      ),
    ],
  ).toBytes();
}

gpu.BufferView _view(TypedData data) => gpu.BufferView(
  gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(data)),
  offsetInBytes: 0,
  lengthInBytes: data.lengthInBytes,
);

class _StateFixture {
  _StateFixture(this.pipeline)
    : color = gpu.gpuContext.createTexture(gpu.StorageMode.devicePrivate, 4, 4),
      depth = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
        format: gpu.gpuContext.defaultDepthStencilFormat,
      ),
      commands = gpu.gpuContext.createCommandBuffer();

  final gpu.RenderPipeline pipeline;
  final gpu.Texture color, depth;
  final gpu.CommandBuffer commands;
  final List<gpu.DeviceBuffer> buffers = [];

  gpu.RenderPass pass({
    gpu.LoadAction colorLoad = gpu.LoadAction.clear,
    gpu.LoadAction depthLoad = gpu.LoadAction.clear,
  }) => commands.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: color, loadAction: colorLoad),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthLoadAction: depthLoad,
        depthStoreAction: gpu.StoreAction.store,
        depthClearValue: 1,
      ),
    ),
  );

  void draw(gpu.RenderPass pass, List<double> color, {double z = .5}) {
    final packed = color.fold<int>(
      0,
      (value, channel) => value * 16 + (channel * 8).round(),
    );
    final data = Float32List.fromList([
      for (final xy in const [
        [-1.0, -1.0],
        [1.0, -1.0],
        [1.0, 1.0],
        [-1.0, -1.0],
        [1.0, 1.0],
        [-1.0, 1.0],
      ]) ...[...xy, z, packed.toDouble()],
    ]);
    final view = _view(data);
    buffers.add(view.buffer);
    pass
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(view)
      ..draw(6);
  }

  void expectPixel(List<int> expected) {
    final gl = (gpu.gpuContext as WebGlContext).gl;
    final pixel = JSUint8Array.withLength(4);
    gl.readPixels(
      1,
      1,
      1,
      1,
      web.WebGL2RenderingContext.RGBA,
      web.WebGL2RenderingContext.UNSIGNED_BYTE,
      pixel,
    );
    final actual = pixel.toDart;
    for (var channel = 0; channel < 4; channel++) {
      expect(actual[channel], closeTo(expected[channel], 1));
    }
    expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
  }

  void dispose() {
    commands.submit();
    buffers.forEach(gpu.gpuHost.releaseBuffer);
    gpu.gpuHost.releaseTexture(color);
    gpu.gpuHost.releaseTexture(depth);
  }
}

void main() {
  if (useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  test(
    'an upload to an index buffer leaves the bound vertex array alone',
    () async {
      await gpu.initializeGpuBackend();
      final library = (await gpu.loadShaderLibraryFromBytesAsync(
        ByteData.sublistView(_bundle()),
      ))!;
      final pipeline = gpu.gpuContext.createRenderPipeline(
        library['PointVertex']!,
        library['WhiteFragment']!,
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
      );
      final vertices = _view(Float32List.fromList([0, 0, 1, 0, 0, 1]));
      final sixIndices = _view(Uint16List.fromList([0, 1, 2, 0, 1, 2]));
      final threeIndices = _view(Uint16List.fromList([0, 1, 2]));
      final gl = (gpu.gpuContext as WebGlContext).gl;

      final color = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
      );
      final commands = gpu.gpuContext.createCommandBuffer();
      final pass = commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: color)),
      );
      void drawWith(gpu.BufferView indices, int count) => pass
        ..bindPipeline(pipeline)
        ..bindVertexBuffer(vertices)
        ..bindIndexBuffer(indices, gpu.IndexType.int16)
        ..drawIndexed(count);

      // The second draw leaves its cached vertex array bound when the upload
      // to the first draw's index buffer runs.
      drawWith(threeIndices, 3);
      drawWith(sixIndices, 6);
      threeIndices.buffer.overwrite(
        ByteData.sublistView(Uint16List.fromList([2, 1, 0])),
      );
      while (gl.getError() != web.WebGL2RenderingContext.NO_ERROR) {}
      drawWith(sixIndices, 6);
      expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
      commands.submit();
    },
  );

  group('fixed state', () {
    late _StateFixture fixture;
    setUp(() async {
      await gpu.initializeGpuBackend();
      final library = (await gpu.loadShaderLibraryFromBytesAsync(
        ByteData.sublistView(_bundle()),
      ))!;
      fixture = _StateFixture(
        gpu.gpuContext.createRenderPipeline(
          library['StateVertex']!,
          library['StateFragment']!,
          vertexLayout: const gpu.VertexLayout(
            buffers: [
              gpu.VertexBuffer(
                strideInBytes: 16,
                attributes: [
                  gpu.VertexAttribute(
                    name: 'position',
                    format: gpu.VertexFormat.float32x4,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      addTearDown(fixture.dispose);
    });

    test('repeated blend states and mutable equations preserve pixels', () {
      final pass = fixture.pass()
        ..setDepthCompareOperation(gpu.CompareFunction.always)
        ..setDepthWriteEnable(false)
        ..setColorBlendEnable(false)
        ..setColorBlendEnable(false);
      fixture.draw(pass, [1, 0, 0, 1]);
      fixture.expectPixel([255, 0, 0, 255]);

      final equation = gpu.ColorBlendEquation();
      pass
        ..setColorBlendEnable(true)
        ..setColorBlendEnable(true)
        ..setColorBlendEquation(equation)
        ..setColorBlendEquation(equation);
      fixture.draw(pass, [0, 0, .5, .5]);
      fixture.expectPixel([128, 0, 128, 255]);

      equation
        ..destinationColorBlendFactor = gpu.BlendFactor.one
        ..destinationAlphaBlendFactor = gpu.BlendFactor.one;
      pass
        ..setColorBlendEquation(equation)
        ..setColorBlendEquation(equation);
      fixture.draw(pass, [0, .25, 0, .25]);
      fixture.expectPixel([128, 64, 128, 255]);

      equation
        ..colorBlendOperation = gpu.BlendOperation.reverseSubtract
        ..alphaBlendOperation = gpu.BlendOperation.reverseSubtract;
      pass
        ..setColorBlendEquation(equation)
        ..setColorBlendEquation(equation);
      fixture.draw(pass, [0, .125, 0, .25]);
      fixture.expectPixel([128, 32, 128, 191]);

      final next = fixture.pass(colorLoad: gpu.LoadAction.load)
        ..setDepthCompareOperation(gpu.CompareFunction.always)
        ..setColorBlendEnable(false)
        ..setColorBlendEnable(false);
      fixture.draw(next, [1, 1, 0, .5]);
      fixture.expectPixel([255, 255, 0, 128]);
    });

    test('depth transitions survive load clears and disabled writes', () {
      final pass = fixture.pass()
        ..setColorBlendEnable(false)
        ..setDepthWriteEnable(true)
        ..setDepthWriteEnable(true)
        ..setDepthCompareOperation(gpu.CompareFunction.less)
        ..setDepthCompareOperation(gpu.CompareFunction.less);
      fixture.draw(pass, [1, 0, 0, 1], z: .2);
      fixture.draw(pass, [0, 1, 0, 1], z: .8);
      fixture.expectPixel([255, 0, 0, 255]);

      pass
        ..setDepthWriteEnable(false)
        ..setDepthWriteEnable(false)
        ..setDepthCompareOperation(gpu.CompareFunction.greater)
        ..setDepthCompareOperation(gpu.CompareFunction.greater);
      fixture.draw(pass, [0, 0, 1, 1], z: .8);
      pass
        ..setDepthCompareOperation(gpu.CompareFunction.less)
        ..setDepthCompareOperation(gpu.CompareFunction.less);
      fixture.draw(pass, [0, 1, 0, 1], z: .5);
      fixture.expectPixel([0, 0, 255, 255]);

      final cleared = fixture.pass()
        ..setColorBlendEnable(false)
        ..setDepthWriteEnable(false)
        ..setDepthWriteEnable(false)
        ..setDepthCompareOperation(gpu.CompareFunction.less);
      fixture.draw(cleared, [1, 0, 0, 1], z: .2);
      fixture.draw(cleared, [0, 0, 1, 1], z: .8);
      fixture.expectPixel([0, 0, 255, 255]);

      final loaded = fixture.pass(depthLoad: gpu.LoadAction.load)
        ..setColorBlendEnable(false)
        ..setDepthWriteEnable(true)
        ..setDepthWriteEnable(true)
        ..setDepthCompareOperation(gpu.CompareFunction.less);
      fixture.draw(loaded, [0, 1, 0, 1], z: .5);
      fixture.draw(loaded, [1, 0, 0, 1], z: .8);
      fixture.expectPixel([0, 255, 0, 255]);

      final retained = fixture.pass(depthLoad: gpu.LoadAction.load)
        ..setColorBlendEnable(false)
        ..setDepthWriteEnable(false)
        ..setDepthCompareOperation(gpu.CompareFunction.less);
      fixture.draw(retained, [1, 0, 0, 1], z: .8);
      fixture.expectPixel([0, 0, 0, 0]);
    });

    test('culling and winding transitions reset across passes', () {
      final pass = fixture.pass()
        ..setColorBlendEnable(false)
        ..setDepthCompareOperation(gpu.CompareFunction.always)
        ..setCullMode(gpu.CullMode.backFace)
        ..setCullMode(gpu.CullMode.backFace)
        ..setWindingOrder(gpu.WindingOrder.clockwise)
        ..setWindingOrder(gpu.WindingOrder.clockwise);
      fixture.draw(pass, [1, 0, 0, 1]);
      fixture.expectPixel([255, 0, 0, 255]);
      pass
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise);
      fixture.draw(pass, [0, 1, 0, 1]);
      fixture.expectPixel([255, 0, 0, 255]);
      pass
        ..setCullMode(gpu.CullMode.frontFace)
        ..setCullMode(gpu.CullMode.frontFace);
      fixture.draw(pass, [0, 1, 0, 1]);
      fixture.expectPixel([0, 255, 0, 255]);
      pass
        ..setWindingOrder(gpu.WindingOrder.clockwise)
        ..setWindingOrder(gpu.WindingOrder.clockwise);
      fixture.draw(pass, [0, 0, 1, 1]);
      fixture.expectPixel([0, 255, 0, 255]);
      pass
        ..setCullMode(gpu.CullMode.none)
        ..setCullMode(gpu.CullMode.none);
      fixture.draw(pass, [0, 0, 1, 1]);
      fixture.expectPixel([0, 0, 255, 255]);
      pass
        ..setCullMode(gpu.CullMode.backFace)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise);

      final next = fixture.pass()
        ..setColorBlendEnable(false)
        ..setDepthCompareOperation(gpu.CompareFunction.always);
      fixture.draw(next, [1, 0, 0, 1]);
      fixture.expectPixel([255, 0, 0, 255]);
      next
        ..setCullMode(gpu.CullMode.backFace)
        ..setCullMode(gpu.CullMode.backFace)
        ..setWindingOrder(gpu.WindingOrder.clockwise)
        ..setWindingOrder(gpu.WindingOrder.clockwise);
      fixture.draw(next, [0, 1, 0, 1]);
      fixture.expectPixel([0, 255, 0, 255]);
    });
  });
}
