import 'dart:convert';
import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/src/fmat/build_materials.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

void main() {
  group('fmat DataAsset helpers', () {
    test('compute stable DataAsset names and Flutter asset keys', () {
      expect(
        fmatDataAssetName('materials', 'materials.shaderbundle'),
        'flutter_scene/fmat/materials/materials.shaderbundle',
      );
      expect(
        fmatFlutterAssetKeyFor(
          package: 'example_app',
          bundleName: 'materials',
          fileName: 'materials.index.json',
        ),
        'packages/example_app/flutter_scene/fmat/materials/materials.index.json',
      );
    });

    test('discovers .fmat files below materials directory in stable order', () {
      final temp = Directory.systemTemp.createTempSync('fmat_discovery');
      try {
        File.fromUri(temp.uri.resolve('materials/z.fmat'))
          ..createSync(recursive: true)
          ..writeAsStringSync('z');
        File.fromUri(temp.uri.resolve('materials/nested/a.fmat'))
          ..createSync(recursive: true)
          ..writeAsStringSync('a');
        File.fromUri(temp.uri.resolve('materials/ignore.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync('ignore');

        expect(discoverFmatMaterials(temp.uri), [
          'materials/nested/a.fmat',
          'materials/z.fmat',
        ]);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test(
      'required DataAssets mode fails before legacy fallback work',
      () async {
        final input = _buildInput(buildDataAssets: false);
        final output = BuildOutputBuilder();

        await expectLater(
          buildMaterials(
            buildInput: input,
            buildOutput: output,
            materials: const ['materials/toon.fmat'],
            assetMode: MaterialAssetMode.dataAssetsRequired,
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('flutter config --enable-dart-data-assets'),
            ),
          ),
        );
      },
    );
  });

  group('FmatMaterialRegistry', () {
    test('resolves a material by source path, ignoring extension', () async {
      final registry = await FmatMaterialRegistry.load(
        bundle: _JsonAssetBundle({
          'packages/example_app/flutter_scene/fmat/materials/materials.index.json':
              _indexJson(package: 'example_app', bundleName: 'materials'),
        }),
        assetKeys: const [
          'packages/example_app/flutter_scene/fmat/materials/materials.index.json',
          'assets/other.txt',
        ],
      );

      for (final query in ['materials/toon.fmat', 'materials/toon']) {
        final resolution = registry.resolve(query);
        expect(resolution.index.package, 'example_app');
        expect(resolution.index.bundleName, 'materials');
        expect(resolution.index.shaderBundleAssetKey, 'shader.key');
        expect(resolution.index.sidecarAssetKey, 'sidecar.key');
        expect(resolution.entry.entryName, 'FmatToon');
        expect(resolution.entry.source, 'materials/toon.fmat');
      }
    });

    test('same material name in different directories does not collide', () async {
      final registry = await FmatMaterialRegistry.load(
        bundle: _JsonAssetBundle({
          'packages/example_app/flutter_scene/fmat/materials/materials.index.json':
              _twoMaterialIndexJson(),
        }),
        assetKeys: const [
          'packages/example_app/flutter_scene/fmat/materials/materials.index.json',
        ],
      );

      expect(registry.resolve('a/toon.fmat').entry.entryName, 'Toon');
      expect(registry.resolve('b/toon.fmat').entry.entryName, 'ToonB');
    });

    test(
      'requires package or bundle disambiguation for duplicate source paths',
      () async {
        final registry = await FmatMaterialRegistry.load(
          bundle: _JsonAssetBundle({
            'packages/a/flutter_scene/fmat/materials/materials.index.json':
                _indexJson(package: 'a', bundleName: 'materials'),
            'packages/b/flutter_scene/fmat/materials/materials.index.json':
                _indexJson(package: 'b', bundleName: 'materials'),
          }),
          assetKeys: const [
            'packages/a/flutter_scene/fmat/materials/materials.index.json',
            'packages/b/flutter_scene/fmat/materials/materials.index.json',
          ],
        );

        expect(
          () => registry.resolve('materials/toon.fmat'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Pass package and/or bundleName'),
            ),
          ),
        );
        expect(
          registry.resolve('materials/toon.fmat', package: 'b').index.package,
          'b',
        );
      },
    );
  });
}

// An index whose two materials share the entry-name-keyed map but live at
// different source paths (and have distinct entry names).
String _twoMaterialIndexJson() => jsonEncode({
  'schema': 1,
  'package': 'example_app',
  'bundleName': 'materials',
  'shaderBundleAssetKey': 'shader.key',
  'sidecarAssetKey': 'sidecar.key',
  'materials': {
    'Toon': {'entryName': 'Toon', 'source': 'a/toon.fmat'},
    'ToonB': {'entryName': 'ToonB', 'source': 'b/toon.fmat'},
  },
});

BuildInput _buildInput({required bool buildDataAssets}) {
  final temp = Directory.systemTemp.createTempSync('flutter_scene_build_input');
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: temp.uri,
      packageName: 'example_app',
      outputDirectoryShared: temp.uri.resolve('.dart_tool/hook/'),
      outputFile: temp.uri.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  if (buildDataAssets) {
    DataAssetsExtension().setupBuildInput(builder);
  }
  return builder.build();
}

String _indexJson({required String package, required String bundleName}) =>
    jsonEncode({
      'schema': 1,
      'package': package,
      'bundleName': bundleName,
      'shaderBundleAssetKey': 'shader.key',
      'sidecarAssetKey': 'sidecar.key',
      'materials': {
        'FmatToon': {'entryName': 'FmatToon', 'source': 'materials/toon.fmat'},
      },
    });

final class _JsonAssetBundle extends CachingAssetBundle {
  _JsonAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) {
      throw StateError('Missing test asset: $key');
    }
    final bytes = utf8.encode(value);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
