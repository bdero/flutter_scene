import 'package:flutter_gpu/gpu.dart' as gpu;

/// Shared material rendering properties.
///
/// A default environment can be set on the [Scene], which is automatically
/// applied to all materials. Individual [Material]s may optionally override the
/// default environment.
base class Environment {
  Environment({this.texture, this.intensity = 1.0, this.exposure = 1.0});

  // TODO(bdero): Support environment cubemaps. (Cubemaps are missing from Flutter GPU at the time of writing: https://github.com/flutter/flutter/issues/145027)
  /// The environment map to use for image-based-lighting.
  ///
  /// This must be an equirectangular map.
  gpu.Texture? texture;

  /// The intensity of the environment map.
  double intensity;

  /// The exposure level used for tone mapping.
  double exposure;
}
