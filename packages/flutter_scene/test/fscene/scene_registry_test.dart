import 'package:flutter/services.dart';
import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/fscene/stream/stream.dart' show unloadSubtree;
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
        SceneRegistry.isSceneAssetKey('packages/app/flutter_scene/other/x.bin'),
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

      var reloads = 0;
      final root = await registry.loadScene(
        'assets/host',
        bundle: bundle,
        onReload: (_) => reloads++,
      );
      final inst = root.getChildByName('inst')!;
      expect(root.getChildByName('detail'), isNotNull);

      // Baseline pass so the coordinator has hashes for both assets.
      HotReloadCoordinator.instance.onReassemble();
      await _settle(() => false);
      final baselineReloads = reloads;

      // Edit only the prefab; the host bytes are untouched.
      bundle.assets[prefabKey] = prefabBytes('renamed');
      HotReloadCoordinator.instance.onReassemble();
      await _settle(() => root.getChildByName('renamed') != null);

      expect(root.getChildByName('renamed'), isNotNull);
      expect(root.getChildByName('detail'), isNull);
      // The instance node is host-owned and keeps its identity.
      expect(root.getChildByName('inst'), same(inst));
      // The app callback ran after the patch.
      expect(reloads, greaterThan(baselineReloads));
    });

    test('stable prefab ids patch prefab nodes fine-grained', () async {
      // Authored documents with fixed ids: recomposing after an edit derives
      // the same per-instance ids, so the diff patches the existing live
      // nodes instead of rebuilding the subtree.
      const stableHostKey =
          'packages/app/flutter_scene/scene/assets/stable_host.fsceneb';
      const stablePrefabKey =
          'packages/app/flutter_scene/scene/assets/stable_prefab.fsceneb';

      Uint8List prefabNamed(String detailName) {
        final doc = SceneDocument(
          documentId: DocumentId(Uint8List(16)..[0] = 7),
        );
        doc.addNode(
          NodeSpec(
            id: const LocalId(4, 1),
            name: 'prefabRoot',
            children: [const LocalId(4, 2)],
          ),
          root: true,
        );
        doc.addNode(NodeSpec(id: const LocalId(4, 2), name: detailName));
        return writeFsceneb(doc);
      }

      Uint8List hostDoc() {
        final doc = SceneDocument(
          documentId: DocumentId(Uint8List(16)..[0] = 8),
        );
        doc.addNode(
          NodeSpec(
            id: const LocalId(5, 1),
            name: 'inst',
            instance: PrefabInstanceSpec(
              source: const AssetRef('assets/stable_prefab'),
            ),
          ),
          root: true,
        );
        return writeFsceneb(doc);
      }

      final bundle = _BytesAssetBundle({
        stableHostKey: hostDoc(),
        stablePrefabKey: prefabNamed('detail'),
      });
      final registry = await SceneRegistry.load(
        assetKeys: const [stableHostKey, stablePrefabKey],
      );

      final root = await registry.loadScene(
        'assets/stable_host',
        bundle: bundle,
      );
      final detail = root.getChildByName('detail')!;

      bundle.assets[stablePrefabKey] = prefabNamed('renamed');
      HotReloadCoordinator.instance.onReassemble();
      await _settle(() => root.getChildByName('renamed') != null);

      // The same live node was renamed in place rather than replaced.
      expect(root.getChildByName('renamed'), same(detail));
    });
  });

  group('streamed subtrees', () {
    test(
      'loadSubtree streams by source path and hot-reloads in place',
      () async {
        const hostKey =
            'packages/app/flutter_scene/scene/assets/stream_host.fsceneb';
        const prefabKey =
            'packages/app/flutter_scene/scene/assets/stream_prefab.fsceneb';

        Uint8List prefabNamed(String name) {
          final doc = SceneDocument();
          doc.createNode(name: name, root: true);
          return writeFsceneb(doc);
        }

        Uint8List hostDoc() {
          final doc = SceneDocument();
          doc
              .createNode(name: 'spot', root: true)
              .instance = PrefabInstanceSpec(
            source: const AssetRef('assets/stream_prefab'),
            load: LoadPolicy.lazy,
          );
          return writeFsceneb(doc);
        }

        final bundle = _BytesAssetBundle({
          hostKey: hostDoc(),
          prefabKey: prefabNamed('tree'),
        });
        final registry = await SceneRegistry.load(
          assetKeys: const [hostKey, prefabKey],
        );

        final root = await registry.loadScene(
          'assets/stream_host',
          bundle: bundle,
        );
        final placeholder = root.getChildByName('spot')!;
        expect(placeholder.children, isEmpty);

        await registry.loadSubtree(placeholder, bundle: bundle);
        expect(root.getChildByName('tree'), isNotNull);

        // Editing the streamed prefab re-streams the loaded subtree in place.
        bundle.assets[prefabKey] = prefabNamed('bush');
        HotReloadCoordinator.instance.onReassemble();
        await _settle(() => root.getChildByName('bush') != null);
        expect(root.getChildByName('bush'), isNotNull);
        expect(root.getChildByName('tree'), isNull);

        // An unloaded placeholder is left alone by further edits.
        unloadSubtree(placeholder);
        bundle.assets[prefabKey] = prefabNamed('rock');
        HotReloadCoordinator.instance.onReassemble();
        await _settle(() => false);
        expect(placeholder.children, isEmpty);
      },
    );
  });

  group('scene templates', () {
    test('repeat loads share the cached template', () async {
      const key = 'packages/app/flutter_scene/scene/assets/shared.fsceneb';
      final doc = SceneDocument();
      doc.addNode(NodeSpec(id: const LocalId(3, 1), name: 'thing'), root: true);
      final bundle = _BytesAssetBundle({key: writeFsceneb(doc)});
      final registry = await SceneRegistry.load(assetKeys: const [key]);

      final a = await registry.loadScene('assets/shared', bundle: bundle);
      final b = await registry.loadScene('assets/shared', bundle: bundle);

      // Two independent instances of the same scene.
      expect(identical(a, b), isFalse);
      expect(a.getChildByName('thing'), isNotNull);
      expect(b.getChildByName('thing'), isNotNull);
      expect(
        identical(a.getChildByName('thing'), b.getChildByName('thing')),
        isFalse,
      );
      // The asset was read (and the document composed) once.
      expect(bundle.loadCounts[key], 1);
    });

    test('hot reload invalidates the cached template', () async {
      const key = 'packages/app/flutter_scene/scene/assets/inval.fsceneb';
      Uint8List named(String name) {
        final doc = SceneDocument();
        doc.addNode(NodeSpec(id: const LocalId(3, 2), name: name), root: true);
        return writeFsceneb(doc);
      }

      final bundle = _BytesAssetBundle({key: named('one')});
      final registry = await SceneRegistry.load(assetKeys: const [key]);

      final root = await registry.loadScene('assets/inval', bundle: bundle);
      expect(root.getChildByName('one'), isNotNull);

      bundle.assets[key] = named('two');
      HotReloadCoordinator.instance.onReassemble();
      await _settle(() => root.getChildByName('two') != null);
      expect(root.getChildByName('two'), isNotNull); // patched in place

      // A fresh load sees the edited content, not the stale template.
      final fresh = await registry.loadScene('assets/inval', bundle: bundle);
      expect(fresh.getChildByName('two'), isNotNull);
      expect(fresh.getChildByName('one'), isNull);
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

  /// Successful [load] calls per key.
  final Map<String, int> loadCounts = {};

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) {
      throw StateError('Missing test asset: $key');
    }
    loadCounts[key] = (loadCounts[key] ?? 0) + 1;
    return ByteData.sublistView(bytes);
  }
}
