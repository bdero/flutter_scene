part of '_gpu.dart';

/// Bridge helper to display an offscreen-rendered Texture in a Flutter
/// widget. Web-only at runtime; throws on Impeller (native) targets
/// because flutter_gpu's `Texture.asImage()` is the standard path there.
Future<ui.Image> presentTextureAsImage(
  Texture texture, {
  bool transferOwnership = false,
}) {
  throw UnimplementedError(
    'presentTextureAsImage is only implemented on web. On native, use '
    'Texture.asImage().',
  );
}


/// The web backend uploads an encoded image straight into its own context;
/// this backend has no such path, and the caller decodes through `dart:ui`.
Future<Texture?> createTextureFromEncodedImage(
  Uint8List encoded, {
  bool mipmaps = true,
  int? maxSize,
}) async => null;
