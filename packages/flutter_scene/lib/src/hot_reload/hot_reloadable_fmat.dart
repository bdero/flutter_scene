import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// An `.fmat`-backed runtime object (a surface material or a sky) that can
/// refresh itself in place from a regenerated shader and sidecar during hot
/// reload. Implemented by `PreprocessedMaterial` and `PreprocessedSky`; the
/// `HotReloadCoordinator` tracks instances through this interface.
abstract interface class HotReloadableFmat {
  /// The current fragment shader. Its Dart identity is preserved across a
  /// shader-library reinitialize, so reflection offsets stay valid.
  gpu.Shader get fragmentShader;

  /// Re-reads render state and parameters from a regenerated [fragmentShader]
  /// and sidecar [metadata] in place, preserving explicitly-set parameter
  /// values.
  void updateFromMetadata(
    gpu.Shader fragmentShader,
    Map<String, Object?> metadata,
  );
}
