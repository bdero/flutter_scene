// The WebGPU backend's shader libraries, built from WGSL sidecars.
//
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/webgpu/webgpu_shader_library_browser_test.dart
//
// The last test compiles a real sidecar (every engine shader) when one is
// served at FLUTTER_SCENE_SIDECAR_URL, with CORS, and skips otherwise. Make
// one with tool/build_wgsl_sidecar.dart over an untrimmed bundle.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _sidecarUrl = String.fromEnvironment('FLUTTER_SCENE_SIDECAR_URL');

final Uint8List _bundle = Uint8List.fromList(utf8.encode('a stand-in bundle'));

const _vertexWgsl = '''
struct FrameInfo { mvp : mat4x4<f32>, tint : vec4<f32> }
@group(0) @binding(0) var<uniform> frame : FrameInfo;
@vertex
fn main(@location(0u) position : vec3<f32>, @location(1u) uv : vec2<f32>)
    -> @builtin(position) vec4<f32> {
  return frame.mvp * vec4<f32>(position + vec3<f32>(uv, 0.0), 1.0);
}
''';

const _fragmentWgsl = '''
@group(0) @binding(65) var albedo : texture_2d<f32>;
@group(0) @binding(193) var albedo_sampler : sampler;
@fragment
fn main() -> @location(0) vec4<f32> {
  return textureSample(albedo, albedo_sampler, vec2<f32>(0.5));
}
''';

String _sidecar({
  String vertex = _vertexWgsl,
  int format = 2,
  String? bundleHash,
}) => jsonEncode({
  'format': format,
  'translator': 'test',
  'bundle': bundleHash ?? sidecarBundleHash(_bundle),
  'shaders': {
    'TestVertex': {
      'stage': 'vertex',
      'entryPoint': 'main',
      'wgsl': vertex,
      'inputs': [
        {'name': 'position', 'location': 0, 'vecSize': 3, 'offset': 0},
        {'name': 'uv', 'location': 1, 'vecSize': 2, 'offset': 12},
      ],
      'uniforms': [
        {
          'name': 'FrameInfo',
          'group': 0,
          'binding': 0,
          'size': 80,
          'fields': [
            {'name': 'mvp', 'offset': 0},
            {'name': 'tint', 'offset': 64},
          ],
        },
      ],
      'textures': <Object?>[],
    },
    'TestFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _fragmentWgsl,
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': [
        {'name': 'albedo', 'group': 0, 'binding': 65, 'sampler': 193},
      ],
    },
  },
});

void main() {
  if (!gpu.useWebGpuBackend) {
    test('needs --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGL2 in this build.');
    });
    return;
  }

  setUpAll(() => gpu.initializeGpuBackend());

  test('the bundle hash matches FNV-1a test vectors in the browser', () {
    expect(sidecarBundleHash(<int>[]), '811c9dc5');
    expect(sidecarBundleHash(utf8.encode('a')), 'e40c292c');
    expect(sidecarBundleHash(utf8.encode('foobar')), 'bf9cf968');
  });

  test('compiles shaders and answers reflection from the sidecar', () async {
    final library = await webGpuShaderLibraryFromSidecar(_bundle, _sidecar());
    final vertex = library['TestVertex']!;
    final fragment = library['TestFragment']!;
    expect(vertex.stage, gpu.ShaderStage.vertex);
    expect(fragment.stage, gpu.ShaderStage.fragment);
    expect(library['Missing'], isNull);

    final slot = vertex.getUniformSlot('FrameInfo');
    expect(slot.sizeInBytes, 80);
    expect(slot.getMemberOffsetInBytes('tint'), 64);
    expect(slot.getMemberOffsetInBytes('nope'), isNull);
    expect(vertex.getUniformSlot('Absent').sizeInBytes, isNull);

    final described = webGpuDescribeShader(vertex);
    expect(described.inputs, [('position', 0), ('uv', 1)]);
    expect(described.vertexStride, 20);
    expect(described.generation, 1);
    expect(webGpuDescribeShader(fragment).textures, [('albedo', 65, 193)]);
  });

  test('refuses a sidecar built with another bundle', () {
    expect(
      webGpuShaderLibraryFromSidecar(_bundle, _sidecar(bundleHash: 'stale')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('stale'),
        ),
      ),
    );
  });

  test('refuses an older sidecar format', () {
    expect(
      webGpuShaderLibraryFromSidecar(_bundle, _sidecar(format: 1)),
      throwsA(isA<StateError>()),
    );
  });

  test('reports a WGSL compile error with the shader name', () {
    expect(
      webGpuShaderLibraryFromSidecar(_bundle, _sidecar(vertex: 'fn broken( {')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('TestVertex'),
        ),
      ),
    );
  });

  test('every shader of a real sidecar compiles', () async {
    if (_sidecarUrl.isEmpty) {
      markTestSkipped('Set FLUTTER_SCENE_SIDECAR_URL to a served sidecar.');
      return;
    }
    final response = await web.window.fetch(_sidecarUrl.toJS).toDart;
    final json = (jsonDecode((await response.text().toDart).toDart) as Map)
      ..['bundle'] = sidecarBundleHash(_bundle);
    final count = (json['shaders'] as Map).length;
    final library = await webGpuShaderLibraryFromSidecar(
      _bundle,
      jsonEncode(json),
    );
    for (final name in (json['shaders'] as Map).keys) {
      expect(library[name as String], isNotNull, reason: name);
    }
    // ignore: avoid_print
    print('SIDECAR compiled $count shaders');
  });
}
