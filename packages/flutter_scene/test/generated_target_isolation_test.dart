/// One `flutter run` invokes the hook twice, once with the target's code-asset
/// config and once with only data assets and no target OS, and a pub-cache tree
/// is shared by every project on the machine. So several builds write one
/// generated tree with different graphics backends in mind, and an output
/// compiled for one backend is unreadable on another. Every such output is
/// separated by target, in its file name and in the manifest, and the runtime
/// reads back only the target it runs on.
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/fmat/target_shader_bundle.dart';
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_scene/src/generated_assets/runtime_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

/// A hook input like the one `flutter run` makes for [targetOS], or like the
/// one it also makes with no asset types at all when [targetOS] is null.
BuildInput _input(Uri packageRoot, {OS? targetOS}) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  if (targetOS != null) {
    CodeAssetExtension(
      targetArchitecture: Architecture.arm64,
      targetOS: targetOS,
      linkModePreference: LinkModePreference.dynamic,
      macOS: targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
      iOS: targetOS == OS.iOS
          ? IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 13)
          : null,
      android: targetOS == OS.android
          ? AndroidCodeConfig(targetNdkApi: 21)
          : null,
    ).setupBuildInput(builder);
  }
  return builder.build();
}

/// The data-asset-only hook input `flutter run` makes for both a native
/// build's second pass (code assets off) and a web build. flutter_tools reduces
/// `MacOSAssetTarget` (with no code assets) and `WebAssetTarget` to this same
/// single data-asset extension, so the two inputs are constructed identically.
BuildInput _dataOnlyInput(Uri packageRoot) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    );
  DataAssetsExtension().setupBuildInput(builder);
  builder.config.setupBuild(linkingEnabled: false);
  builder.setupBuildInput();
  return builder.build();
}

