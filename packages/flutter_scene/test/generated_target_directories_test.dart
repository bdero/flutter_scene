/// A generated tree is one listed asset directory, and every build sharing it
/// (every project on the machine, for flutter_scene's own tree in the pub cache)
/// adds outputs for its own target. Target outputs therefore live in a directory
/// per target, listed with a platform filter, so an app ships only its own.
library;

import 'dart:io';

import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const List<String> _filterableOSes = [
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
];

String _pubspecListing(Iterable<GeneratedTargetDirectory> directories) {
  final buffer = StringBuffer(
    'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
  );
  for (final directory in directories) {
    buffer.write(
      '    - path: ${directory.assetEntry}\n'
      '      platforms: [${directory.platforms.join(', ')}]\n',
    );
  }
  return buffer.toString();
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('fs_target_dirs'));
  tearDown(() => temp.deleteSync(recursive: true));

  void writePubspec(String contents) => File.fromUri(
    temp.uri.resolve('pubspec.yaml'),
  ).writeAsStringSync(contents);

  Uri bundleUri(GeneratedAssetTree tree, String target) => tree.fileUri(
    GeneratedAssetFamily.shaderBundle,
    nameId: 'base',
    extension: '.shaderbundle',
    variant: 'engine=one',
    target: target,
  );

  String relative(Uri uri) =>
      uri.path.substring(temp.uri.resolve(generatedAssetsEntry).path.length);

  test(
    'each target an app can run on has a directory filtered to that app',
    () {
      for (final os in [..._filterableOSes, null]) {
        final target = shaderTargetKey(shaderBundleBackendsForOS(os));
        final directory = generatedTargetDirectory(target);
        expect(directory, isNotNull, reason: '$os ($target) needs a directory');
        expect(directory!.platforms, contains(os ?? 'web'));
      }
      // No two directories claim a platform, so a platform ships one set.
      final claimed = [
        for (final directory in generatedTargetDirectories)
          ...directory.platforms,
      ];
      expect(claimed.toSet().length, claimed.length);
      // Fuchsia takes Vulkan alone, which no platform filter can name.
      expect(
        generatedTargetDirectory(
          shaderTargetKey(shaderBundleBackendsForOS('fuchsia')),
        ),
        isNull,
      );
    },
  );

  test('flutter_scene lists every target directory and ships it empty', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final assets = (pubspec['flutter'] as YamlMap)['assets'] as YamlList;
    final listed = {
      for (final entry in assets)
        if (entry is YamlMap)
          entry['path'] as String: [
            for (final platform in entry['platforms'] as YamlList)
              platform as String,
          ],
    };
    for (final directory in generatedTargetDirectories) {
      expect(listed[directory.assetEntry], directory.platforms);
      // Flutter fails the build on a listed directory that does not exist, and
      // an empty directory is not published, so each carries its .gitignore.
      expect(
        File(
          '${directory.assetEntry}$generatedAssetsGitignoreFileName',
        ).existsSync(),
        isTrue,
      );
    }
  });

  test('a tree listing its target directories writes into them', () {
    writePubspec(_pubspecListing(generatedTargetDirectories));
    final tree = GeneratedAssetTree.open(temp.uri, 'app');
    final metal = bundleUri(tree, 'metalDesktop');
    final gles = bundleUri(tree, 'openglEs,vulkan');
    expect(relative(metal), startsWith('metal_desktop/'));
    expect(relative(gles), startsWith('opengl_es_vulkan/'));
    // Target-agnostic outputs and unfilterable targets stay at the top.
    expect(relative(bundleUri(tree, 'vulkan')), isNot(contains('/')));
    expect(
      relative(
        tree.fileUri(
          GeneratedAssetFamily.scene,
          nameId: 'level',
          extension: '.fsceneb',
        ),
      ),
      isNot(contains('/')),
    );

    for (final (uri, target) in [
      (metal, 'metalDesktop'),
      (gles, 'openglEs,vulkan'),
    ]) {
      writeGeneratedBytes(uri, [1]);
      tree.recordFile(
        family: GeneratedAssetFamily.shaderBundle,
        id: 'base',
        uri: uri,
        stamp: target,
        owner: 'flutter_scene',
        target: target,
      );
    }
    // An output no entry names, left in a target directory by an older build.
    final stale = temp.uri.resolve(
      '${generatedAssetsEntry}metal_desktop/'
      'shaderbundle.base.0123abcd.shaderbundle',
    );
    writeGeneratedBytes(stale, [1]);
    File.fromUri(stale).setLastModifiedSync(DateTime(2000));
    tree.save();

    final manifest = GeneratedAssetManifest.decode(
      File.fromUri(
        temp.uri.resolve('$generatedAssetsEntry$generatedManifestFileName'),
      ).readAsStringSync(),
    )!;
    // The recorded file carries its directory, so the runtime key does too.
    expect(
      manifest
          .findForTarget(
            GeneratedAssetFamily.shaderBundle,
            'base',
            'metalDesktop',
          )!
          .file,
      relative(metal),
    );
    expect(File.fromUri(metal).existsSync(), isTrue);
    expect(File.fromUri(gles).existsSync(), isTrue);
    expect(File.fromUri(stale).existsSync(), isFalse);
  });

  test('a save keeps a fresh output another target just wrote', () {
    writePubspec(_pubspecListing(generatedTargetDirectories));
    // Both opened before either saves, the way two builds share one tree.
    final metalTree = GeneratedAssetTree.open(temp.uri, 'app');
    final glesTree = GeneratedAssetTree.open(temp.uri, 'app');

    Uri saveBundle(GeneratedAssetTree tree, String target) {
      final uri = bundleUri(tree, target);
      writeGeneratedBytes(uri, [1]);
      tree
        ..recordFile(
          family: GeneratedAssetFamily.shaderBundle,
          id: 'base',
          uri: uri,
          stamp: target,
          owner: 'flutter_scene',
          target: target,
        )
        ..save();
      return uri;
    }

    final metal = saveBundle(metalTree, 'metalDesktop');
    saveBundle(glesTree, 'openglEs,vulkan');
    // The target is part of what names a file, so the gles save must read the
    // metal one as a variant of the same output rather than as an orphan.
    expect(File.fromUri(metal).existsSync(), isTrue);
  });

  test('a tree listing only the top directory keeps outputs flat', () {
    writePubspec(_pubspecListing(const []));
    final tree = GeneratedAssetTree.open(temp.uri, 'app');
    for (final target in ['metalDesktop', 'openglEs', 'metalIos']) {
      expect(relative(bundleUri(tree, target)), isNot(contains('/')));
    }
  });
}
