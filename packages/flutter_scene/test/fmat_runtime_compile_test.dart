// FmatRuntimeCompiler against the SDK cache's impellerc: bundle output, the
// sidecar shape, disk caching, and the error paths. Runs only when impellerc
// resolves (CI without engine artifacts skips).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/fmat/fmat_ast.dart' show FmatException;
import 'package:flutter_scene/src/fmat/runtime_compile.dart';
import 'package:flutter_test/flutter_test.dart';

const _surface = '''
material {
  name: "RuntimeTest",
  shading_model: unlit,
  parameters: [
    { type: vec4, name: tint, hint: source_color, default: [1.0, 0.0, 0.0, 1.0] },
    { type: float, name: strength, hint: range(0, 1, 0.01), default: 0.5 },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = material_params.tint * material_params.strength;
    PrepareMaterial(material);
  }
}
''';

const _sky = '''
material {
  name: "RuntimeTestSky",
  parameters: [
    { type: vec3, name: zenith, default: [0.1, 0.2, 0.8] },
  ],
}

sky {
  vec3 Sky(vec3 direction) {
    return material_params.zenith * max(direction.y, 0.0);
  }
}
''';

const _broken = '''
material {
  name: "RuntimeBroken",
  shading_model: unlit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = not_a_function(1.0);
  }
}
''';

void main() async {
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    impellerc = null;
  }
  final skip = impellerc == null
      ? 'impellerc not found in the SDK cache'
      : false;

  late Directory cacheDir;
  late FmatRuntimeCompiler compiler;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('fmat_compile_test_');
    compiler = FmatRuntimeCompiler(
      impellerc: impellerc ?? Uri.file('/nonexistent'),
      includeDirectories: [Directory('shaders').absolute.uri],
      cacheDirectory: cacheDir,
    );
  });

  tearDown(() => cacheDir.deleteSync(recursive: true));

  test('compiles a surface material to a shader bundle plus sidecar', () async {
    final result = await compiler.compile(_surface, fileName: 'test.fmat');
    expect(result.entryName, 'RuntimeTest');
    // The flatbuffer file identifier sits after the root offset.
    expect(
      utf8.decode(Uint8List.sublistView(result.shaderBundle, 4, 8)),
      'IPSB',
    );
    final metadata = (result.sidecar['RuntimeTest'] as Map)
        .cast<String, Object?>();
    expect(metadata['domain'], 'surface');
    expect(metadata['shading_model'], 'unlit');
    final names = [
      for (final p in metadata['parameters'] as List) (p as Map)['name'],
    ];
    expect(names, containsAll(['tint', 'strength']));
    // The depfile-tracked framework includes are watchable inputs.
    expect(result.includeDependencies, isNotEmpty);
    for (final path in result.includeDependencies) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  }, skip: skip);

  test('compiles a sky material', () async {
    final result = await compiler.compile(_sky, fileName: 'sky.fmat');
    final metadata = (result.sidecar['RuntimeTestSky'] as Map)
        .cast<String, Object?>();
    expect(metadata['domain'], 'sky');
  }, skip: skip);

  test('serves an unchanged source from the disk cache', () async {
    await compiler.compile(_surface, fileName: 'test.fmat');
    // Prove the second compile reads the cached bundle: overwrite it on disk
    // with a sentinel and observe the sentinel coming back.
    final cached = cacheDir
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('out.shaderbundle'));
    cached.writeAsBytesSync([1, 2, 3, 4]);
    final again = await compiler.compile(_surface, fileName: 'test.fmat');
    expect(Uint8List.sublistView(again.shaderBundle), [1, 2, 3, 4]);

    // An edited source misses the cache and compiles a real bundle again.
    final edited = await compiler.compile(
      _surface.replaceFirst('0.5', '0.75'),
      fileName: 'test.fmat',
    );
    expect(edited.shaderBundle.lengthInBytes, greaterThan(1000));
  }, skip: skip);

  test('reports GLSL errors as FmatCompileException', () async {
    await expectLater(
      compiler.compile(_broken, fileName: 'broken.fmat'),
      throwsA(isA<FmatCompileException>()),
    );
  }, skip: skip);

  test('reports source errors as FmatException', () async {
    await expectLater(
      compiler.compile('material {', fileName: 'parse.fmat'),
      throwsA(isA<FmatException>()),
    );
  }, skip: skip);
}
