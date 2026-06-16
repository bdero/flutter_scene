// Covers SceneRegistry.resolveRefKey: a prefab reference inside a scene is
// resolved relative to that scene's directory (how the editor authors linked
// imports), with a fallback to a package-root-relative reference. This is what
// lets an authored scene's imported/ assets resolve from the bundle at runtime.

import 'package:flutter_scene/src/importer/scene_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SceneRegistry registry;

  setUp(() async {
    registry = await SceneRegistry.load(
      assetKeys: const [
        'packages/app/flutter_scene/scene/assets/levels/forest.fsceneb',
        'packages/app/flutter_scene/scene/assets/levels/imported/tree.fsceneb',
        'packages/app/flutter_scene/scene/assets/shared/rock.fsceneb',
      ],
    );
  });

  test('resolves a sibling-relative prefab ref against the host scene dir', () {
    expect(
      registry.resolveRefKey(
        'assets/levels/forest',
        'imported/tree.fsceneb',
        'app',
      ),
      'packages/app/flutter_scene/scene/assets/levels/imported/tree.fsceneb',
    );
  });

  test('resolves a parent-relative (..) prefab ref', () {
    expect(
      registry.resolveRefKey(
        'assets/levels/forest',
        '../shared/rock.fsceneb',
        'app',
      ),
      'packages/app/flutter_scene/scene/assets/shared/rock.fsceneb',
    );
  });

  test('falls back to a package-root-relative ref when not found locally', () {
    expect(
      registry.resolveRefKey(
        'assets/levels/forest',
        'assets/shared/rock.fsceneb',
        'app',
      ),
      'packages/app/flutter_scene/scene/assets/shared/rock.fsceneb',
    );
  });

  test('still resolves a ref that matches by package-root path', () {
    // A top-level scene (no directory) with a package-relative ref.
    expect(
      registry.resolveRefKey('forest', 'assets/levels/forest.fsceneb', 'app'),
      'packages/app/flutter_scene/scene/assets/levels/forest.fsceneb',
    );
  });
}
