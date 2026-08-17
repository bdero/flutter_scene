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
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_test/flutter_test.dart';

const String _pubspecAssetKey =
    'packages/flutter_scene/build/shaderbundles/base.shaderbundle';
const String _dataAssetKey =
    'packages/flutter_scene/flutter_gpu_shaders/shaderbundles/base.shaderbundle';
final String _treeFileName = generatedFileName(
  GeneratedAssetFamily.shaderBundle,
  'base',
  '.shaderbundle',
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

String _manifestJson() => GeneratedAssetManifest(
  package: 'example_app',
  entries: [
    GeneratedAssetEntry(
      family: GeneratedAssetFamily.shaderBundle,
      id: 'base',
      owner: 'flutter_scene',
      file: _treeFileName,
      stamp: 'stamp',
    ),
  ],
).encode();

void main() {
  tearDown(clearGeneratedAssetIndexCache);

  test('prefers the data-asset key when the manifest lists it', () async {
    final bundle = _ManifestAssetBundle([_pubspecAssetKey, _dataAssetKey]);
    expect(await resolveBaseShaderBundleKey(bundle: bundle), _dataAssetKey);
  });

  test('resolves the generated tree when there is no data asset', () async {
    final manifestKey = '$generatedAssetsDirectory/$generatedManifestFileName';
    final bundle = _ManifestAssetBundle(
      [manifestKey, '$generatedAssetsDirectory/$_treeFileName'],
      strings: {manifestKey: _manifestJson()},
    );
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    expect(
      await resolveBaseShaderBundleKey(bundle: bundle),
      '$generatedAssetsDirectory/$_treeFileName',
    );
  });

  test('falls back to the pubspec-asset key with nothing else', () async {
    final bundle = _ManifestAssetBundle([_pubspecAssetKey]);
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    expect(await resolveBaseShaderBundleKey(bundle: bundle), _pubspecAssetKey);
  });

  test('falls back to the pubspec-asset key without a manifest', () async {
    final bundle = _EmptyAssetBundle();
    addTearDown(() => clearGeneratedAssetIndexCache(bundle));
    expect(await resolveBaseShaderBundleKey(bundle: bundle), _pubspecAssetKey);
  });

  test('the data-asset key matches what the shader hook registers', () {
    expect(
      gpu_shaders.flutterDataAssetKey(
        package: 'flutter_scene',
        name: gpu_shaders.shaderBundleDataAssetName('base.shaderbundle'),
      ),
      _dataAssetKey,
    );
  });

  test('a missing bundle names the setup step', () {
    expect(
      baseShaderBundleLoadFailureMessage(_pubspecAssetKey),
      allOf(contains('buildEngineAssets'), contains('flutter_scene:init')),
    );
  });
}
