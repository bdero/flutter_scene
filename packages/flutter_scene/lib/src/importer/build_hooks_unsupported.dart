/// Web/wasm stub for the build-hook helpers. The real [buildScenes] uses
/// `dart:io` to write `.fsceneb` files and only runs on the native build host
/// (from a consumer's `hook/build.dart`). Routing the web/wasm import here
/// keeps `dart:io` (and `package:hooks`) off the wasm dependency graph, so the
/// package stays WASM-compatible. Calling it on web/wasm is never expected.
library;

/// Web/wasm placeholder for the native build-hook enum.
enum SceneAssetMode { legacyOnly, dataAssetsIfAvailable, dataAssetsRequired }

/// Throws on web/wasm; see the library doc above. The native signature takes a
/// `BuildInput` / `BuildOutputBuilder` from `package:hooks`; this stub uses
/// `Object` instead so it pulls in no `dart:io`.
Never buildScenes({
  required Object buildInput,
  required Object buildOutput,
  List<String>? inputFilePaths,
  String outputDirectory = 'build/scenes/',
  String discoveryRoot = 'assets/',
  SceneAssetMode assetMode = SceneAssetMode.legacyOnly,
  bool compressTextures = false,
}) => throw UnsupportedError(
  'buildScenes runs at build time on native platforms only.',
);
