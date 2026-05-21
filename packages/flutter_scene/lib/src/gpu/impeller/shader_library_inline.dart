part of '_gpu.dart';

/// Compile a small map of inline GLSL ES 1.00 sources into a ShaderLibrary.
/// Web-only at runtime; throws on Impeller (native) targets because
/// flutter_gpu doesn't expose a way to construct a `Shader` from raw GLSL
/// on native platforms. Bundle-shipped shaders (`ShaderLibrary.fromAsset`)
/// are the supported path on native.
ShaderLibrary compileShaderLibraryInline(
  Map<String, ({String source, ShaderStage stage})> shaders,
) {
  throw UnimplementedError(
    'compileShaderLibraryInline is only implemented on web. On native '
    'targets, load shaders via gpu.ShaderLibrary.fromAsset.',
  );
}

/// Async shader-library loader. On native this just wraps flutter_gpu's
/// synchronous `ShaderLibrary.fromAsset`; the web backend implements a
/// genuinely async load.
Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) {
  return Future.value(ShaderLibrary.fromAsset(assetName));
}
