// The GPU half of noise baking, uploads bakeNoisePixels output as a
// texture.

import 'package:flutter_scene/src/noise/fast_noise_lite.dart';
import 'package:flutter_scene/src/noise/noise_pixels.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

/// Bakes [noise] into a grayscale [Texture2D], ready to bind as a material
/// sampler.
///
/// A convenience over [bakeNoisePixels] plus [Texture2D.fromPixels]; must
/// run where GPU resources may be created (the raster thread). Content is
/// linear data, so mipmaps (when [sampling] enables them) average directly.
/// {@category Noise}
Texture2D bakeNoiseTexture(
  FastNoiseLite noise, {
  required int width,
  required int height,
  double originX = 0.0,
  double originY = 0.0,
  double cellSize = 1.0,
  TextureSampling sampling = const TextureSampling(),
}) {
  return Texture2D.fromPixels(
    bakeNoisePixels(
      noise,
      width: width,
      height: height,
      originX: originX,
      originY: originY,
      cellSize: cellSize,
    ),
    width,
    height,
    content: TextureContent.data,
    sampling: sampling,
  );
}
