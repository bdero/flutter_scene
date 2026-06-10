import 'package:flutter/services.dart';
import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/importer/scene_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SceneRegistry', () {
    test('isSceneAssetKey matches only .fsceneb DataAsset keys', () {
      expect(
        SceneRegistry.isSceneAssetKey(
          'packages/app/flutter_scene/scene/assets/forest.fsceneb',
        ),
        isTrue,
      );
      expect(SceneRegistry.isSceneAssetKey('assets/forest.fsceneb'), isFalse);
      expect(
        SceneRegistry.isSceneAssetKey(
          'packages/app/flutter_scene/model/x.model',
        ),
        isFalse,
      );
    });

    test('resolves a scene by source path, ignoring extension', () async {
      final registry = await SceneRegistry.load(
        assetKeys: const [
          'packages/app/flutter_scene/scene/assets/levels/forest.fsceneb',
          'assets/other.txt',
        ],
      );

      const key =
          'packages/app/flutter_scene/scene/assets/levels/forest.fsceneb';
      expect(registry.resolveKey('assets/levels/forest.glb'), key);
      expect(registry.resolveKey('assets/levels/forest.fsceneb'), key);
      expect(registry.resolveKey('assets/levels/forest'), key);
    });

    test('same file name in different directories does not collide', () async {
      final registry = await SceneRegistry.load(
        assetKeys: const [
          'packages/app/flutter_scene/scene/assets/a/forest.fsceneb',
          'packages/app/flutter_scene/scene/assets/b/forest.fsceneb',
        ],
      );
      expect(
        registry.resolveKey('assets/a/forest.glb'),
        'packages/app/flutter_scene/scene/assets/a/forest.fsceneb',
      );
      expect(
        registry.resolveKey('assets/b/forest.glb'),
        'packages/app/flutter_scene/scene/assets/b/forest.fsceneb',
      );
    });

    test('throws when a source path is not found', () async {
      final registry = await SceneRegistry.load(assetKeys: const []);
      expect(
        () => registry.resolveKey('assets/missing.glb'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'requires package disambiguation for duplicate source paths',
      () async {
        final registry = await SceneRegistry.load(
          assetKeys: const [
            'packages/a/flutter_scene/scene/assets/forest.fsceneb',
            'packages/b/flutter_scene/scene/assets/forest.fsceneb',
          ],
        );
        expect(
          () => registry.resolveKey('assets/forest.glb'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Pass package to disambiguate'),
            ),
          ),
        );
        expect(
          registry.resolveKey('assets/forest.glb', package: 'b'),
          'packages/b/flutter_scene/scene/assets/forest.fsceneb',
        );
      },
    );
  });

  group('prefab hot reload', () {
    const hostKey = 'packages/app/flutter_scene/scene/assets/host.fsceneb';
    const prefabKey = 'packages/app/flutter_scene/scene/assets/prefab.fsceneb';

    Uint8List prefabBytes(String detailName) {
      final prefab = SceneDocument();
      final root = prefab.createNode(name: 'prefabRoot', root: true);
      final detail = prefab.createNode(name: detailName);
      root.children.add(detail.id);
      return writeFsceneb(prefab);
    }

    Uint8List hostBytes() {
      final host = SceneDocument();
      host.createNode(name: 'inst', root: true).instance = PrefabInstanceSpec(
        source: const AssetRef('assets/prefab'),
        load: LoadPolicy.eager,
      );
      return writeFsceneb(host);
    }

    test('an edit to a referenced prefab patches the host scene', () async {
      final bundle = _BytesAssetBundle({
        hostKey: hostBytes(),
        prefabKey: prefabBytes('detail'),
      });
      final registry = await SceneRegistry.load(
        assetKeys: const [hostKey, prefabKey],
      );

      final root = await registry.loadScene('assets/host', bundle: bundle);
      final inst = root.getChildByName('inst')!;
      expect(root.getChildByName('detail'), isNotNull);

      // Baseline pass so the coordinator has hashes for both assets.
      HotReloadCoordinator.instance.onReassemble();
      await _settle(() => false);

      // Edit only the prefab; the host bytes are untouched.
      bundle.assets[prefabKey] = prefabBytes('renamed');
      HotReloadCoordinator.instance.onReassemble();
      await _settle(() => root.getChildByName('renamed') != null);

      expect(root.getChildByName('renamed'), isNotNull);
      expect(root.getChildByName('detail'), isNull);
      // The instance node is host-owned and keeps its identity.
      expect(root.getChildByName('inst'), same(inst));
    });
  });
}

// Waits for the coordinator's fire-and-forget refresh to settle (or [done] to
// turn true).
Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
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
