import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/importer/build_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

void main() {
  group('model DataAsset helpers', () {
    test('compute stable DataAsset names and Flutter asset keys', () {
      expect(
        modelDataAssetName('assets/vehicles/car.model'),
        'flutter_scene/model/assets/vehicles/car.model',
      );
      expect(
        modelFlutterAssetKeyFor(
          package: 'example_app',
          relativeModelPath: 'assets/vehicles/car.model',
        ),
        'packages/example_app/flutter_scene/model/assets/vehicles/car.model',
      );
    });
  });

  group('discoverGlbModels', () {
    test('discovers .glb files below assets directory in stable order', () {
      final temp = Directory.systemTemp.createTempSync('glb_discovery');
      try {
        File.fromUri(temp.uri.resolve('assets/z.glb'))
          ..createSync(recursive: true)
          ..writeAsStringSync('z');
        File.fromUri(temp.uri.resolve('assets/nested/a.glb'))
          ..createSync(recursive: true)
          ..writeAsStringSync('a');
        File.fromUri(temp.uri.resolve('assets/ignore.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync('ignore');

        expect(discoverGlbModels(temp.uri), [
          'assets/nested/a.glb',
          'assets/z.glb',
        ]);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('returns empty when no assets directory exists', () {
      final temp = Directory.systemTemp.createTempSync('glb_discovery_empty');
      try {
        expect(discoverGlbModels(temp.uri), isEmpty);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });

  test('required DataAssets mode fails before doing build work', () {
    final temp = Directory.systemTemp.createTempSync('model_required');
    try {
      final input = _buildInput(packageRoot: temp.uri, buildDataAssets: false);
      final output = BuildOutputBuilder();

      expect(
        () => buildModels(
          buildInput: input,
          buildOutput: output,
          inputFilePaths: const ['assets/missing.glb'],
          assetMode: ModelAssetMode.dataAssetsRequired,
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('flutter config --enable-dart-data-assets'),
          ),
        ),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test(
    'discovers, imports, emits a DataAsset, and declares the source dependency',
    () {
      final glbSource = _resolve('examples/assets_src/two_triangles.glb');
      if (!File(glbSource).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($glbSource) - skipping.');
        return;
      }

      final temp = Directory.systemTemp.createTempSync('model_build');
      try {
        final glbUri = temp.uri.resolve('assets/two_triangles.glb');
        File.fromUri(glbUri)
          ..createSync(recursive: true)
          ..writeAsBytesSync(File(glbSource).readAsBytesSync());

        final input = _buildInput(packageRoot: temp.uri, buildDataAssets: true);
        final outputBuilder = BuildOutputBuilder();

        // No inputFilePaths: exercises auto-discovery of assets/**/*.glb.
        buildModels(
          buildInput: input,
          buildOutput: outputBuilder,
          assetMode: ModelAssetMode.dataAssetsIfAvailable,
        );

        // The .model was written under a path mirroring the source.
        expect(
          File.fromUri(
            temp.uri.resolve('build/models/assets/two_triangles.model'),
          ).existsSync(),
          isTrue,
        );

        final output = outputBuilder.build();

        // A DataAsset was emitted, keyed by the full source-relative path.
        final data = output.assets.data;
        expect(data, hasLength(1));
        expect(data.single.package, 'example_app');
        expect(
          data.single.name,
          'flutter_scene/model/assets/two_triangles.model',
        );

        // The source GLB was declared as a dependency (so hot reload retriggers).
        expect(output.dependencies, contains(glbUri));
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );
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
