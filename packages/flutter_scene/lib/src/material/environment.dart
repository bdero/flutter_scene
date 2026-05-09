import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/material/material.dart';

base class EnvironmentMap {
  EnvironmentMap._(this._radianceTexture, this._irradianceTexture);

  factory EnvironmentMap.empty() {
    return EnvironmentMap._(null, null);
  }

  factory EnvironmentMap.fromGpuTextures({
    required gpu.Texture radianceTexture,
    gpu.Texture? irradianceTexture,
  }) {
    return EnvironmentMap._(radianceTexture, irradianceTexture);
  }

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
  Environment({
    EnvironmentMap? environmentMap,
    this.intensity = 1.0,
    this.exposure = 2.0,
  }) : environmentMap = environmentMap ?? EnvironmentMap.empty();

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
