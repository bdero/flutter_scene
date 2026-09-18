part of '_gpu.dart';

Future<ui.Image> presentTextureAsImage(
  Texture texture, {
  bool transferOwnership = false,
}) => _stub();


/// The web backend uploads an encoded image straight into its own context;
/// this backend has no such path, and the caller decodes through `dart:ui`.
Future<Texture?> createTextureFromEncodedImage(
  Uint8List encoded, {
  bool mipmaps = true,
  int? maxSize,
}) async => null;
