// The stage interface check against shaders compiled at test time, on a real
// GPU context. Needs Flutter GPU (run with --enable-flutter-gpu) and impellerc,
// and runs where the check does (Apple platforms); skips elsewhere. The test
// runner's backend cannot load the engine's own bundle, so a test vertex
// shader stands in for the engine's, writing the same seven varyings.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/build.dart'
    show shaderBundleImpellercArguments;
import 'package:flutter_gpu_shaders/environment.dart' show findImpellerC;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/shared/shader_library_sources.dart'
    show ShaderLibrarySource, registerShaderLibrarySource;
import 'package:flutter_scene/src/material/shader_interface.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show tryResolvePipeline;
import 'package:flutter_test/flutter_test.dart';

import 'support/gpu_available.dart';

// Five of the seven engine varyings, the mistake the toon example made, so
// v_color lands on location 4 where the engine writes v_texture_coords_1.
const _partial = '''
in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector;
in vec2 v_texture_coords;
in vec4 v_color;
out vec4 frag_color;
void main() {
  frag_color = v_color * vec4(normalize(v_normal), 1.0);
}
''';

// Writes the seven engine varyings, like the engine's vertex shaders.
const _standardVertex = '''
in vec3 position;
out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;
void main() {
  v_position = position;
  v_normal = vec3(0.0, 0.0, 1.0);
  v_viewvector = vec3(0.0);
  v_texture_coords = vec2(0.0);
  v_texture_coords_1 = vec2(0.0);
  v_color = vec4(1.0);
  v_tangent = vec4(1.0, 0.0, 0.0, 1.0);
  gl_Position = vec4(position, 1.0);
}
''';

// The same fragment shader declaring every engine varying.
const _complete = '''
in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector;
in vec2 v_texture_coords;
in vec2 v_texture_coords_1;
in vec4 v_color;
in vec4 v_tangent;
out vec4 frag_color;
void main() {
  frag_color = v_color * vec4(normalize(v_normal), 1.0);
}
''';

Future<ByteData> _compileBundle(Uri impellerc) async {
  final dir = Directory.systemTemp.createTempSync('shader_interface_test_');
  try {
    final partial = File('${dir.path}/partial.frag')
      ..writeAsStringSync(_partial);
    final complete = File('${dir.path}/complete.frag')
      ..writeAsStringSync(_complete);
    final vertex = File('${dir.path}/standard.vert')
      ..writeAsStringSync(_standardVertex);
    final bundle = File('${dir.path}/test.shaderbundle');
    final result = await Process.run(
      impellerc.toFilePath(),
      shaderBundleImpellercArguments(
        outputBundleFilePath: bundle.uri,
        manifestJson: jsonEncode({
          'PartialFragment': {'type': 'fragment', 'file': partial.path},
          'CompleteFragment': {'type': 'fragment', 'file': complete.path},
          'StandardVertex': {'type': 'vertex', 'file': vertex.path},
        }),
        manifestDirectory: dir.uri,
        shaderLibDirectory: impellerc.resolve('./shader_lib'),
        glesLanguageVersion: 300,
      ),
    );
    if (result.exitCode != 0) {
      throw StateError('impellerc failed: ${result.stderr}${result.stdout}');
    }
    return ByteData.sublistView(bundle.readAsBytesSync());
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    impellerc = null;
  }
  final skip = !gpuAvailable()
      ? 'no GPU context in this environment'
      : impellerc == null
      ? 'impellerc not found in the SDK cache'
      : !checksStageInterfaces
      ? 'the check runs on Apple platforms only'
      : false;

  late ByteData bundleBytes;
  setUpAll(() async {
    if (skip != false) return;
    bundleBytes = await _compileBundle(impellerc!);
  });

  // Each test loads its own library from the same bytes, so one test's parse
  // and rejections do not leak into the next.
  Future<gpu.ShaderLibrary> loadLibrary() async =>
      (await gpu.loadShaderLibraryFromBytesAsync(bundleBytes))!;

  test('a cubemap variant assigned after construction is checked', () async {
    final material = ShaderMaterial();
    final library = await loadLibrary();
    final partial = library['PartialFragment']!;
    material.setRadianceCubeFragmentShader(partial);
    expect(stageInterfacesPending, isTrue);

    await stageInterfacesLoad;
    expect(
      stageInterfaceProblem(library['StandardVertex']!, partial),
      contains(
        'v_color (float4) at location 4, where the vertex shader writes '
        'v_texture_coords_1 (float2)',
      ),
    );
  }, skip: skip);

  test('a pairing waits while its reflection loads, then is checked', () async {
    // An app's libraries load from assets, so their reflection arrives
    // asynchronously; serve this one the same way.
    const assetKey = 'test/stage_interface.shaderbundle';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      return key == assetKey ? bundleBytes : null;
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    final library = await loadLibrary();
    registerShaderLibrarySource(
      library,
      const ShaderLibrarySource(assetKey: assetKey),
    );
    final partial = library['PartialFragment']!;
    final complete = library['CompleteFragment']!;
    final vertex = library['StandardVertex']!;

    ShaderMaterial(fragmentShader: partial);
    ShaderMaterial(fragmentShader: complete);
    expect(stageInterfaceDeferred(vertex, partial), isTrue);
    expect(tryResolvePipeline(vertex, partial), isNull);

    await stageInterfacesLoad;
    expect(stageInterfaceDeferred(vertex, partial), isFalse);
    expect(tryResolvePipeline(vertex, partial), isNull);
    expect(tryResolvePipeline(vertex, complete), isNotNull);
  }, skip: skip);
}
