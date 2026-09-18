import 'dart:typed_data';
import 'dart:ui' as ui;

import '../gpu/gpu.dart' as gpu;
import '../render/mip_sampling_probe.dart';
import 'mipmap.dart';

/// Uploads an encoded image (PNG, JPEG, and whatever else the platform reads)
/// through the backend's own decoder where it has one, or returns null so
/// the caller decodes with the platform codec and uploads the pixels itself.
///
/// The web backend has one. Its browser decodes off the main thread and its
/// mip chain is built on the GPU, so no pixel crosses Dart memory and nothing
/// is read back through the framework's renderer, which clips large images
/// and corrupts a read-back that overlaps a frame.
Future<gpu.Texture?> gpuTextureFromEncodedBytes(
  Uint8List bytes, {
  TextureContent content = TextureContent.color,
  bool mipmaps = true,
  int? maxMipmapLevels,
  int? maxSize,
}) {
  return gpu.createTextureFromEncodedImage(
    bytes,
    content: switch (content) {
      TextureContent.color => gpu.MipContent.color,
      TextureContent.data => gpu.MipContent.data,
      TextureContent.normal => gpu.MipContent.normal,
    },
    mipmaps: mipmaps && mipChainsAreSampled,
    maxMipLevels: maxMipmapLevels,
    maxSize: maxSize,
  );
}

/// Decodes [bytes] with the platform codec. When [maxSize] is given, a larger
/// image is scaled down as it decodes so its longest side fits, keeping the
/// aspect ratio; its full-size pixels are never held.
Future<ui.Image> decodeEncodedImage(Uint8List bytes, {int? maxSize}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      if (maxSize == null) {
        return ui.TargetImageSize(width: width, height: height);
      }
      final (fitWidth, fitHeight) = gpu.fitWithin(width, height, maxSize);
      return ui.TargetImageSize(width: fitWidth, height: fitHeight);
    },
  );
  final frame = await codec.getNextFrame();
  return frame.image;
}
