import 'package:flutter_scene/src/importer/model_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelRegistry', () {
    test('isModelAssetKey matches only .model DataAsset keys', () {
      expect(
        ModelRegistry.isModelAssetKey(
          'packages/app/flutter_scene/model/assets/car.model',
        ),
        isTrue,
      );
      expect(ModelRegistry.isModelAssetKey('assets/car.model'), isFalse);
      expect(
        ModelRegistry.isModelAssetKey('packages/app/assets/car.png'),
        isFalse,
      );
    });

    test('resolves a model by source path, ignoring extension', () async {
      final registry = await ModelRegistry.load(
        assetKeys: const [
          'packages/app/flutter_scene/model/assets/vehicles/car.model',
          'assets/other.txt',
        ],
      );

      const key = 'packages/app/flutter_scene/model/assets/vehicles/car.model';
      expect(registry.resolveKey('assets/vehicles/car.glb'), key);
      expect(registry.resolveKey('assets/vehicles/car.model'), key);
      expect(registry.resolveKey('assets/vehicles/car'), key);
    });

    test('same file name in different directories does not collide', () async {
      final registry = await ModelRegistry.load(
        assetKeys: const [
          'packages/app/flutter_scene/model/assets/vehicles/car.model',
          'packages/app/flutter_scene/model/assets/props/car.model',
        ],
      );

      expect(
        registry.resolveKey('assets/vehicles/car.glb'),
        'packages/app/flutter_scene/model/assets/vehicles/car.model',
      );
      expect(
        registry.resolveKey('assets/props/car.glb'),
        'packages/app/flutter_scene/model/assets/props/car.model',
      );
    });

    test('throws when a source path is not found', () async {
      final registry = await ModelRegistry.load(assetKeys: const []);
      expect(
        () => registry.resolveKey('assets/missing.glb'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'requires package disambiguation for duplicate source paths',
      () async {
        final registry = await ModelRegistry.load(
          assetKeys: const [
            'packages/a/flutter_scene/model/assets/car.model',
            'packages/b/flutter_scene/model/assets/car.model',
          ],
        );

        expect(
          () => registry.resolveKey('assets/car.glb'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Pass package to disambiguate'),
            ),
          ),
        );
        expect(
          registry.resolveKey('assets/car.glb', package: 'b'),
          'packages/b/flutter_scene/model/assets/car.model',
        );
      },
    );
  });
}
