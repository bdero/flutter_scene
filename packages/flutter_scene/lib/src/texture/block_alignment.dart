// The 4x4 block-size rule the compressed texture formats impose on a base
// level, shared by the two cook paths (loose images and glTF-embedded ones).
// Build-time only (it resamples with package:image); nothing here runs on
// device.

import 'package:image/image.dart' as img;

import 'package:flutter_scene/src/texture/block/universal_block.dart';

/// Whether [width] x [height] can be stored in the 4x4 block formats, which
/// reject a base level that does not fill whole blocks.
bool isBlockAligned(int width, int height) =>
    width % kBlockDim == 0 && height % kBlockDim == 0;

/// [size] rounded up to the next multiple of the block dimension.
int alignedUp(int size) => ((size + kBlockDim - 1) ~/ kBlockDim) * kBlockDim;

/// Resamples [image] up to the next block-aligned size so it can be stored
/// compressed, or returns it unchanged when it already is.
///
/// This resamples rather than padding: padding would need every UV that reads
/// the texture rescaled, which is not knowable here and breaks tiling. The
/// trade is that texel boundaries shift slightly, so it is opt-in.
img.Image resampleToBlockAlignment(img.Image image) {
  if (isBlockAligned(image.width, image.height)) return image;
  return img.copyResize(
    image,
    width: alignedUp(image.width),
    height: alignedUp(image.height),
    interpolation: img.Interpolation.cubic,
  );
}
