import 'package:flutter_scene/build_hooks.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The removed modes stay on the enums so an upgraded hook fails with the
  // migration rather than an undefined name.
  test('the message names the mode, the replacement, and the setup', () {
    Object? caught;
    try {
      throwRemovedAssetMode(
        'SceneAssetMode.legacyOnly',
        'SceneAssetMode.generatedTree',
      );
    } catch (e) {
      caught = e;
    }
    expect(
      caught.toString(),
      allOf(
        contains('SceneAssetMode.legacyOnly'),
        contains('SceneAssetMode.generatedTree'),
        contains('flutter_scene:init'),
        contains(generatedAssetsEntry),
      ),
    );
  });

  test('every builder still exposes the removed names', () {
    // Referencing them is the point; a rename would break an upgrading hook
    // at the name rather than at the message.
    // ignore: deprecated_member_use
    expect(SceneAssetMode.values, contains(SceneAssetMode.legacyOnly));
    // ignore: deprecated_member_use
    expect(MaterialAssetMode.values, contains(MaterialAssetMode.legacyOnly));
    // ignore: deprecated_member_use
    expect(TextureAssetMode.values, contains(TextureAssetMode.legacyOnly));
    expect(
      TargetShaderBundleAssetMode.values,
      // ignore: deprecated_member_use
      contains(TargetShaderBundleAssetMode.dataAssetsIfAvailable),
    );
  });
}
