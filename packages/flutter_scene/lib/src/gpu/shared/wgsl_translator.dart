/// The SPIR-V to WGSL translation seam.
///
/// The bundle's Vulkan SPIR-V is translated to WGSL before it reaches a WebGPU
/// backend. Everything about that translation is backend agnostic except where
/// the translator itself comes from, which is Tint compiled to wasm on the web
/// and Tint linked natively elsewhere. This is the seam between the two.
library;

import 'dart:typed_data';

import 'wgsl_bindings.dart';

/// The result of translating one shader.
typedef WgslTranslation = ({String wgsl, WgslBindingMap bindings});

/// Raised when a shader could not be translated.
class WgslTranslationException implements Exception {
  WgslTranslationException(this.shaderName, this.reason);

  /// The bundle entry that failed, for locating it in a large bundle.
  final String shaderName;
  final String reason;

  @override
  String toString() =>
      'WgslTranslationException: failed to translate "$shaderName", $reason';
}

/// Translates SPIR-V modules to WGSL.
///
/// Implementations are expected to be cheap to call repeatedly; callers do not
/// cache, [WgslTranslationCache] does.
abstract class WgslTranslator {
  /// Prepares the translator. Safe to call more than once.
  Future<void> initialize();

  /// Translates [spirv], asking for [samplerBindings] to be honored exactly.
  ///
  /// [samplerBindings] maps a combined sampler's original binding to the slot
  /// its split sampler should occupy. Supplying it takes ownership of binding
  /// assignment away from the translator, so textures keep their original
  /// numbers. An empty map lets the translator assign, which is harder to
  /// predict and only used where the mapping is not yet known.
  ///
  /// Throws [WgslTranslationException] on failure.
  String translate(
    Uint32List spirv, {
    required String shaderName,
    Map<int, int> samplerBindings = const {},
    bool allowNonUniformDerivatives = true,
    bool minify = false,
  });

  /// A short identifier for the translator build, recorded in errors and logs
  /// so a bad artifact is identifiable from a bug report.
  String get revision;
}

/// Memoizes translations so a shader is only translated once per generation.
///
/// Hot reload bumps a shader's generation, which evicts just that entry rather
/// than the whole cache.
class WgslTranslationCache {
  WgslTranslationCache(this._translator);

  final WgslTranslator _translator;
  final Map<String, ({int generation, WgslTranslation translation})> _entries =
      {};

  /// Translations currently held, for diagnostics.
  int get length => _entries.length;

  /// Returns the translation for [shaderName], translating on a miss.
  ///
  /// [resources] is the shader's bundle reflection, which determines the
  /// binding layout. [generation] invalidates the entry when it changes.
  WgslTranslation get(
    String shaderName,
    Uint32List spirv,
    List<WgslReflectedResource> resources, {
    int generation = 0,
    bool verify = true,
  }) {
    final cached = _entries[shaderName];
    if (cached != null && cached.generation == generation) {
      return cached.translation;
    }

    final bindings = WgslBindingMap.mapped(resources);
    final wgsl = _translator.translate(
      spirv,
      shaderName: shaderName,
      samplerBindings: bindings.samplerMappings,
    );

    // Cheap, and it turns a translator that changed its assignment policy into
    // a loud load-time failure rather than silently binding the wrong slot.
    if (verify) {
      try {
        bindings.verifyAgainstWgsl(wgsl, shaderName: shaderName);
      } on WgslBindingMismatch catch (e) {
        throw WgslTranslationException(shaderName, e.message);
      }
    }

    final translation = (wgsl: wgsl, bindings: bindings);
    _entries[shaderName] = (generation: generation, translation: translation);
    return translation;
  }

  /// Drops [shaderName], forcing a retranslation on the next request.
  void evict(String shaderName) => _entries.remove(shaderName);

  /// Drops everything.
  void clear() => _entries.clear();
}
