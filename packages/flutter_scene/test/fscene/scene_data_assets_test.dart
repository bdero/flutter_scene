// Covers the buildScenes build hook: discovering .glb sources, importing them
// to .fsceneb packages, and registering them as DataAssets. Mirrors the
// buildModels coverage. Runs only when the source GLB corpus is present.

import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/importer/build_hooks.dart';
import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

void main() {
  test('sceneDataAssetName computes a stable DataAsset name', () {
    expect(
      sceneDataAssetName('assets/levels/forest.fsceneb'),
      'flutter_scene/scene/assets/levels/forest.fsceneb',
    );
  });

  test('imports a .glb, writes a .fsceneb, and emits a DataAsset', () {
    final glbSource = _resolve('examples/assets_src/two_triangles.glb');
    if (!File(glbSource).existsSync()) {
      // ignore: avoid_print
      print('Test data missing ($glbSource) - skipping.');
      return;
    }

    final temp = Directory.systemTemp.createTempSync('scene_build');
    try {
      final glbUri = temp.uri.resolve('assets/two_triangles.glb');
      File.fromUri(glbUri)
        ..createSync(recursive: true)
        ..writeAsBytesSync(File(glbSource).readAsBytesSync());

      final input = _buildInput(packageRoot: temp.uri, buildDataAssets: true);
      final outputBuilder = BuildOutputBuilder();

      // No inputFilePaths: exercises auto-discovery of assets/**/*.glb.
      buildScenes(
        buildInput: input,
        buildOutput: outputBuilder,
        assetMode: SceneAssetMode.dataAssetsIfAvailable,
      );

      final scenePath = temp.uri.resolve(
        'build/scenes/assets/two_triangles.fsceneb',
      );
      expect(File.fromUri(scenePath).existsSync(), isTrue);

      // The written package is a valid container that round-trips.
      final document = readFsceneb(File.fromUri(scenePath).readAsBytesSync());
      expect(document.nodes, isNotEmpty);
      expect(document.payloads, isNotEmpty);

      final output = outputBuilder.build();
      final data = output.assets.data;
      expect(data, hasLength(1));
      expect(data.single.package, 'example_app');
      expect(
        data.single.name,
        'flutter_scene/scene/assets/two_triangles.fsceneb',
      );
      expect(output.dependencies, contains(glbUri));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}

BuildInput _buildInput({
  required Uri packageRoot,
  required bool buildDataAssets,
}) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'example_app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  if (buildDataAssets) {
    DataAssetsExtension().setupBuildInput(builder);
  }
  return builder.build();
}

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return relative;
}
