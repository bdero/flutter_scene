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

/// Root the module is downloaded from: a CORS proxy in front of the
/// GitHub release (see tool/wasm_cors_proxy/). GitHub release assets lack
/// CORS headers, which a browser fetch requires, so the worker re-serves
/// the release asset with CORS. `$wasmReleaseBaseUrl/$wasmReleaseTag/
/// $wasmFileName` resolves to the matching release asset. Set this to the
/// URL `wrangler deploy` prints for the worker.
const String wasmReleaseBaseUrl =
    'https://flutter-scene-wasm.bdero.workers.dev';

/// The release tag the module is attached to, e.g.
/// `flutter_scene_rapier-0.0.1`. Empty until the first release.
const String wasmReleaseTag = 'flutter_scene_rapier-0.0.1-dev.1';

/// File name of the module within the release.
const String wasmFileName = 'flutter_scene_rapier_native.wasm';

/// Lower-case hex sha256 of the released module, verified after download.
/// Empty until the first release.
const String wasmSha256 =
    'f016ad51d4d1ab180311083a05a59e76454e294e6b1497b629871a6de37b263e';
