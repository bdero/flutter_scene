import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Uploads a decoded `dart:ui` [ui.Image] to a Flutter GPU texture.
///
/// The image is read as raw RGBA bytes and copied into a host-visible
/// GPU texture matching the image's dimensions. No mip chain is built, so a
/// minified texture shimmers; prefer `Texture2D.fromImage` for anything a
/// material samples, and reach for this only when a raw `gpu.Texture` is what
/// you need (building an `EnvironmentMap`, interop with a custom pipeline).
/// A material texture slot takes a `TextureSource`, so wrap the result in
/// `GpuTextureSource` to bind it.
///
/// Throws if the image can't be read as RGBA.
/// {@category Assets and loading}
Future<gpu.Texture> gpuTextureFromImage(ui.Image image) async {
  // Straight (non-premultiplied) alpha: the material shaders treat a sampled
  // texture as straight and premultiply on output, so a premultiplied source
  // (the rawRgba default) would be multiplied by alpha twice and darken every
  // partially transparent texel. Invisible for opaque images, but it crushes
  // soft-edged content (sprites, cutouts). Mirrors the widget-texture path.
  final byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
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
/// {@category Assets and loading}
Future<ui.Image> imageFromAsset(String assetPath, {AssetBundle? bundle}) async {
  // Load resource from the asset bundle. Throws exception if the asset couldn't
  // be found in the bundle.
  final buffer = await (bundle ?? rootBundle).loadBuffer(assetPath);

  // Decode the image.
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Reads the raw bytes of the asset at [assetPath] from the bundle.
Future<Uint8List> bytesFromAsset(
  String assetPath, {
  AssetBundle? bundle,
}) async {
  final data = await (bundle ?? rootBundle).load(assetPath);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Decodes an encoded image (PNG, JPEG, etc.) from raw [bytes].
///
/// Uses `dart:ui`'s built-in image codecs. When [maxWidth] is set and the
/// image is wider, it is decoded scaled down to [maxWidth] (aspect ratio
/// preserved); a narrower image is never upscaled. Throws if the bytes can't
/// be decoded as an image.
/// {@category Assets and loading}
Future<ui.Image> imageFromBytes(Uint8List bytes, {int? maxWidth}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final ui.Codec codec;
  ui.ImageDescriptor? descriptor;
  if (maxWidth == null) {
    codec = await ui.instantiateImageCodecFromBuffer(buffer);
  } else {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec(
      targetWidth: descriptor.width <= maxWidth ? null : maxWidth,
    );
  }
  final frame = await codec.getNextFrame();
  descriptor?.dispose();
  return frame.image;
}

/// Loads an image from the asset bundle at [assetPath] and uploads it as
/// a Flutter GPU texture.
///
/// The asset is decoded with [imageFromAsset] and then uploaded via
/// [gpuTextureFromImage], mipless like that path. Prefer
/// `Texture2D.fromAsset` for material textures. Throws if the asset is not
/// present in the bundle or cannot be decoded.
/// {@category Assets and loading}
Future<gpu.Texture> gpuTextureFromAsset(String assetPath) async {
  return await gpuTextureFromImage(await imageFromAsset(assetPath));
}
