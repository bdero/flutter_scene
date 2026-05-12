import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Uploads a decoded `dart:ui` [ui.Image] to a Flutter GPU texture.
///
/// The image is read as raw RGBA bytes and copied into a host-visible
/// GPU texture matching the image's dimensions. The returned texture is
/// suitable for binding to materials such as [UnlitMaterial.baseColorTexture]
/// or [PhysicallyBasedMaterial.baseColorTexture], or for building an
/// [EnvironmentMap].
///
/// Throws if the image can't be read as RGBA.
Future<gpu.Texture> gpuTextureFromImage(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw Exception('Failed to get RGBA data from image.');
  }

  // Upload the RGBA image to a Flutter GPU texture.
  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    image.width,
    image.height,
  );
  texture.overwrite(byteData);

  return texture;
}

/// Loads and decodes an image from the asset bundle at [assetPath].
///
/// Uses `dart:ui`'s built-in image codecs (PNG, JPEG, etc.). Throws if
/// the asset is not present in the bundle or cannot be decoded.
Future<ui.Image> imageFromAsset(String assetPath) async {
  // Load resource from the asset bundle. Throws exception if the asset couldn't
  // be found in the bundle.
  final buffer = await rootBundle.loadBuffer(assetPath);

  // Decode the image.
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Loads an image from the asset bundle at [assetPath] and uploads it as
/// a Flutter GPU texture.
///
/// The asset is decoded with [imageFromAsset] and then uploaded via
/// [gpuTextureFromImage]. Throws if the asset is not present in the
/// bundle or cannot be decoded.
Future<gpu.Texture> gpuTextureFromAsset(String assetPath) async {
  return await gpuTextureFromImage(await imageFromAsset(assetPath));
}
