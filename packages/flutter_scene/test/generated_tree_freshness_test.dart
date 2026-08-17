// How the hooks decide to redo work: converting, skipping an unchanged source,
// adding, deleting, and moving one, plus the stat-fingerprint rule that keeps a
// multi-gigabyte source from being read on every build.

import 'dart:io';

import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_file_names.dart';
import 'package:flutter_scene/src/importer/build_cache.dart';
import 'package:flutter_scene/src/importer/build_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

/// The committed corpus's smallest scene, copied into each temp package.
final File _corpusGlb = File.fromUri(
  Directory.current.uri.resolve('../../examples/assets_src/two_triangles.glb'),
);

BuildInput _input(Uri packageRoot) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  return builder.build();
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fs_freshness');
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File source(String name) => File.fromUri(temp.uri.resolve('assets/$name'));

  void addScene(String name) {
    source(name)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(_corpusGlb.readAsBytesSync());
  }

  BuildOutput run() {
    final output = BuildOutputBuilder();
    buildScenes(buildInput: _input(temp.uri), buildOutput: output);
    return output.build();
  }

  Uri outputOf(String id) => temp.uri.resolve(
    '$generatedAssetsEntry'
    '${generatedFileName(GeneratedAssetFamily.scene, id, '.fsceneb')}',
  );

  /// A conversion rewrites the output, so its timestamp moving is the signal
  /// that the cache missed (the bytes are identical either way).
  DateTime writtenAt(String id) =>
      File.fromUri(outputOf(id)).statSync().modified;

  GeneratedAssetManifest manifest() => GeneratedAssetManifest.decode(
    File.fromUri(
      temp.uri.resolve('$generatedAssetsEntry$generatedManifestFileName'),
    ).readAsStringSync(),
  )!;

  test('converts a source, then skips it while it is unchanged', () {
    addScene('one.glb');
    run();
    expect(File.fromUri(outputOf('assets/one')).existsSync(), isTrue);
    final first = writtenAt('assets/one');
    run();
    expect(writtenAt('assets/one'), first);
  });

  test('reconverts a changed source', () {
    addScene('one.glb');
    run();
    final first = writtenAt('assets/one');
    source(
      'one.glb',
    ).writeAsBytesSync([...source('one.glb').readAsBytesSync(), 0]);
    run();
    expect(writtenAt('assets/one').isAfter(first), isTrue);
  });

  test('adding a source converts only the new one', () {
    addScene('one.glb');
    run();
    final untouched = writtenAt('assets/one');
    addScene('two.glb');
    run();
    expect(writtenAt('assets/one'), untouched);
    expect(File.fromUri(outputOf('assets/two')).existsSync(), isTrue);
  });

  test('deleting a source prunes its entry and its output', () {
    addScene('one.glb');
    addScene('two.glb');
    run();
    final removed = outputOf('assets/two');
    expect(File.fromUri(removed).existsSync(), isTrue);

    source('two.glb').deleteSync();
    run();

    expect(File.fromUri(removed).existsSync(), isFalse);
    expect(manifest().find(GeneratedAssetFamily.scene, 'assets/two'), isNull);
    expect(
      manifest().find(GeneratedAssetFamily.scene, 'assets/one'),
      isNotNull,
    );
  });

  test('moving a source renames its output and sweeps the old one', () {
    addScene('one.glb');
    run();
    final before = outputOf('assets/one');
    source(
      'one.glb',
    ).renameSync(temp.uri.resolve('assets/moved.glb').toFilePath());
    run();
    expect(File.fromUri(before).existsSync(), isFalse);
    expect(File.fromUri(outputOf('assets/moved')).existsSync(), isTrue);
  });

  test('declares each source plus the discovery root as dependencies', () {
    addScene('one.glb');
    final dependencies = run().dependencies;
    expect(dependencies, contains(temp.uri.resolve('assets/')));
    expect(dependencies, contains(temp.uri.resolve('assets/one.glb')));
  });

  group('sourceFingerprint', () {
    test('content-hashes a small file, so a bare touch changes nothing', () {
      final file = File.fromUri(temp.uri.resolve('small.bin'))
        ..writeAsBytesSync(List<int>.filled(16, 7));
      final first = sourceFingerprint(file);
      file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
      expect(sourceFingerprint(file), first);
    });

    test('takes size and modification time for a large file', () {
      final file = File.fromUri(temp.uri.resolve('large.bin'))
        ..writeAsBytesSync(List<int>.filled(kSmallSourceBytes + 1, 7));
      final first = sourceFingerprint(file);
      expect(first, matches(RegExp(r'^\d+@\d+$')));
      // A touch is the one case the stat form reconverts for nothing, which is
      // the trade for never reading the file.
      file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
      expect(sourceFingerprint(file), isNot(first));
    });

    test('a rewrite of the same length is still caught by the timestamp', () {
      final file = File.fromUri(temp.uri.resolve('large.bin'))
        ..writeAsBytesSync(List<int>.filled(kSmallSourceBytes + 1, 7));
      final first = sourceFingerprint(file);
      file.writeAsBytesSync(List<int>.filled(kSmallSourceBytes + 1, 9));
      expect(sourceFingerprint(file), isNot(first));
    });
  });
}
