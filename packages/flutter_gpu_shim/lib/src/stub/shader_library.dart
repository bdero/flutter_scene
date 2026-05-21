part of '_gpu.dart';

base class ShaderLibrary {
  ShaderLibrary._();
  static ShaderLibrary? fromAsset(String assetName) => _stub();
  Shader? operator [](String shaderName) => _stub();
}

Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) =>
    Future.value(ShaderLibrary.fromAsset(assetName));
