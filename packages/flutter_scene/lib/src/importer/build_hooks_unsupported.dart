/// Web/wasm stub for the build-hook helpers. The real [buildScenes] uses
/// `dart:io` to write `.fsceneb` files and only runs on the native build host
/// (from a consumer's `hook/build.dart`). Routing the web/wasm import here
/// keeps `dart:io` (and `package:hooks`) off the wasm dependency graph, so the
/// package stays WASM-compatible. Calling it on web/wasm is never expected.
library;

/// Web/wasm placeholder for the native build-hook enum.
enum SceneAssetMode {
  generatedTree,
  dataAssetsRequired,

  @Deprecated(
    'Removed in 0.21.0. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  legacyOnly,
  @Deprecated(
    'Removed in 0.21.0. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  dataAssetsIfAvailable,
}

/// Throws on web/wasm; see the library doc above. The native signature takes a
/// `BuildInput` / `BuildOutputBuilder` from `package:hooks`; this stub uses
/// `Object` instead so it pulls in no `dart:io`.
Never buildScenes({
  required Object buildInput,
  required Object buildOutput,
  List<String>? inputFilePaths,
  String discoveryRoot = 'assets/',
  SceneAssetMode assetMode = SceneAssetMode.generatedTree,
  bool compressTextures = false,
  bool alignForCompression = false,
}) => throw UnsupportedError(
  'buildScenes runs at build time on native platforms only.',
);
