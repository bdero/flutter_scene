import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercises the coordinator's texture registrations directly (a plain source
// and reload closure); the GPU upload itself is out of scope.
void main() {
  test('reloads a texture whose cooked file was renamed', () async {
    const fstex = 'packages/app/flutter_scene/texture/assets/ground.fstex';
    const ktx2 = 'packages/app/flutter_scene/texture/assets/ground.ktx2';
    final bundle = _BytesAssetBundle({
      fstex: Uint8List.fromList([1, 2, 3]),
    });
    final source = Object();
    var resolved = fstex;
    final reloads = <String>[];
    HotReloadCoordinator.instance.registerTexture(
      source,
      assetKey: fstex,
      bundle: bundle,
      resolveAssetKey: () async => resolved,
      onReload: (key) async => reloads.add(key),
    );

    // Baseline pass so the coordinator has a hash for the asset.
    HotReloadCoordinator.instance.onReassemble();
    await _settle();
    expect(reloads, isEmpty);

    // Switching encodings replaces the .fstex with a .ktx2.
    bundle.assets
      ..remove(fstex)
      ..[ktx2] = Uint8List.fromList([4, 5, 6]);
    resolved = ktx2;
    HotReloadCoordinator.instance.onReassemble();
    await _settle();
    expect(reloads, [ktx2]);

    // Later edits reload through the new key.
    bundle.assets[ktx2] = Uint8List.fromList([7, 8, 9]);
    HotReloadCoordinator.instance.onReassemble();
    await _settle();
    expect(reloads, [ktx2, ktx2]);

    // An unchanged pass does nothing.
    HotReloadCoordinator.instance.onReassemble();
    await _settle();
    expect(reloads, [ktx2, ktx2]);
    expect(source, isNotNull); // keeps the weakly held source alive
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _BytesAssetBundle extends CachingAssetBundle {
  _BytesAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(bytes);
  }
}
