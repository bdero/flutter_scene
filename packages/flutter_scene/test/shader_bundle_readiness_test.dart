/// A shader bundle the engine cannot unpack still loads, and every lookup in
/// it just returns null. That used to leave the scene reporting itself ready
/// and drawing a black frame, with the only clue in the engine's own log. The
/// load now fails, and says which of the two causes it is and how to clear it.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
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

const String _packageTree = 'packages/flutter_scene/$generatedAssetsDirectory';

/// A bundle whose files were built for [target] only, the state a macOS app
/// lands in when a build for another platform wrote the shared tree last.
AssetBundle _bundleBuiltFor(String target) {
  String file(GeneratedAssetFamily family, String id, String extension) =>
      generatedFileName(family, id, extension, variant: 'target=$target');
  final entries = [
    {
      'family': 'shaderBundle',
      'id': 'base',
      'file': file(GeneratedAssetFamily.shaderBundle, 'base', '.shaderbundle'),
      'stamp': 'x',
      'target': target,
    },
    for (final part in ['#shaderbundle', '#sidecar'])
      {
        'family': 'material',
        'id': 'physical$part',
        'file': file(GeneratedAssetFamily.material, 'physical', '.bin'),
        'stamp': 'x',
        'target': target,
      },
  ];
  final manifest = jsonEncode({
    'schema': GeneratedAssetManifest.schema,
    'package': 'flutter_scene',
    'entries': entries,
  });
  final assets = <String, String>{
    '$_packageTree/$generatedManifestFileName': manifest,
    for (final entry in entries) '$_packageTree/${entry['file']}': '',
  };
  return _MapBundle(assets);
}

final class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{
        for (final asset in assets.keys) asset: <Object?>[],
      })!;
    }
    final value = assets[key];
    if (value == null) throw StateError('missing asset $key');
    return ByteData.sublistView(utf8.encode(value));
  }
}

void main() {
  tearDown(() => clearGeneratedAssetIndexCache());

  test('the probes name entries the bundles actually contain', () {
    // A probe that drifted from the real entry name would fail every load.
    expect(baseShaderBundleProbeName, 'UnskinnedVertex');
    expect(physicalBundleProbeName, 'PhysicalOpaque');
  });

  test('a bundle built only for another platform does not resolve', () async {
    final foreign = currentShaderTarget == 'metalIos' ? 'openglEs' : 'metalIos';
    final bundle = _bundleBuiltFor(foreign);
    expect(await resolveBaseShaderBundleKey(bundle: bundle), isNull);
    expect(await resolvePhysicalBundleKeys(bundle: bundle), isNull);

    final index = await loadGeneratedAssetIndex(bundle);
    expect(
      index.targetsOf(
        GeneratedAssetFamily.shaderBundle,
        'base',
        package: 'flutter_scene',
      ),
      [foreign],
      reason: 'the failure message has to be able to name what was built',
    );
  });

  test('a bundle built for this platform still resolves', () async {
    final bundle = _bundleBuiltFor(currentShaderTarget);
    expect(await resolveBaseShaderBundleKey(bundle: bundle), isNotNull);
    expect(await resolvePhysicalBundleKeys(bundle: bundle), isNotNull);
  });

  test('the wrong-target message names the mismatch and the fix', () {
    final message = baseShaderBundleWrongTargetMessage(['openglEs']);
    expect(message, contains('openglEs'));
    expect(message, contains(currentShaderTarget));
    expect(message, contains('Rebuild'));
    expect(message, isNot(contains(baseShaderBundleMissingMessage)));
  });

  test('the unusable-bundle messages name both causes and the fix', () {
    for (final message in [
      baseShaderBundleUnusableMessage('some.shaderbundle'),
      physicalBundleUnusableMessage('some.shaderbundle'),
    ]) {
      expect(message, contains('some.shaderbundle'));
      // Names our own trim step, not impellerc, which compiles every backend.
      expect(message, contains('trimmed'), reason: 'first cause');
      expect(message, contains('different Flutter engine'), reason: 'second');
      expect(message, contains(currentShaderTarget));
      expect(message, contains('flutter clean'), reason: 'the fix');
      // The old advice was to await a Future the caller had already awaited.
      expect(message, isNot(contains('initializeStaticResources')));
    }
  });
}
