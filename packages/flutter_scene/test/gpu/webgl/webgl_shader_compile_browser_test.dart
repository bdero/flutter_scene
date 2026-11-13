// The WebGL2 backend compiles a shader where it is first looked up, not
// every shader of its bundle at load, and a hot reload of its asset reaches
// a shader first looked up after it.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_shader_compile_browser_test.dart
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
  const vertex =
      '#version 100\nattribute vec2 position;\n'
      'void main() { gl_Position = vec4(position, 0.0, 1.0); }\n';
  final fragment =
      '#version 100\nprecision mediump float;\n'
      'void main() { gl_FragColor = vec4($color); }\n';
  return fb.ShaderBundleObjectBuilder(
    formatVersion: 2,
    shaders: [
      shader('PointVertex', fb.ShaderStage.kVertex, vertex),
      shader('WhiteFragment', fb.ShaderStage.kFragment, fragment),
      shader('UnusedFragment', fb.ShaderStage.kFragment, fragment),
    ],
  ).toBytes();
}

Future<gpu.ShaderLibrary> _library() async => (await gpu
    .loadShaderLibraryFromBytesAsync(ByteData.sublistView(_bundle())))!;

void main() {
  if (gpu.useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  setUpAll(gpu.initializeGpuBackend);

  test('a library compiles only the shaders looked up', () async {
    final gl = (gpu.gpuContext as WebGlContext).gl as JSObject;
    final compileShader = gl['compileShader']! as JSFunction;
    var compiles = 0;
    gl['compileShader'] = ((JSAny? shader) {
      compiles++;
      compileShader.callAsFunction(gl, shader);
    }).toJS;
    final library = await _library();
    expect(compiles, 0);
    library['PointVertex'];
    library['PointVertex'];
    expect(compiles, 1);
    gl.delete('compileShader'.toJS);
  });

  test('a shader that fails to compile throws on every lookup', () async {
    final library = (await gpu.loadShaderLibraryFromBytesAsync(
      ByteData.sublistView(_bundle(color: 'missing')),
    ))!;
    expect(() => library['WhiteFragment'], throwsException);
    expect(() => library['WhiteFragment'], throwsException);
    expect(library['NoSuchShader'], isNull);
  });

  test(
    'a shader first looked up after a reload compiles the new source',
    () async {
      final window = web.window as JSObject;
      final fetch = window['fetch']! as JSFunction;
      var bundle = _bundle(color: '0.25');
      window['fetch'] = ((JSAny? _, JSAny? _) => Future<JSAny?>.value(
        web.Response(bundle.toJS),
      ).toJS).toJS;
      final gl = (gpu.gpuContext as WebGlContext).gl as JSObject;
      final shaderSource = gl['shaderSource']! as JSFunction;
      final sources = <String>[];
      gl['shaderSource'] = ((JSAny? shader, JSString source) {
        sources.add(source.toDart);
        shaderSource.callAsFunction(gl, shader, source);
      }).toJS;
      try {
        final first = (await gpu.loadShaderLibraryAsync(
          'reload_test.shaderbundle',
        ))!;
        final second = (await gpu.loadShaderLibraryAsync(
          'reload_test.shaderbundle',
        ))!;
        bundle = _bundle(color: '0.75');
        await gpu.reinitializeShaderLibraryAsync('reload_test.shaderbundle');
        first['UnusedFragment'];
        second['UnusedFragment'];
        expect(sources, hasLength(2));
        expect(sources, everyElement(contains('0.75')));
      } finally {
        window['fetch'] = fetch;
        gl.delete('shaderSource'.toJS);
      }
    },
  );
}
