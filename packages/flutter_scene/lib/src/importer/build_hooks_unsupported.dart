/// Web/wasm stub for the build-hook helpers. The real [buildModels] uses
/// `dart:io` to write `.model` files and only runs on the native build host
/// (from a consumer's `hook/build.dart`). Routing the web/wasm import here
/// keeps `dart:io` (and `package:hooks`) off the wasm dependency graph, so the
/// package stays WASM-compatible. Calling it on web/wasm is never expected.
library;

/// Throws on web/wasm; see the library doc above. The native signature takes a
/// `BuildInput` from `package:hooks`; this stub avoids that import so it pulls
/// in no `dart:io`.
Never buildModels({
  required Object buildInput,
  required List<String> inputFilePaths,
  String outputDirectory = 'build/models/',
}) =>
    throw UnsupportedError(
      'buildModels runs at build time on native platforms only.',
    );
