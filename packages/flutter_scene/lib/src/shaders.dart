import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

const String _kBaseShaderBundlePath =
    'packages/flutter_scene/build/shaderbundles/base.shaderbundle';

gpu.ShaderLibrary? _baseShaderLibrary;

/// The shader bundle shipped with `flutter_scene`.
///
/// Contains the vertex and fragment shaders used by the built-in
/// geometries (`UnskinnedVertex`, `SkinnedVertex`) and materials
/// (`StandardFragment`, `UnlitFragment`). Custom [Geometry] or [Material]
/// subclasses can pull additional shaders from this library.
///
/// Reading a shader bundle from an asset is asynchronous on every backend,
/// so the bundle must be loaded ahead of time by awaiting
/// [Scene.initializeStaticResources] (which calls [loadBaseShaderLibrary]);
/// accessing this getter before that completes throws.
/// {@category Assets and loading}
gpu.ShaderLibrary get baseShaderLibrary {
  final cached = _baseShaderLibrary;
  if (cached == null) {
    throw Exception(
      'The base shader bundle has not been loaded yet. Await '
      'Scene.initializeStaticResources() before constructing geometry or '
      'materials that touch the base shader library.',
    );
  }
  return cached;
}

/// Asynchronously loads and caches the base shader bundle. Idempotent.
/// Called by [Scene.initializeStaticResources] so the synchronous
/// [baseShaderLibrary] getter has a cached library to return (shader assets
/// can't be read synchronously on any backend).
/// {@category Assets and loading}
Future<void> loadBaseShaderLibrary() async {
  if (_baseShaderLibrary != null) {
    return;
  }
  final lib = await gpu.loadShaderLibraryAsync(_kBaseShaderBundlePath);
  if (lib == null) {
    throw Exception(
      "Failed to load base shader bundle! ($_kBaseShaderBundlePath)",
    );
  }
  _baseShaderLibrary = lib;
}
