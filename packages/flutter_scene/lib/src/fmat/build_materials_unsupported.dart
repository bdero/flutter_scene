/// Web/wasm stub for [buildMaterials]. The real implementation uses `dart:io`
/// and `package:flutter_gpu_shaders` to compile `.fmat` materials, and only
/// runs on the native build host (from a consumer's `hook/build.dart`).
/// Routing the web/wasm import here keeps `dart:io` and `package:hooks` off the
/// wasm dependency graph, so the package stays WASM-compatible. Calling it on
/// web/wasm is never expected.
library;

/// Web/wasm placeholder for the native build-hook enum.
enum MaterialAssetMode { legacyOnly, dataAssetsIfAvailable, dataAssetsRequired }

/// Throws on web/wasm; see the library doc above. The native signature takes
/// `BuildInput` / `BuildOutputBuilder` from `package:hooks`; this stub uses
/// `Object` instead so it pulls in no `dart:io`.
Never buildMaterials({
  required Object buildInput,
  required Object buildOutput,
  List<String>? materials,
  String bundleName = 'materials',
  MaterialAssetMode assetMode = MaterialAssetMode.legacyOnly,
}) => throw UnsupportedError(
  'buildMaterials runs at build time on native platforms only.',
);
