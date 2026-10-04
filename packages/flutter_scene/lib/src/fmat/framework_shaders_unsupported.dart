/// Web/wasm stub for [engineShaderIncludeDirectory]. The real implementation
/// uses `dart:io` and only runs on the native build host (from a consumer's
/// `hook/build.dart`). Routing the web/wasm import here keeps `dart:io` and
/// `package:hooks` off the wasm dependency graph.
library;

/// Throws on web/wasm; see the library doc above. The native signature takes
/// `BuildInput` from `package:hooks`; this stub uses `Object` instead so it
/// pulls in no `dart:io`.
Never engineShaderIncludeDirectory(Object buildInput) => throw UnsupportedError(
  'engineShaderIncludeDirectory runs at build time on native hosts only.',
);
