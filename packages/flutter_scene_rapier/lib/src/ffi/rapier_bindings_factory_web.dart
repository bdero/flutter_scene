// Web backend factory: the shim is a WebAssembly module downloaded from
// the package's release (the web counterpart of the native build hook's
// prebuilt download), instantiated once and shared by every world. It
// must be loaded before the first world is created; ensureRapierReady
// does the download + checksum, and createRapierBindings then spins up a
// world on the shared instance synchronously.
//
// During development, before a release exists, set
// --dart-define=FLUTTER_SCENE_RAPIER_WASM_URL=<url> to load a locally
// served module instead (checksum verification is skipped for an
// explicit override). A relative, same-origin URL avoids CORS.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/wasm_rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/wasm_release.dart';
import 'package:flutter_scene_rapier/src/ffi/wasm_runtime_web.dart';

const _urlOverride = String.fromEnvironment('FLUTTER_SCENE_RAPIER_WASM_URL');

JsWasmRuntime? _runtime;

/// Downloads and instantiates the shim's WebAssembly module once. Safe to
/// call repeatedly; later calls return immediately.
Future<void> ensureRapierReady() async {
  if (_runtime != null) return;
  final (url, expectedSha256) = _resolveSource();
  final bytes = await _fetchBytes(url);
  if (expectedSha256 != null) {
    final actual = sha256.convert(bytes).toString();
    if (actual != expectedSha256) {
      throw StateError(
        'Checksum mismatch for the Rapier wasm module from $url.\n'
        '  expected: $expectedSha256\n  actual:   $actual',
      );
    }
  }
  _runtime = await JsWasmRuntime.instantiate(bytes);
}

/// Creates a world on the shared module instance. Throws if the module
/// has not been loaded yet.
RapierBindings createRapierBindings() {
  final runtime = _runtime;
  if (runtime == null) {
    throw StateError(
      'The Rapier WebAssembly module is not loaded. Await '
      'RapierWorld.ensureInitialized() before constructing a RapierWorld '
      'on the web.',
    );
  }
  return WasmRapierBindings(runtime);
}

// Returns the module URL and the sha256 to verify it against (null when
// no verification applies, i.e. an explicit dev override).
(String, String?) _resolveSource() {
  if (_urlOverride.isNotEmpty) return (_urlOverride, null);
  if (wasmReleaseTag.isEmpty || wasmSha256.isEmpty) {
    throw StateError(
      'No Rapier wasm release is configured yet. Build the module and set '
      '--dart-define=FLUTTER_SCENE_RAPIER_WASM_URL=<url> to a served copy, '
      'or use a published release of flutter_scene_rapier.',
    );
  }
  return ('$wasmReleaseBaseUrl/$wasmReleaseTag/$wasmFileName', wasmSha256);
}

Future<Uint8List> _fetchBytes(String url) async {
  final response = await _fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError(
      'Could not download the Rapier wasm module from $url: '
      'HTTP ${response.status}',
    );
  }
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(JSString url);

extension type _FetchResponse(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
