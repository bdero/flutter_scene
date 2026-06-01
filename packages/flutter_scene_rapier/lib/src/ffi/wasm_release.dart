// Points the web backend at the WebAssembly build of the shim attached
// to the matching GitHub release. The release workflow uploads the
// module and its checksum; the release step fills these in (the same way
// hook/native_binaries.json is filled in for the native libraries), so
// the published package downloads exactly its own release's module.
//
// Empty [wasmReleaseTag] / [wasmSha256] mean no release has been cut yet.
// Before then, point the web backend at a locally served module with
// --dart-define=FLUTTER_SCENE_RAPIER_WASM_URL=<url> (see
// rapier_bindings_factory_web.dart).

/// Root the release assets are downloaded from.
const String wasmReleaseBaseUrl =
    'https://github.com/bdero/flutter_scene/releases/download';

/// The release tag the module is attached to, e.g.
/// `flutter_scene_rapier-0.0.1`. Empty until the first release.
const String wasmReleaseTag = '';

/// File name of the module within the release.
const String wasmFileName = 'flutter_scene_rapier_native.wasm';

/// Lower-case hex sha256 of the released module, verified after download.
/// Empty until the first release.
const String wasmSha256 = '';
