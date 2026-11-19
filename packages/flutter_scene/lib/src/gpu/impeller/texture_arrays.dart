part of '_gpu.dart';

// 2D-array textures arrived in Flutter GPU with Flutter 3.50, after this
// package's floor, so these reach that API by name and report no arrays on an
// older engine. Only texture creation and binding call them.
// TODO(min-flutter-3.50): call the Flutter GPU members directly once the
// minimum Flutter version is 3.50 or newer.

/// `TextureType.texture2DArray`, or null on an engine without it.
final TextureType? _texture2DArray = TextureType.values
    .where((type) => type.name == 'texture2DArray')
    .firstOrNull;

/// Whether the active context creates 2D-array textures. False on engines
/// older than Flutter 3.50, and where the backend has none.
bool get supportsTextureArrays {
  if (_texture2DArray == null) return false;
  try {
    // ignore: avoid_dynamic_calls
    return (gpuContext as dynamic).doesSupportTextureArrays as bool;
  } on NoSuchMethodError {
    return false;
  }
}

/// A [width] x [height] 2D-array texture of [layerCount] layers. Check
/// [supportsTextureArrays] first.
Texture createTexture2DArray(
  StorageMode storageMode,
  int width,
  int height,
  int layerCount, {
  PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
}) {
  final type = _texture2DArray;
  if (type == null) {
    throw UnsupportedError(
      '2D-array textures need Flutter 3.50 or newer on native platforms.',
    );
  }
  // ignore: avoid_dynamic_calls
  return (gpuContext as dynamic).createTexture(
        storageMode,
        width,
        height,
        format: format,
        textureType: type,
        enableRenderTargetUsage: false,
        layerCount: layerCount,
      )
      as Texture;
}

/// Whether [texture] is a 2D-array texture.
bool isTexture2DArray(Texture texture) =>
    _texture2DArray != null && texture.textureType == _texture2DArray;

/// The layers of a 2D-array [texture], or 1 for every other kind.
int textureLayerCount(Texture texture) {
  if (!isTexture2DArray(texture)) return 1;
  // ignore: avoid_dynamic_calls
  return (texture as dynamic).layerCount as int;
}
