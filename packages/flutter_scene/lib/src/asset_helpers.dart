import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

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

Future<gpu.Texture> gpuTextureFromAsset(String assetPath) async {
  // Load resource from the asset bundle. Throws exception if the asset couldn't
  // be found in the bundle.
  final buffer = await rootBundle.loadBuffer(assetPath);

  // Decode the image.
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  return await gpuTextureFromImage(image);
}
