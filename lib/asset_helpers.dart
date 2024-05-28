import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

Future<gpu.Texture> gpuTextureFromAsset(String assetPath) async {
  // Load resource from the asset bundle. Throws exception if the asset couldn't
  // be found in the bundle.

  final buffer = await rootBundle.loadBuffer(assetPath);

  // Decode the image.

  final codec = await instantiateImageCodecFromBuffer(buffer);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw Exception('Failed to get RGBA data from image.');
  }

  // Upload the RGBA image to a Flutter GPU texture.

  final texture = gpu.gpuContext
      .createTexture(gpu.StorageMode.hostVisible, image.width, image.height);
  if (texture == null) {
    throw Exception('Failed to create Flutter GPU texture.');
  }
  if (!texture.overwrite(byteData)) {
    throw Exception('Failed to overwrite Flutter GPU texture data.');
  }

  return texture;
}
