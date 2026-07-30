part of '_gpu.dart';

base class ShaderLibrary {
  ShaderLibrary._();
  static ShaderLibrary? fromAsset(String assetName) => _stub();
  static void reinitialize(String assetKey) => _stub();
  Shader? operator [](String shaderName) => _stub();
}

Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) =>
    Future.value(ShaderLibrary.fromAsset(assetName));

Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes) =>
    _stub();

Future<void> reinitializeShaderLibraryAsync(String assetKey) => _stub();

Future<String?> reinitializeShaderLibraryFromBytesAsync(
  ShaderLibrary library,
  ByteData bytes,
) => _stub();
