part of '_gpu.dart';

/// A collection of pre-compiled shaders. Mirrors flutter_gpu's API for the
/// bundle-loading path, and adds a web-only `fromInlineMap` factory for
/// tests that don't want to ship a `.shaderbundle`.
base class ShaderLibrary {
  ShaderLibrary._(this._shaders);

  final Map<String, Shader> _shaders;

  /// Look up a compiled shader by the name it was given in the bundle (or
  /// in the inline map).
  Shader? operator [](String name) => _shaders[name];

  /// Web-only addition. Compile an inline map of GLSL ES 1.00 sources for
  /// quick smoke-test pipelines. Each entry's source is run through
  /// `transpileGlslEs100To300` before compilation. Reflection metadata
  /// (uniform structs, vertex inputs) is **not** populated, so the
  /// resulting shaders are only usable with pipelines that don't need
  /// reflection-driven binding.
  static ShaderLibrary fromInlineMap(
    Map<String, ({String source, ShaderStage stage})> shaders,
  ) {
    final compiled = <String, Shader>{};
    shaders.forEach((name, entry) {
      final s = Shader._(gpuContext, entry.stage);
      final transpiled = transpileGlslEs100To300(
        entry.source,
        isFragment: entry.stage == ShaderStage.fragment,
      );
      s._compile(transpiled);
      compiled[name] = s;
    });
    return ShaderLibrary._(compiled);
  }

  /// Load a `.shaderbundle` asset. Not implemented for Phase 1 - the
  /// bundle parser lives in the smoke test today and will move into the
  /// shim in a later phase.
  static Future<ShaderLibrary?> fromAsset(String assetName) {
    throw UnimplementedError(
      'ShaderLibrary.fromAsset is not implemented yet on web. Use '
      'ShaderLibrary.fromInlineMap for smoke tests, or wait for the bundle '
      'parser to land in the shim.',
    );
  }
}

/// Top-level helper matching flutter_gpu's API.
Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) {
  return ShaderLibrary.fromAsset(assetName);
}

/// Compile a map of inline GLSL ES 1.00 sources into a ShaderLibrary.
/// Web-specific; on native targets this throws.
ShaderLibrary compileShaderLibraryInline(
  Map<String, ({String source, ShaderStage stage})> shaders,
) => ShaderLibrary.fromInlineMap(shaders);
