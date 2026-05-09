import 'package:flutter_gpu/gpu.dart' as gpu;

const String _kBaseShaderBundlePath =
    'packages/flutter_scene/build/shaderbundles/base.shaderbundle';

gpu.ShaderLibrary? _baseShaderLibrary;

/// The shader bundle shipped with `flutter_scene`, lazily loaded on first
/// access.
///
/// Contains the vertex and fragment shaders used by the built-in
/// geometries (`UnskinnedVertex`, `SkinnedVertex`) and materials
/// (`StandardFragment`, `UnlitFragment`). Custom [Geometry] or [Material]
/// subclasses can pull additional shaders from this library.
///
/// Throws if the bundled shader asset cannot be loaded.
gpu.ShaderLibrary get baseShaderLibrary {
  if (_baseShaderLibrary != null) {
    return _baseShaderLibrary!;
  }
  _baseShaderLibrary = gpu.ShaderLibrary.fromAsset(_kBaseShaderBundlePath);
  if (_baseShaderLibrary != null) {
    return _baseShaderLibrary!;
  }

  throw Exception(
    "Failed to load base shader bundle! ($_kBaseShaderBundlePath)",
  );
}
