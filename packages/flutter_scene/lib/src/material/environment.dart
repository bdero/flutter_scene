import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/material/material.dart';

/// A pair of textures used for image-based lighting.
///
/// The radiance texture supplies high-frequency reflections (used for
/// specular sampling), while the optional irradiance texture supplies
/// low-frequency ambient lighting (used for diffuse). Both textures are
/// currently expected to be equirectangular maps; cubemap support will
/// land once Flutter GPU exposes cubemaps.
///
/// Use [EnvironmentMap.fromAssets] or [EnvironmentMap.fromUIImages] to
/// construct one from images, [EnvironmentMap.fromGpuTextures] when you
/// already hold GPU textures, or [EnvironmentMap.empty] for a no-op
/// placeholder.
base class EnvironmentMap {
  EnvironmentMap._(this._radianceTexture, this._irradianceTexture);

  /// Creates an empty environment map. Both [radianceTexture] and
  /// [irradianceTexture] return a white placeholder, contributing no
  /// directional lighting.
  factory EnvironmentMap.empty() {
    return EnvironmentMap._(null, null);
  }

  /// Wraps already-uploaded GPU textures.
  ///
  /// [irradianceTexture] is optional; when omitted, irradiance sampling
  /// falls back to a white placeholder.
  factory EnvironmentMap.fromGpuTextures({
    required gpu.Texture radianceTexture,
    gpu.Texture? irradianceTexture,
  }) {
    return EnvironmentMap._(radianceTexture, irradianceTexture);
  }

  /// Builds an [EnvironmentMap] from already-decoded `dart:ui` images,
  /// uploading them to GPU textures.
  static Future<EnvironmentMap> fromUIImages({
    required ui.Image radianceImage,
    ui.Image? irradianceImage,
  }) async {
    final radianceTexture = await gpuTextureFromImage(radianceImage);
    gpu.Texture? irradianceTexture;

    if (irradianceImage != null) {
      irradianceTexture = await gpuTextureFromImage(irradianceImage);
    }

    return EnvironmentMap.fromGpuTextures(
      radianceTexture: radianceTexture,
      irradianceTexture: irradianceTexture,
    );
  }

  /// Loads an [EnvironmentMap] from the asset bundle.
  ///
  /// [radianceImagePath] is required; [irradianceImagePath] is optional
  /// and falls back to a white placeholder when omitted.
  static Future<EnvironmentMap> fromAssets({
    required String radianceImagePath,
    String? irradianceImagePath,
  }) async {
    final radianceTexture = await gpuTextureFromAsset(radianceImagePath);
    gpu.Texture? irradianceTexture;

    if (irradianceImagePath != null) {
      irradianceTexture = await gpuTextureFromAsset(irradianceImagePath);
    }

    return EnvironmentMap.fromGpuTextures(
      radianceTexture: radianceTexture,
      irradianceTexture: irradianceTexture,
    );
  }

  /// Whether this environment map has no radiance texture.
  ///
  /// An empty environment contributes no IBL; the [Scene] swaps it for
  /// the package's bundled default at draw time.
  bool isEmpty() => _radianceTexture == null;

  gpu.Texture? _radianceTexture;
  gpu.Texture? _irradianceTexture;

  // TODO(bdero): Once cubemaps are supported, change this to be an environment cubemap. (Cubemaps are missing from Flutter GPU at the time of writing: https://github.com/flutter/flutter/issues/145027)
  /// Represents the light being emitted by the environment from any direction.
  ///
  /// Currently expected to be an equirectangular map.
  gpu.Texture get radianceTexture =>
      Material.whitePlaceholder(_radianceTexture);

  // TODO(bdero): Once cubemaps are supported, change this to be an environment cubemap. (Cubemaps are missing from Flutter GPU at the time of writing: https://github.com/flutter/flutter/issues/145027)
  // TODO(bdero): Generate Gaussian blurred mipmaps for this texture for accurate roughness sampling.
  /// The integral of all light being received by a given surface at any direction.
  ///
  /// Currently expected to be an equirectangular map.
  gpu.Texture get irradianceTexture =>
      Material.whitePlaceholder(_irradianceTexture);
}

/// Shared material rendering properties.
///
/// A default environment can be set on the [Scene], which is automatically
/// applied to all materials. Individual [Material]s may optionally override the
/// default environment.
base class Environment {
  /// Creates an [Environment] with the given image-based-lighting map
  /// and shared tone-mapping parameters.
  ///
  /// All parameters are optional; the defaults pair an empty
  /// [EnvironmentMap] with `intensity = 1.0` and `exposure = 2.0`.
  Environment({
    EnvironmentMap? environmentMap,
    this.intensity = 1.0,
    this.exposure = 2.0,
  }) : environmentMap = environmentMap ?? EnvironmentMap.empty();

  /// Returns a copy of this environment with a different
  /// [environmentMap], preserving [intensity] and [exposure].
  Environment withNewEnvironmentMap(EnvironmentMap environmentMap) {
    return Environment(
      environmentMap: environmentMap,
      intensity: intensity,
      exposure: exposure,
    );
  }

  /// The environment map to use for image-based-lighting.
  ///
  /// This must be an equirectangular map.
  EnvironmentMap environmentMap;

  /// The intensity of the environment map.
  double intensity;

  /// The exposure level used for tone mapping.
  double exposure;
}
