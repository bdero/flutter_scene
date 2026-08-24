/// A shader bundle is only valid for the engine that consumes it, so every
/// compiled output records which engine compiled it and is rebuilt when that
/// changes. One shared pub cache across two Flutter versions depends on this.
library;

import 'dart:io';

import 'package:flutter_scene/src/fmat/target_shader_bundle.dart';
import 'package:flutter_scene/src/generated_assets/engine_identity.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

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
    temp = Directory.systemTemp.createTempSync('fs_engine_stamp');
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
    );
  });
  tearDown(() {
    debugSetEngineIdentity(null);
    temp.deleteSync(recursive: true);
  });

  test('the identity names the engine, and is stable within a run', () async {
    debugSetEngineIdentity(null);
    final identity = await engineIdentity();
    expect(identity, isNotEmpty);
    expect(await engineIdentity(), identity);
    // The SDK running the tests has an engine cache, so both signals resolve.
    expect(identity, contains('impellerc='));
    expect(identity, contains('engine='));
  });

  test('a compiled bundle stamps the engine it was built for', () async {
    debugSetEngineIdentity('engine=first');
    final first = await shaderBundleStamp(_input(temp.uri), 'bundle=base');
    expect(first, contains('engine=first'));
    debugSetEngineIdentity('engine=second');
    expect(
      await shaderBundleStamp(_input(temp.uri), 'bundle=base'),
      isNot(first),
    );
  });

  test('a new engine makes the recorded output stale', () async {
    final tree = GeneratedAssetTree.open(temp.uri, 'app');
    final output = tree.fileUri(
      GeneratedAssetFamily.shaderBundle,
      nameId: 'base',
      extension: '.shaderbundle',
    );
    File.fromUri(output).writeAsBytesSync([0]);

    debugSetEngineIdentity('engine=first');
    final built = await shaderBundleStamp(_input(temp.uri), 'bundle=base');
    tree
      ..recordFile(
        family: GeneratedAssetFamily.shaderBundle,
        id: 'base',
        uri: output,
        stamp: built,
        owner: 'flutter_scene',
      )
      ..save();

    expect(
      tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', built, [output]),
      isTrue,
      reason: 'the same engine and sources must skip the compile',
    );

    debugSetEngineIdentity('engine=second');
    final afterUpgrade = await shaderBundleStamp(
      _input(temp.uri),
      'bundle=base',
    );
    expect(
      tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', afterUpgrade, [
        output,
      ]),
      isFalse,
      reason: 'a bundle built by another engine must be recompiled',
    );
  });

  test('material bundles isolate file paths by engine identity', () async {
    final tree = GeneratedAssetTree.open(temp.uri, 'app');
    debugSetEngineIdentity('engine=first');
    final first = tree.fileUri(
      GeneratedAssetFamily.material,
      nameId: 'materials',
      extension: '.shaderbundle',
      variant: await engineIdentity(),
    );

    debugSetEngineIdentity('engine=second');
    final second = tree.fileUri(
      GeneratedAssetFamily.material,
      nameId: 'materials',
      extension: '.shaderbundle',
      variant: await engineIdentity(),
    );

    expect(first, isNot(second));
  });

  test('a generated file is published by rename, never half-written', () {
    final target = temp.uri.resolve('out.bin');
    writeGeneratedBytes(target, List<int>.filled(64, 3));
    expect(File.fromUri(target).readAsBytesSync().length, 64);
    expect(
      Directory.fromUri(
        temp.uri,
      ).listSync().where((e) => e.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('a read-only destination fails with the way out', () {
    final locked = Directory.fromUri(temp.uri.resolve('locked/'))..createSync();
    Process.runSync('chmod', ['a-w', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['u+w', locked.path]));
    expect(
      () => writeGeneratedString(locked.uri.resolve('out.txt'), 'x'),
      throwsA(
        isA<GeneratedAssetsNotWritableException>().having(
          (e) => e.toString(),
          'message',
          allOf(
            contains('writable'),
            contains('data assets'),
            contains('buildEngineAssets'),
          ),
        ),
      ),
    );
  });
}
