// The WebGL2 backend issues a program's compile and link without reading
// their results, so the driver can build many in parallel, and reads them at
// the program's first bind, where a failure still reports.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_parallel_compile_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

Uint8List _bundle({String color = '1.0'}) {
  fb.ShaderObjectBuilder shader(
    String name,
    fb.ShaderStage stage,
    String source,
  ) => fb.ShaderObjectBuilder(
    name: name,
    openglEs: fb.BackendShaderObjectBuilder(
      stage: stage,
      entrypoint: 'main',
      inputs: [
        if (stage == fb.ShaderStage.kVertex)
          fb.ShaderInputObjectBuilder(name: 'position'),
      ],
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
      ),
      shader(
        'ColorFragment',
        fb.ShaderStage.kFragment,
        '#version 100\nprecision mediump float;\n'
            'void main() { gl_FragColor = vec4($color); }\n',
      ),
    ],
  ).toBytes();
}

Future<gpu.ShaderLibrary> _library({String color = '1.0'}) async =>
    (await gpu.loadShaderLibraryFromBytesAsync(
      ByteData.sublistView(_bundle(color: color)),
    ))!;

const _vertexLayout = gpu.VertexLayout(
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

gpu.RenderPass _pass() {
  final color = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    4,
    4,
  );
  return gpu.gpuContext.createCommandBuffer().createRenderPass(
    gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: color)),
  );
}

gpu.BufferView _triangle() {
  final data = Float32List.fromList([0, 0, 1, 0, 0, 1]);
  return gpu.BufferView(
    gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(data)),
    offsetInBytes: 0,
    lengthInBytes: data.lengthInBytes,
  );
}

/// Counts the calls that read a compile or link result, or wait on one.
class _StatusQueries {
  _StatusQueries() {
    _wrap('getShaderParameter', (args) {
      if ((args[1] as JSNumber).toDartInt ==
          web.WebGL2RenderingContext.COMPILE_STATUS) {
        count++;
      }
    });
    _wrap('getProgramParameter', (args) {
      if ((args[1] as JSNumber).toDartInt ==
          web.WebGL2RenderingContext.LINK_STATUS) {
        count++;
      }
    });
    for (final name in const [
      'getShaderInfoLog',
      'getProgramInfoLog',
      'getUniformLocation',
      'getUniformBlockIndex',
      'getAttribLocation',
    ]) {
      _wrap(name, (_) => count++);
    }
  }

  final JSObject _gl = (gpu.gpuContext as WebGlContext).gl as JSObject;
  final List<String> _wrapped = [];
  int count = 0;

  void _wrap(String name, void Function(List<JSAny?> args) onCall) {
    final original = _gl[name]! as JSFunction;
    _gl[name] = ((JSAny? a, JSAny? b) {
      onCall([a, b]);
      return original.callAsFunction(_gl, a, b);
    }).toJS;
    _wrapped.add(name);
  }

  void restore() {
    for (final name in _wrapped) {
      _gl.delete(name.toJS);
    }
  }
}

void main() {
  if (gpu.useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  setUpAll(gpu.initializeGpuBackend);

  test('enables KHR_parallel_shader_compile when the browser has it', () {
    final gl = (gpu.gpuContext as WebGlContext).gl;
    final supported =
        gl.getSupportedExtensions()?.toDart.any(
          (name) => name.toDart == 'KHR_parallel_shader_compile',
        ) ??
        false;
    final library = gpu.compileShaderLibraryInline({
      'v': (
        source:
            'attribute vec2 position;\n'
            'void main() { gl_Position = vec4(position, 0.0, 1.0); }\n',
        stage: gpu.ShaderStage.vertex,
      ),
      'f': (
        source:
            'precision mediump float;\n'
            'void main() { gl_FragColor = vec4(1.0); }\n',
        stage: gpu.ShaderStage.fragment,
      ),
    });
    final pipeline =
        gpu.gpuContext.createRenderPipeline(library['v']!, library['f']!)
            as WebGlRenderPipeline;
    // Without the extension there is nothing to poll, so the link always
    // reads as complete. With it, the link finishes on its own.
    if (!supported) {
      expect(pipeline.isLinkComplete, isTrue);
      return;
    }
    final watch = Stopwatch()..start();
    while (!pipeline.isLinkComplete) {
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    }
  });

  test('nothing reads a link result before the first bind', () async {
    final library = await _library();
    final queries = _StatusQueries();
    try {
      final pipeline = gpu.gpuContext.createRenderPipeline(
        library['PointVertex']!,
        library['ColorFragment']!,
        vertexLayout: _vertexLayout,
      );
      expect(queries.count, 0);
      final pass = _pass()..bindPipeline(pipeline);
      expect(queries.count, greaterThan(0));
      final afterFirstBind = queries.count;
      pass
        ..bindVertexBuffer(_triangle())
        ..draw(3)
        ..bindPipeline(pipeline)
        ..draw(3);
      expect(queries.count, afterFirstBind);
    } finally {
      queries.restore();
    }
  });

  test('a shader that fails to compile reports at the draw', () async {
    final library = await _library(color: 'missing');
    expect(library['NoSuchShader'], isNull);
    // Neither the lookup nor the pipeline build waits on the compile.
    final pipeline = gpu.gpuContext.createRenderPipeline(
      library['PointVertex']!,
      library['ColorFragment']!,
      vertexLayout: _vertexLayout,
    );
    final pass = _pass()
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(_triangle());
    // An Exception, not an Error, so the renderer's draw guard skips it, and
    // on every draw, so the guard can reject the pipeline.
    for (var i = 0; i < 2; i++) {
      expect(
        () => pass.draw(3),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            allOf(
              contains('Failed to compile fragment shader'),
              contains('missing'),
            ),
          ),
        ),
      );
    }
    // A working pipeline still draws on the same pass afterwards.
    final good = await _library();
    final gl = (gpu.gpuContext as WebGlContext).gl;
    while (gl.getError() != web.WebGL2RenderingContext.NO_ERROR) {}
    pass
      ..bindPipeline(
        gpu.gpuContext.createRenderPipeline(
          good['PointVertex']!,
          good['ColorFragment']!,
          vertexLayout: _vertexLayout,
        ),
      )
      ..bindVertexBuffer(_triangle())
      ..draw(3);
    expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
  });
}
