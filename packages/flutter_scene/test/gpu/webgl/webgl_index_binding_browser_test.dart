// A buffer upload between draws on the WebGL2 backend leaves the index
// buffer of every cached vertex array as the draw that cached it bound it.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_index_binding_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

// No uint64 reflection field is written, so dart2js builds it too: the
// explicit vertex layout supplies the format and offset, location is 0.
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
    ],
  ).toBytes();
}

gpu.BufferView _view(TypedData data) => gpu.BufferView(
  gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(data)),
  offsetInBytes: 0,
  lengthInBytes: data.lengthInBytes,
);

void main() {
  if (gpu.useWebGpuBackend) {
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
}
