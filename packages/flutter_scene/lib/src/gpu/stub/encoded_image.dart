part of '_gpu.dart';

/// The web backend decodes and uploads an encoded image in its own context;
/// this backend has no such path, so the caller decodes through `dart:ui`.
Future<Texture?> createTextureFromEncodedImage(
  Uint8List encoded, {
  MipContent content = MipContent.color,
  bool mipmaps = true,
  int? maxMipLevels,
  int? maxSize,
}) async => null;
