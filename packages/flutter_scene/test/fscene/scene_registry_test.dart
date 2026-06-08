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
}
