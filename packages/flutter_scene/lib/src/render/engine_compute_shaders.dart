import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/shader_interface.dart'
    show markEngineShaderLibrary;

/// The engine's compute shaders (`shaders/compute.shaderbundle.json`), loaded
/// on first request and only where the device supports compute, so a device
/// without it never reads the bundle.
abstract final class EngineComputeShaders {
  static gpu.ShaderLibrary? _library;
  static Future<void>? _loading;
  static bool _failed = false;

  /// The library once it has loaded, starting the load on the first call.
  /// Null on a device without compute, while loading, and after a failure,
  /// which is reported once. A caller falls back to its non-compute path
  /// whenever this is null.
  static gpu.ShaderLibrary? request() {
    if (_failed || !gpu.supportsCompute) return null;
    final library = _library;
    if (library != null) return library;
    _loading ??= _load().then<void>(
      (loaded) => _library = loaded,
      onError: (Object error, StackTrace stack) {
        _failed = true;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_scene',
            context: ErrorDescription(
              'while loading the compute shaders. Features that use them fall '
              'back to their non-compute paths',
            ),
          ),
        );
      },
    );
    return null;
  }

  /// Waits for the load [request] starts. Completes at once on a device
  /// without compute.
  static Future<void> whenLoaded() async {
    request();
    await _loading;
  }

  static Future<gpu.ShaderLibrary> _load() async {
    final key = (await loadGeneratedAssetIndex()).resolveFirstKey(
      GeneratedAssetFamily.shaderBundle,
      'compute',
      package: 'flutter_scene',
    );
    if (key == null) {
      throw StateError(
        'The engine compute shader bundle is missing. flutter_scene\'s build '
        'hook compiles it with the base bundle, so rebuild the app.',
      );
    }
    final library = await gpu.loadShaderLibraryAsync(key);
    if (library == null) {
      throw StateError(
        'Could not load the engine compute shaders from "$key". They are '
        'compiled for the engine that built the app, so rebuild after '
        'changing Flutter versions.',
      );
    }
    markEngineShaderLibrary(library);
    return library;
  }

  /// Forgets the library and any failure, so a test can drive the load from a
  /// known state.
  @visibleForTesting
  static void debugReset() {
    _library = null;
    _loading = null;
    _failed = false;
  }
}
