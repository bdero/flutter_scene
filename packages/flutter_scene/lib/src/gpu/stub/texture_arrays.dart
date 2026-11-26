part of '_gpu.dart';

/// Whether the active context creates 2D-array textures.
bool get supportsTextureArrays => _stub();

/// A [width] x [height] 2D-array texture of [layerCount] layers.
Texture createTexture2DArray(
  StorageMode storageMode,
  int width,
  int height,
  int layerCount, {
  PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
}) => _stub();

/// Whether [texture] is a 2D-array texture.
bool isTexture2DArray(Texture texture) => _stub();

/// The layers of a 2D-array [texture], or 1 for every other kind.
int textureLayerCount(Texture texture) => _stub();