GeneratedAssetTree _tree(Directory temp) =>
    GeneratedAssetTree.open(temp.uri, 'app');

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fs_target_isolation');
    File.fromUri(temp.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('a config with no asset types picks GLES, a macOS one picks Metal', () {
    expect(shaderBundleBackendsForBuild(_input(temp.uri)), {
      ShaderBundleBackend.openglEs,
    });
    expect(shaderBundleBackendsForBuild(_input(temp.uri, targetOS: OS.macOS)), {
      ShaderBundleBackend.metalDesktop,
    });
    expect(
      shaderBundleTargetKey(_input(temp.uri, targetOS: OS.macOS)),
      isNot(shaderBundleTargetKey(_input(temp.uri))),
    );
  });

  test(
    'a native build\'s data-only pass is indistinguishable from a web build',
    () {
      // The wasteful native GLES compile cannot be skipped at this layer. The
      // data-asset-only input carries no target OS, so it resolves to GLES
      // exactly like a web build, which genuinely needs that set. Nothing the
      // hook can read separates the two. If a Flutter release starts naming the
      // platform on a data-only input, this flips and the skip becomes possible.
      final dataOnly = _dataOnlyInput(temp.uri);
      expect(dataOnly.config.buildCodeAssets, isFalse);
      expect(shaderBundleBackendsForBuild(dataOnly), {
        ShaderBundleBackend.openglEs,
      });
      final config = jsonEncode(dataOnly.config.json).toLowerCase();
      for (final os in const [
        'macos',
        'ios',
        'android',
        'linux',
        'windows',
        'web',
        'fuchsia',
      ]) {
        expect(
          config,
          isNot(contains(os)),
          reason: 'a data-only input naming $os would let the native pass skip',
        );
      }
    },
  );

  test('two targets write different files in one tree', () {
    final tree = _tree(temp);
    Uri output(String target) => tree.fileUri(
      GeneratedAssetFamily.shaderBundle,
      nameId: 'base',
      extension: '.shaderbundle',
      variant: 'engine=one',
      target: target,
    );
    expect(output('metalDesktop'), isNot(output('openglEs')));
  });

  test(
    'the GLES rebuild cannot clobber the Metal build it shares a tree with',
    () {
      final tree = _tree(temp);
      final metal = shaderBundleTargetKey(_input(temp.uri, targetOS: OS.macOS));
      final gles = shaderBundleTargetKey(_input(temp.uri));

      for (final target in [metal, gles]) {
        final uri = tree.fileUri(
          GeneratedAssetFamily.shaderBundle,
          nameId: 'base',
          extension: '.shaderbundle',
          target: target,
        );
        writeGeneratedBytes(uri, [target.length]);
        tree.recordFile(
          family: GeneratedAssetFamily.shaderBundle,
          id: 'base',
          uri: uri,
          stamp: 'stamp $target',
          owner: 'flutter_scene',
          target: target,
        );
      }
      tree.save();

      final manifest = GeneratedAssetManifest.decode(
        File.fromUri(
          temp.uri.resolve(
            '$generatedAssetsDirectory/$generatedManifestFileName',
          ),
        ).readAsStringSync(),
      )!;
      final entries = manifest.ofFamily(GeneratedAssetFamily.shaderBundle);
      expect(
        entries.length,
        2,
        reason: 'one entry per target, not last writer',
      );
      expect(
        entries.map((e) => e.file).toSet().length,
        2,
        reason: 'the two targets must not name the same file',
      );
      expect(
        manifest
            .findForTarget(GeneratedAssetFamily.shaderBundle, 'base', metal)!
            .target,
        metal,
      );
      // The sweep in save() keeps both, since both are still referenced.
      for (final entry in entries) {
        expect(
          File.fromUri(
            temp.uri.resolve('$generatedAssetsDirectory/${entry.file}'),
          ),
          predicate<File>((f) => f.existsSync()),
        );
      }
    },
  );

  test(
    'freshness is tracked per target, so neither build invalidates the other',
    () {
      final tree = _tree(temp);
      final metal = shaderBundleTargetKey(_input(temp.uri, targetOS: OS.macOS));
      final gles = shaderBundleTargetKey(_input(temp.uri));
      final uri = tree.fileUri(
        GeneratedAssetFamily.shaderBundle,
        nameId: 'base',
        extension: '.shaderbundle',
        target: metal,
      );
      writeGeneratedBytes(uri, [1]);
      tree.recordFile(
        family: GeneratedAssetFamily.shaderBundle,
        id: 'base',
        uri: uri,
        stamp: 'metal',
        owner: 'flutter_scene',
        target: metal,
      );

      expect(
        tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', 'metal', [
          uri,
        ], target: metal),
        isTrue,
      );
      expect(
        tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', 'gles', [
          uri,
        ], target: gles),
        isFalse,
        reason:
            'the GLES build must compile its own bundle, not adopt this one',
      );
    },
  );

  test('the runtime reads back only the target it runs on', () {
    final index = GeneratedAssetIndex([
      GeneratedAssetSource(
        keyPrefix: 'packages/flutter_scene/$generatedAssetsEntry',
        manifest: GeneratedAssetManifest(
          package: 'flutter_scene',
          entries: [
            for (final target in ['metalDesktop', 'openglEs', 'metalIos'])
              GeneratedAssetEntry(
                family: GeneratedAssetFamily.shaderBundle,
                id: 'base',
                owner: 'flutter_scene',
                file: 'shaderbundle.base.$target.shaderbundle',
                stamp: 'x',
                target: target,
              ),
          ],
        ),
      ),
    ]);

    final key = index.resolveFirstKey(
      GeneratedAssetFamily.shaderBundle,
      'base',
      package: 'flutter_scene',
    );
    expect(
      key,
      endsWith('shaderbundle.base.$currentShaderTarget.shaderbundle'),
    );
    expect(
      index.entriesOf(GeneratedAssetFamily.shaderBundle).length,
      1,
      reason: 'the other platforms\' bundles are not this build\'s to load',
    );
    expect(
      index.targetsOf(GeneratedAssetFamily.shaderBundle, 'base'),
      containsAll(['metalDesktop', 'openglEs', 'metalIos']),
      reason: 'a diagnostic still needs to name what was built',
    );
  });

  test('a target-agnostic entry is readable on every target', () {
    final index = GeneratedAssetIndex([
      GeneratedAssetSource(
        keyPrefix: generatedAssetsEntry,
        manifest: GeneratedAssetManifest(
          package: 'app',
          entries: [
            GeneratedAssetEntry(
              family: GeneratedAssetFamily.scene,
              id: 'assets/one',
              owner: 'app',
              file: 'scene.one.abcdef12.fsceneb',
              stamp: 'x',
            ),
          ],
        ),
      ),
    ]);
    expect(
      index.resolveFirstKey(GeneratedAssetFamily.scene, 'assets/one'),
      '${generatedAssetsEntry}scene.one.abcdef12.fsceneb',
    );
  });

  test('the build and the runtime agree on what each OS needs', () {
    // Fuchsia is skipped because code_assets cannot parse it back out of a
    // config, so no hook ever sees it.
    for (final os in OS.values.where((os) => os != OS.fuchsia)) {
      expect(
        shaderBundleTargetKey(_input(temp.uri, targetOS: os)),
        shaderTargetKey(shaderBundleBackendsForOS(os.name)),
        reason: 'a mismatch here is a black frame on ${os.name}',
      );
    }
    // What this host would build for itself is what it looks for at runtime.
    expect(
      currentShaderTarget,
      shaderTargetKey(shaderBundleBackendsForOS(runtimeOperatingSystem)),
    );
    expect(
      shaderBundleTargetKey(
        _input(
          temp.uri,
          targetOS: OS.values.firstWhere(
            (os) => os.name == runtimeOperatingSystem,
          ),
        ),
      ),
      currentShaderTarget,
    );
  });

  test('a manifest from an older schema is discarded rather than misread', () {
    expect(
      GeneratedAssetManifest.decode(
        '{"schema": 2, "package": "app", "entries": []}',
      ),
      isNull,
    );
  });
}
