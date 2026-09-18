part of '_gpu.dart';

/// Decodes [encoded] (any format the browser reads) and uploads it as an
/// RGBA8 texture, straight into this backend's own WebGL context.
///
/// The image never becomes a `ui.Image`, so nothing is read back through the
/// framework's renderer and no pixel crosses Dart memory. An image larger than
/// [maxSize], or than the context's `MAX_TEXTURE_SIZE`, is scaled down by the
/// browser, keeping its aspect ratio.
///
/// Returns null on a backend with no such path; the caller decodes through
/// `dart:ui` instead.
Future<Texture?> createTextureFromEncodedImage(
  Uint8List encoded, {
  bool mipmaps = true,
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
    // Read as a JS number: under dart2wasm the value is not a Dart `num`.
    final JSAny? reported = gl.getParameter(
      web.WebGL2RenderingContext.MAX_TEXTURE_SIZE,
    );
    var limit = reported.isA<JSNumber>()
        ? (reported as JSNumber).toDartInt
        : 2048;
    if (maxSize != null && maxSize < limit) limit = maxSize;

    final longest = bitmap.width > bitmap.height ? bitmap.width : bitmap.height;
    if (longest > limit) {
      final scaled = await web.window
          .createImageBitmap(
            bitmap,
            options(
              width: (bitmap.width * limit ~/ longest).clamp(1, limit),
              height: (bitmap.height * limit ~/ longest).clamp(1, limit),
            ),
          )
          .toDart;
      bitmap.close();
      bitmap = scaled;
    }

    final width = bitmap.width;
    final height = bitmap.height;
    final texture = context.createTexture(
      StorageMode.hostVisible,
      width,
      height,
      mipLevelCount: mipmaps ? Texture.fullMipCount(width, height) : 1,
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
    if (texture.mipLevelCount > 1) gl.generateMipmap(texture.glTarget);
    return texture;
  } finally {
    bitmap.close();
  }
}
