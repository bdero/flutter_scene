/// The shelf's folder model: what "here" means, and what lands in it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_scene_editor/src/assets/asset_index.dart';

void main() {
  test('a file is classified by its extension, and only if it is an asset', () {
    expect(assetKindOf('body.glb'), FileAssetKind.model);
    expect(assetKindOf('Room.GLTF'), FileAssetKind.model);
    expect(assetKindOf('albedo.png'), FileAssetKind.image);
    expect(assetKindOf('studio.hdr'), FileAssetKind.environmentImage);
    expect(assetKindOf('level.fscene'), FileAssetKind.scene);
    expect(assetKindOf('paint.fmat'), FileAssetKind.material);
    expect(assetKindOf('Door.blueprint'), FileAssetKind.blueprint);

    // Everything else is left where it is rather than copied into a project
    // that has no use for it.
    expect(assetKindOf('notes.txt'), isNull);
    expect(assetKindOf('README'), isNull);
    expect(assetKindOf('.hdr'), isNull);
  });
}
