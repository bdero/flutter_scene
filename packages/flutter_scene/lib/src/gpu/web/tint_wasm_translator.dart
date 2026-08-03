/// Loads the tint_wasm artifact and drives it through its C ABI.
///
/// The artifact is built by `tools/tint_wasm/build.sh`; see that directory's
/// README for the exported surface. It is fetched rather than bundled, because
/// Flutter assets cannot be made conditional per platform and ~4 MB of wasm in
/// every native app's bundle would be dead weight.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import '../shared/wgsl_translator.dart';

/// The ES module namespace tint_wasm.mjs exposes.
extension type _TintNamespace._(JSObject _) implements JSObject {
  /// `createTintWasm`, which resolves to the instantiated module.
  @JS('default')
  external JSPromise<_TintModule> createModule();
}

/// The instantiated emscripten module, as its C ABI plus the runtime helpers
/// the build exports.
extension type _TintModule._(JSObject _) implements JSObject {
  @JS('_tw_init')
  external void twInit();

  @JS('_tw_revision')
  external int twRevision();

  @JS('_tw_translate')
  external int twTranslate(
    int spirv,
    int wordCount,
    int mappings,
    int mappingCount,
    int allowNonUniformDerivatives,
    int minify,
  );

  @JS('_tw_wgsl')
  external int twWgsl();

  @JS('_tw_error')
  external int twError();

  @JS('_malloc')
  external int malloc(int bytes);

  @JS('_free')
  external void free(int pointer);

  @JS('HEAPU32')
  external JSUint32Array get heapU32;

  @JS('UTF8ToString')
  external String utf8ToString(int pointer);
}

/// Where the tint_wasm glue module is fetched from.
///
/// Defaults to the published copy. Point this at an asset URL to vendor the
/// artifact, which offline and CSP-restricted deployments need. Must be set
/// before the WebGPU backend initializes.
String tintWasmModuleUrl = _defaultModuleUrl;

const _defaultModuleUrl = String.fromEnvironment(
  'FLUTTER_SCENE_TINT_WASM_URL',
  defaultValue: 'https://wasm.fscene.dev/tint_wasm/tint_wasm.mjs',
);

/// A [WgslTranslator] backed by Tint compiled to WebAssembly.
class TintWasmTranslator implements WgslTranslator {
  TintWasmTranslator({String? moduleUrl})
    : _moduleUrl = moduleUrl ?? tintWasmModuleUrl;

  final String _moduleUrl;
  _TintModule? _module;
  String _revision = 'uninitialized';
  Future<void>? _initializing;

  @override
  String get revision => _revision;

  /// Whether the artifact is loaded and ready to translate.
  bool get isReady => _module != null;

  @override
  Future<void> initialize() {
    // Concurrent callers share one load rather than racing two fetches.
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final namespace =
          (await importModule(_moduleUrl.toJS).toDart) as _TintNamespace;
      final module = await namespace.createModule().toDart;
      module.twInit();
      _module = module;
      _revision = module.utf8ToString(module.twRevision());
    } on Object catch (e) {
      // Reset so a later attempt can retry rather than being stuck on a
      // transient network failure.
      _initializing = null;
      throw WgslTranslationException(
        '<tint_wasm>',
        'could not load the translator from $_moduleUrl, $e',
      );
    }
  }

  @override
  String translate(
    Uint32List spirv, {
    required String shaderName,
    Map<int, int> samplerBindings = const {},
    bool allowNonUniformDerivatives = true,
    bool minify = false,
  }) {
    final m = _module;
    if (m == null) {
      throw WgslTranslationException(
        shaderName,
        'the translator is not initialized; await initialize() first',
      );
    }

    // Flat [fromGroup, fromBinding, toGroup, toBinding] quads. Group is always
    // 0, since impellerc only ever emits descriptor set 0.
    final mappings = Uint32List(samplerBindings.length * 4);
    var i = 0;
    for (final entry in samplerBindings.entries) {
      mappings[i++] = 0;
      mappings[i++] = entry.key;
      mappings[i++] = 0;
      mappings[i++] = entry.value;
    }

    final spirvPtr = _allocate(m, spirv.lengthInBytes);
    final mappingPtr = mappings.isEmpty
        ? 0
        : _allocate(m, mappings.lengthInBytes);
    try {
      _copyInto(m, spirvPtr, spirv);
      if (mappings.isNotEmpty) _copyInto(m, mappingPtr, mappings);

      final ok = m.twTranslate(
        spirvPtr,
        spirv.length,
        mappingPtr,
        samplerBindings.length,
        allowNonUniformDerivatives ? 1 : 0,
        minify ? 1 : 0,
      );
      if (ok == 0) {
        throw WgslTranslationException(shaderName, m.utf8ToString(m.twError()));
      }
      return m.utf8ToString(m.twWgsl());
    } finally {
      m.free(spirvPtr);
      if (mappingPtr != 0) m.free(mappingPtr);
    }
  }

  static int _allocate(_TintModule m, int bytes) {
    final pointer = m.malloc(bytes);
    if (pointer == 0) {
      throw WgslTranslationException(
        '<tint_wasm>',
        'out of wasm memory allocating $bytes bytes',
      );
    }
    return pointer;
  }

  /// HEAPU32 is replaced whenever the wasm heap grows, so it is read fresh on
  /// every copy rather than cached.
  static void _copyInto(_TintModule m, int pointer, Uint32List words) {
    m.heapU32.toDart.setRange(
      pointer >> 2,
      (pointer >> 2) + words.length,
      words,
    );
  }
}
