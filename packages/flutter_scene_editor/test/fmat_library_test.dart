// EditorFmatLibrary end to end against real files: compile-on-load, the
// file watcher's in-place hot swap, error keep-last-good, and structural
// (rename) fallback. Needs a GPU context (run with --enable-flutter-gpu)
// plus impellerc; skips otherwise.
import 'dart:async';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/src/materials/fmat_library.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:scene/scene.dart' show AssetRef;

String _source({String name = 'WatchTest', String strengthDefault = '0.5'}) =>
    '''
material {
  name: "$name",
  shading_model: unlit,
  parameters: [
    { type: float, name: strength, hint: range(0, 1, 0.01), default: $strengthDefault },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(vec3(material_params.strength), 1.0);
    PrepareMaterial(material);
  }
}
''';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  var impellercFound = true;
  try {
    await findImpellerC();
  } catch (_) {
    impellercFound = false;
  }
  final skip = !_gpuAvailable()
      ? 'no GPU context in this environment'
      : !impellercFound
      ? 'impellerc not found in the SDK cache'
      : false;

  late Directory sceneDir;
  late EditorFmatLibrary library;
  final reloads = StreamController<void>.broadcast();
  final errors = <String>[];
  var structuralChanges = 0;

  setUp(() {
    sceneDir = Directory.systemTemp.createTempSync('fmat_watch_test_');
    errors.clear();
    structuralChanges = 0;
    library = EditorFmatLibrary(
      resolvePath: (key) => key.startsWith('/') ? key : '${sceneDir.path}/$key',
      onReload: () => reloads.add(null),
      onError: errors.add,
      onStructuralChange: () async => structuralChanges++,
    );
  });

  tearDown(() {
    library.dispose();
    sceneDir.deleteSync(recursive: true);
  });

  Future<void> nextReload() =>
      reloads.stream.first.timeout(const Duration(seconds: 15));

  test(
    'loads from disk, hot swaps on edit, and keeps last good on error',
    () async {
      final file = File('${sceneDir.path}/watch.fmat')
        ..writeAsStringSync(_source());
      final material = await library.loadMaterial(const AssetRef('watch.fmat'));
      expect(material, isNotNull);
      expect(material!.parameters.parameterNames, contains('strength'));
      expect(library.errorForKey('watch.fmat'), isNull);
      expect(library.metadataForKey('watch.fmat'), isNotNull);
      final shader = material.fragmentShader;

      // An edit recompiles and refreshes the same instance in place.
      var reload = nextReload();
      file.writeAsStringSync(_source(strengthDefault: '0.9'));
      await reload;
      expect(identical(material.fragmentShader, shader), isTrue);
      expect(library.errorForKey('watch.fmat'), isNull);

      // A broken edit keeps the last good shaders and records the error.
      file.writeAsStringSync('material {');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(library.errorForKey('watch.fmat'), isNotNull);
      expect(errors, isNotEmpty);

      // Fixing it clears the error. The library reloaded fresh (the broken
      // state dropped the in-place path), so a structural rebuild was asked
      // for; either signal proves recovery.
      reload = nextReload();
      file.writeAsStringSync(_source(strengthDefault: '0.2'));
      await Future.any([
        reload,
        Future<void>.delayed(const Duration(seconds: 15)),
      ]);
      expect(library.errorForKey('watch.fmat'), isNull);
    },
    skip: skip,
  );

  test('a renamed material triggers a structural rebuild', () async {
    final file = File('${sceneDir.path}/rename.fmat')
      ..writeAsStringSync(_source());
    final material = await library.loadMaterial(const AssetRef('rename.fmat'));
    expect(material, isNotNull);

    file.writeAsStringSync(_source(name: 'WatchTestRenamed'));
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (structuralChanges == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(structuralChanges, greaterThan(0));
    expect(library.errorForKey('rename.fmat'), isNull);
  }, skip: skip);
}
