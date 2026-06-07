/// Web/wasm stub for the build-hook helpers. The real [buildModels] uses
/// `dart:io` to write `.model` files and only runs on the native build host
/// (from a consumer's `hook/build.dart`). Routing the web/wasm import here
/// keeps `dart:io` (and `package:hooks`) off the wasm dependency graph, so the
/// package stays WASM-compatible. Calling it on web/wasm is never expected.
library;

/// Web/wasm placeholder for the native build-hook enum.
enum ModelAssetMode { legacyOnly, dataAssetsIfAvailable, dataAssetsRequired }

/// Throws on web/wasm; see the library doc above. The native signature takes a
/// `BuildInput` / `BuildOutputBuilder` from `package:hooks`; this stub uses
/// `Object` instead so it pulls in no `dart:io`.
Never buildModels({
  required Object buildInput,
  required Object buildOutput,
  List<String>? inputFilePaths,
  String outputDirectory = 'build/models/',
  ModelAssetMode assetMode = ModelAssetMode.legacyOnly,
}) => throw UnsupportedError(
  'buildModels runs at build time on native platforms only.',
);
