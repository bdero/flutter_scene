// The runtime side of the generated tree: the scene, texture, and material
// registries resolve a source path to a tree asset key, and a data asset for the
// same source still wins.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/importer/scene_registry.dart';
import 'package:flutter_scene/src/texture/texture_registry.dart';
import 'package:flutter_test/flutter_test.dart';

const String _manifestKey =
    '$generatedAssetsDirectory/$generatedManifestFileName';

String _treeKey(GeneratedAssetFamily family, String id, String extension) =>
    '$generatedAssetsDirectory/${generatedFileName(family, id, extension)}';

/// Serves an `AssetManifest.bin` over [strings]' keys, plus their contents.
final class _TreeBundle extends CachingAssetBundle {
  _TreeBundle(this.strings, {this.extraKeys = const []});

  final Map<String, String> strings;
  final List<String> extraKeys;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = <String, Object>{
        for (final asset in [...strings.keys, ...extraKeys]) asset: <Object>[],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    if (strings[key] case final contents?) {
      return ByteData.sublistView(utf8.encode(contents));
    }
    throw StateError('Unknown asset: $key');
  }
}

String _manifest(List<GeneratedAssetEntry> entries) =>
    GeneratedAssetManifest(package: 'example_app', entries: entries).encode();

GeneratedAssetEntry _entry(
  GeneratedAssetFamily family,
  String id,
  String extension, {
  String owner = 'example_app',
}) => GeneratedAssetEntry(
  family: family,
  id: id,
  owner: owner,
  file: generatedFileName(family, id, extension),
  stamp: 'stamp',
);

void main() {
  test('SceneRegistry resolves a source path through the tree', () async {
    final bundle = _TreeBundle({
      _manifestKey: _manifest([
        _entry(GeneratedAssetFamily.scene, 'assets/level', '.fsceneb'),
      ]),
    });
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    final registry = await SceneRegistry.load(bundle: bundle);
    expect(
      registry.resolveKey('assets/level.glb'),
      _treeKey(GeneratedAssetFamily.scene, 'assets/level', '.fsceneb'),
    );
    expect(
      registry.resolveKey('assets/level', package: 'example_app'),
      _treeKey(GeneratedAssetFamily.scene, 'assets/level', '.fsceneb'),
    );
  });

  test('a data asset wins over a tree entry for the same scene', () async {
    const dataAssetKey =
        'packages/example_app/flutter_scene/scene/assets/level.fsceneb';
    final bundle = _TreeBundle(
      {
        _manifestKey: _manifest([
          _entry(GeneratedAssetFamily.scene, 'assets/level', '.fsceneb'),
        ]),
      },
      extraKeys: const [dataAssetKey],
    );
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    final registry = await SceneRegistry.load(bundle: bundle);
    expect(registry.resolveKey('assets/level.glb'), dataAssetKey);
  });

  test('a missing scene names the setup step', () async {
    final bundle = _TreeBundle({_manifestKey: _manifest([])});
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    final registry = await SceneRegistry.load(bundle: bundle);
    expect(
      () => registry.resolveKey('assets/level.glb'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('flutter_scene:init'),
            contains(generatedAssetsDirectory),
          ),
        ),
      ),
    );
  });

  test('TextureRegistry resolves a source path through the tree', () async {
    final bundle = _TreeBundle({
      _manifestKey: _manifest([
        _entry(GeneratedAssetFamily.texture, 'assets/grid', '.fstex'),
      ]),
    });
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    final registry = await TextureRegistry.load(bundle: bundle);
    expect(
      registry.resolveKey('assets/grid.png'),
      _treeKey(GeneratedAssetFamily.texture, 'assets/grid', '.fstex'),
    );
  });

  test('FmatMaterialRegistry reads a bundle index from the tree', () async {
    final indexFile = generatedFileName(
      GeneratedAssetFamily.material,
      'materials',
      '.index.json',
    );
    final bundleFile = generatedFileName(
      GeneratedAssetFamily.material,
      'materials',
      '.shaderbundle',
    );
    final sidecarFile = generatedFileName(
      GeneratedAssetFamily.material,
      'materials',
      '.fmat.json',
    );
    final bundle = _TreeBundle({
      _manifestKey: _manifest([
        _entry(GeneratedAssetFamily.material, 'materials', '.index.json'),
        _entry(
          GeneratedAssetFamily.material,
          'materials#shaderbundle',
          '.shaderbundle',
        ),
        _entry(
          GeneratedAssetFamily.material,
          'materials#sidecar',
          '.fmat.json',
        ),
      ]),
      '$generatedAssetsDirectory/$indexFile': jsonEncode({
        'schema': 2,
        'package': 'example_app',
        'bundleName': 'materials',
        'shaderBundleFileName': bundleFile,
        'sidecarFileName': sidecarFile,
        'materials': {
          'Toon': {'entryName': 'Toon', 'source': 'assets/toon.fmat'},
        },
      }),
    });
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    final registry = await FmatMaterialRegistry.load(bundle: bundle);
    final resolution = registry.resolve('assets/toon.fmat');
    expect(resolution.entry.entryName, 'Toon');
    expect(
      resolution.index.shaderBundleAssetKey,
      '$generatedAssetsDirectory/$bundleFile',
    );
    expect(
      resolution.index.sidecarAssetKey,
      '$generatedAssetsDirectory/$sidecarFile',
    );
  });

  test('an empty index resolves nothing and reads no manifest', () async {
    final bundle = _TreeBundle(const {});
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    final index = await loadGeneratedAssetIndex(bundle);
    expect(index.isEmpty, isTrue);
    expect(index.resolveKey(GeneratedAssetFamily.scene, 'anything'), isNull);
  });
}
