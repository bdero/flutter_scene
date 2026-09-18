part of '_gpu.dart';

/// Decodes [encoded] (any format the browser reads) and uploads it as an
/// RGBA8 texture straight into this backend's own WebGL context, building
/// the mip chain on the GPU.
///
/// The image never becomes a `ui.Image`, so nothing is read back through the
/// framework's renderer and no pixel crosses Dart memory. An image larger
/// than [maxSize], or than the context's `MAX_TEXTURE_SIZE`, is scaled down
/// by the browser as it decodes, keeping its aspect ratio. [mipmaps] false
/// uploads the base level only; [maxMipLevels] caps the chain.
///
/// Every backend exposes this entry point; one with no such path returns
/// null and the caller decodes through `dart:ui` instead.
Future<Texture?> createTextureFromEncodedImage(
  Uint8List encoded, {
  MipContent content = MipContent.color,
  bool mipmaps = true,
  int? maxMipLevels,
  int? maxSize,
}) async {
  final context = gpuContext;
  final gl = context._gl;

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
    var limit = context._maxTextureSize;
    if (maxSize != null && (limit == null || maxSize < limit)) limit = maxSize;
    if (limit != null) {
      final (width, height) = fitWithin(bitmap.width, bitmap.height, limit);
      if (width != bitmap.width || height != bitmap.height) {
        final scaled = await web.window
            .createImageBitmap(bitmap, options(width: width, height: height))
            .toDart;
        bitmap.close();
        bitmap = scaled;
      }
    }

    final width = bitmap.width;
    final height = bitmap.height;
    var levels = mipmaps ? Texture.fullMipCount(width, height) : 1;
    if (maxMipLevels != null && maxMipLevels >= 1 && maxMipLevels < levels) {
      levels = maxMipLevels;
    }
    final texture = context.createTexture(
      StorageMode.hostVisible,
      width,
      height,
      mipLevelCount: levels,
    );
    context._bindTextureForSetup(texture.glTarget, texture._texture);
    gl.texSubImage2D(
      texture.glTarget,
      0,
      0,
      0,
      width.toJS,
      height.toJS,
      web.WebGL2RenderingContext.RGBA.toJS,
      web.WebGL2RenderingContext.UNSIGNED_BYTE,
      bitmap,
    );
    context._mipGenerator.generate(texture, content);
    return texture;
  } finally {
    bitmap.close();
  }
}
