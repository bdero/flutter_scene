import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercises the coordinator's environment registrations directly (a plain
// anchor and reload closure); the GPU-dependent load itself is out of scope.
void main() {
  group('environment hot reload registrations', () {
    test('re-runs the load when the asset content changes', () async {
      const key = 'assets/sky_a.hdr';
      final bundle = _BytesAssetBundle({
        key: Uint8List.fromList([1, 2, 3]),
      });
      final anchor = Object();
      var reloads = 0;
      HotReloadCoordinator.instance.registerEnvironment(
        anchor,
        assetKey: key,
        bundle: bundle,
        onReload: () async => reloads++,
      );

      // Baseline pass so the coordinator has a hash for the asset.
      HotReloadCoordinator.instance.onReassemble();
      await _settle();
      final baseline = reloads;

      bundle.assets[key] = Uint8List.fromList([4, 5, 6]);
      HotReloadCoordinator.instance.onReassemble();
      await _settle();
      expect(reloads, baseline + 1);

      // Unchanged content does not re-run the load.
      HotReloadCoordinator.instance.onReassemble();
      await _settle();
      expect(reloads, baseline + 1);
    });

    test(
      'a later registration for the same anchor replaces the first',
      () async {
        const key = 'assets/sky_b.hdr';
        final bundle = _BytesAssetBundle({
          key: Uint8List.fromList([1]),
        });
        final anchor = Object();
        var first = 0;
        var second = 0;
        HotReloadCoordinator.instance.registerEnvironment(
          anchor,
          assetKey: key,
          bundle: bundle,
          onReload: () async => first++,
        );
        HotReloadCoordinator.instance.registerEnvironment(
          anchor,
          assetKey: key,
          bundle: bundle,
          onReload: () async => second++,
        );

        HotReloadCoordinator.instance.onReassemble();
        await _settle();
        bundle.assets[key] = Uint8List.fromList([2]);
        HotReloadCoordinator.instance.onReassemble();
        await _settle();

        expect(first, 0);
        expect(second, 1);
      },
    );

    test(
      'a reload closure may re-register without disrupting the pass',
      () async {
        // Scene.loadEnvironment re-registers when its reload closure re-runs
        // it; the refresh iterates a snapshot so this must not throw.
        const key = 'assets/sky_c.hdr';
        final bundle = _BytesAssetBundle({
          key: Uint8List.fromList([1]),
        });
        final anchor = Object();
        var reloads = 0;
        HotReloadCoordinator.instance.registerEnvironment(
          anchor,
          assetKey: key,
          bundle: bundle,
          onReload: () async {
            reloads++;
            HotReloadCoordinator.instance.registerEnvironment(
              anchor,
              assetKey: key,
              bundle: bundle,
              onReload: () async => reloads++,
            );
          },
        );

        HotReloadCoordinator.instance.onReassemble();
        await _settle();
        bundle.assets[key] = Uint8List.fromList([2]);
        HotReloadCoordinator.instance.onReassemble();
        await _settle();

        expect(reloads, 1);
      },
    );
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
