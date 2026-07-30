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

/// Async shader-library loader. On native this defers to flutter_gpu's
/// `ShaderLibrary.fromAsset`; `Future.value` adopts its result whether that
/// is a `ShaderLibrary?` or a `Future<ShaderLibrary?>`. The web backend
/// implements its own async load.
Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) {
  return Future.value(ShaderLibrary.fromAsset(assetName));
}

/// Loads a shader bundle directly from [bytes].
Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes) {
  return Future.value(ShaderLibrary.fromBytes(bytes));
}

/// Async shader-bundle reinitialize. On native this wraps flutter_gpu's
/// synchronous in-place `ShaderLibrary.reinitialize`; the web backend
/// re-fetches and recompiles asynchronously, so await this before evicting
/// cached pipelines.
Future<void> reinitializeShaderLibraryAsync(String assetKey) {
  // TODO(shader-reload): drop the ignore once ShaderLibrary.reinitialize
  // reaches a released Flutter channel. The API exists only on master, so
  // analyzing against stable (which pub.dev scoring does) reports it
  // undefined; the package requires the master channel at runtime anyway.
  // ignore: undefined_method
  ShaderLibrary.reinitialize(assetKey);
  return Future.value();
}

/// Refreshes a bytes-loaded [library] in place from regenerated bundle
/// [bytes], preserving Shader identity (reflection offsets and pipeline-cache
/// keys stay valid). Returns an error description, or null on success.
Future<String?> reinitializeShaderLibraryFromBytesAsync(
  ShaderLibrary library,
  ByteData bytes,
) {
  // ignore: undefined_method
  return Future.value(library.reinitializeFromBytes(bytes));
}
