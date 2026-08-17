/// The engine's two shader bundles can arrive three ways, and the app's own
/// copy must always win over the one in flutter_scene's package directory.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_gpu_shaders/build.dart' as gpu_shaders;
// ignore: implementation_imports
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/generated_assets/generated_file_names.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/physical_material_variant.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_test/flutter_test.dart';

const String _baseDataAssetKey =
    'packages/flutter_scene/flutter_gpu_shaders/shaderbundles/base.shaderbundle';
const String _physicalDataAssetKey =
    'packages/flutter_scene/flutter_scene/fmat/physical/physical.shaderbundle';

/// The app's own tree, and flutter_scene's inside the package.
const String _appTree = generatedAssetsDirectory;
const String _packageTree = 'packages/flutter_scene/$generatedAssetsDirectory';

final String _baseFile = generatedFileName(
  GeneratedAssetFamily.shaderBundle,
  'base',
  '.shaderbundle',
);
final String _physicalBundleFile = generatedFileName(
  GeneratedAssetFamily.material,
  'physical',
  '.shaderbundle',
);
final String _physicalSidecarFile = generatedFileName(
  GeneratedAssetFamily.material,
  'physical',
  '.fmat.json',
);

/// Serves a synthesized `AssetManifest.bin` listing [assetKeys], plus any
/// string assets in [strings].
class _ManifestAssetBundle extends CachingAssetBundle {
  _ManifestAssetBundle(this.assetKeys, {this.strings = const {}});

  final List<String> assetKeys;
  final Map<String, String> strings;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = <String, Object>{
        for (final asset in assetKeys) asset: <Object>[],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    if (strings[key] case final contents?) {
      return ByteData.sublistView(utf8.encode(contents));
    }
    throw StateError('Unknown asset: $key');
  }
}

/// Fails every load, mimicking an environment with no asset manifest.
class _EmptyAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw StateError('No assets available');
  }
}

String _manifestJson(String package) => GeneratedAssetManifest(
  package: package,
  entries: [
    GeneratedAssetEntry(
      family: GeneratedAssetFamily.shaderBundle,
      id: 'base',
      owner: 'flutter_scene',
      file: _baseFile,
      stamp: 'stamp',
    ),
    GeneratedAssetEntry(
      family: GeneratedAssetFamily.material,
      id: 'physical#shaderbundle',
      owner: 'flutter_scene',
      file: _physicalBundleFile,
      stamp: 'stamp',
    ),
    GeneratedAssetEntry(
      family: GeneratedAssetFamily.material,
      id: 'physical#sidecar',
      owner: 'flutter_scene',
      file: _physicalSidecarFile,
      stamp: 'stamp',
    ),
  ],
).encode();

/// A bundle carrying the named generated trees, and optionally the data assets.
_ManifestAssetBundle _bundleWith({
  bool appTree = false,
  bool packageTree = false,
  bool dataAssets = false,
}) {
  final keys = <String>[];
  final strings = <String, String>{};
  if (dataAssets) keys.addAll([_baseDataAssetKey, _physicalDataAssetKey]);
  for (final (prefix, package) in [
    if (appTree) (_appTree, 'example_app'),
    if (packageTree) (_packageTree, 'flutter_scene'),
  ]) {
    final manifestKey = '$prefix/$generatedManifestFileName';
    strings[manifestKey] = _manifestJson(package);
    keys.addAll([
      manifestKey,
      '$prefix/$_baseFile',
      '$prefix/$_physicalBundleFile',
      '$prefix/$_physicalSidecarFile',
    ]);
  }
  return _ManifestAssetBundle(keys, strings: strings);
}

void main() {
  tearDown(clearGeneratedAssetIndexCache);

  group('the base shader bundle', () {
    test('prefers the data asset', () async {
      final bundle = _bundleWith(
        dataAssets: true,
        appTree: true,
        packageTree: true,
      );
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(
        await resolveBaseShaderBundleKey(bundle: bundle),
        _baseDataAssetKey,
      );
    });

    test("prefers the app tree over flutter_scene's own", () async {
      final bundle = _bundleWith(appTree: true, packageTree: true);
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(
        await resolveBaseShaderBundleKey(bundle: bundle),
        '$_appTree/$_baseFile',
      );
    });

    test("falls back to flutter_scene's own tree", () async {
      final bundle = _bundleWith(packageTree: true);
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(
        await resolveBaseShaderBundleKey(bundle: bundle),
        '$_packageTree/$_baseFile',
      );
    });

    test('resolves nothing when no hook ran', () async {
      final bundle = _bundleWith();
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(await resolveBaseShaderBundleKey(bundle: bundle), isNull);
    });

    test('resolves nothing without a manifest', () async {
      final bundle = _EmptyAssetBundle();
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(await resolveBaseShaderBundleKey(bundle: bundle), isNull);
    });
  });

  group('the physical material bundle', () {
    test('prefers the data asset', () async {
      final bundle = _bundleWith(
        dataAssets: true,
        appTree: true,
        packageTree: true,
      );
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(
        (await resolvePhysicalBundleKeys(bundle: bundle))?.bundle,
        _physicalDataAssetKey,
      );
    });

    test("prefers the app tree over flutter_scene's own", () async {
      final bundle = _bundleWith(appTree: true, packageTree: true);
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      final keys = await resolvePhysicalBundleKeys(bundle: bundle);
      expect(keys?.bundle, '$_appTree/$_physicalBundleFile');
      expect(keys?.sidecar, '$_appTree/$_physicalSidecarFile');
    });

    test("falls back to flutter_scene's own tree", () async {
      final bundle = _bundleWith(packageTree: true);
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      final keys = await resolvePhysicalBundleKeys(bundle: bundle);
      expect(keys?.bundle, '$_packageTree/$_physicalBundleFile');
      expect(keys?.sidecar, '$_packageTree/$_physicalSidecarFile');
    });

    test('resolves nothing when no hook ran', () async {
      final bundle = _bundleWith();
      addTearDown(() => clearGeneratedAssetIndexCache(bundle));
      expect(await resolvePhysicalBundleKeys(bundle: bundle), isNull);
    });
  });

  test('the data-asset key matches what the shader hook registers', () {
    expect(
      gpu_shaders.flutterDataAssetKey(
        package: 'flutter_scene',
        name: gpu_shaders.shaderBundleDataAssetName('base.shaderbundle'),
      ),
      _baseDataAssetKey,
    );
  });

  test('the load errors name what to do', () {
    expect(
      baseShaderBundleMissingMessage,
      allOf(contains('build hook'), contains('Rebuild')),
    );
    expect(
      baseShaderBundleLoadFailureMessage('some.shaderbundle'),
      contains('engine that built the app'),
    );
  });
}
