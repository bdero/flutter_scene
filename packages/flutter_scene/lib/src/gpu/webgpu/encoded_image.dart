part of 'webgpu_backend.dart';

/// Decodes an encoded image with the browser and uploads it as an RGBA8
/// texture, building its mip chain on the GPU. Mirrors the WebGL2 path: no
/// premultiplication, no color-space conversion, and the image scaled down
/// to fit [maxSize] and the device limit.
Future<Texture?> _createTextureFromEncodedImage(
  _WebGpuContext context,
  Uint8List encoded, {
  required MipContent content,
  required bool mipmaps,
  int? maxMipLevels,
  int? maxSize,
}) async {
  web.ImageBitmapOptions options({int? width, int? height}) {
    final result = web.ImageBitmapOptions(
      premultiplyAlpha: 'none',
      colorSpaceConversion: 'none',
    );
    if (width != null && height != null) {
      result
        ..resizeWidth = width
        ..resizeHeight = height
        ..resizeQuality = 'high';
    }
    return result;
  }

  var bitmap = await web.window
      .createImageBitmap(web.Blob(<JSAny>[encoded.toJS].toJS), options())
      .toDart;
  try {
    var limit = context.maxTextureSize;
    if (maxSize != null && maxSize < limit) limit = maxSize;
    final (fitWidth, fitHeight) = fitWithin(bitmap.width, bitmap.height, limit);
    if (fitWidth != bitmap.width || fitHeight != bitmap.height) {
      final scaled = await web.window
          .createImageBitmap(
            bitmap,
            options(width: fitWidth, height: fitHeight),
          )
          .toDart;
      bitmap.close();
      bitmap = scaled;
    }
    final width = bitmap.width;
    final height = bitmap.height;
    var levels = mipmaps ? Texture.fullMipCount(width, height) : 1;
    if (maxMipLevels != null && maxMipLevels >= 1 && maxMipLevels < levels) {
      levels = maxMipLevels;
    }
    final texture =
        context.createTexture(
              StorageMode.hostVisible,
              width,
              height,
              mipLevelCount: levels,
            )
            as _WebGpuTexture;
    context.device.device.queue.copyExternalImageToTexture(
      _obj({'source': bitmap}),
      _obj({
        'texture': texture.texture,
        'mipLevel': 0,
        'premultipliedAlpha': false,
      }),
      _arr([width, height]),
    );
    context.mipGenerator.generate(texture, content);
    return texture;
  } finally {
    bitmap.close();
  }
}
