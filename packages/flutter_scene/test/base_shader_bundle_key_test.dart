import 'package:flutter/services.dart';
import 'package:flutter_gpu_shaders/build.dart' as gpu_shaders;
// ignore: implementation_imports
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_test/flutter_test.dart';

const String _legacyKey =
    'packages/flutter_scene/build/shaderbundles/base.shaderbundle';
const String _dataAssetKey =
    'packages/flutter_scene/flutter_gpu_shaders/shaderbundles/base.shaderbundle';

/// Serves a synthesized `AssetManifest.bin` listing [assetKeys].
class _ManifestAssetBundle extends CachingAssetBundle {
  _ManifestAssetBundle(this.assetKeys);

  final List<String> assetKeys;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = <String, Object>{
        for (final asset in assetKeys) asset: <Object>[],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
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

void main() {
  test('prefers the data-asset key when the manifest lists it', () async {
    final bundle = _ManifestAssetBundle([_legacyKey, _dataAssetKey]);
    expect(await resolveBaseShaderBundleKey(bundle: bundle), _dataAssetKey);
  });

  test('falls back to the legacy key on a legacy-only manifest', () async {
    final bundle = _ManifestAssetBundle([_legacyKey]);
    expect(await resolveBaseShaderBundleKey(bundle: bundle), _legacyKey);
  });

  test('falls back to the legacy key without a manifest', () async {
    expect(
      await resolveBaseShaderBundleKey(bundle: _EmptyAssetBundle()),
      _legacyKey,
    );
  });

  test('the data-asset key matches what the build hook registers', () {
    // The hook (hook/build.dart) registers the bundle through
    // flutter_gpu_shaders' data-asset naming; the runtime constant must
    // resolve to the same flutter asset key.
    expect(
      gpu_shaders.flutterDataAssetKey(
        package: 'flutter_scene',
        name: gpu_shaders.shaderBundleDataAssetName('base.shaderbundle'),
      ),
      _dataAssetKey,
    );
  });
}
