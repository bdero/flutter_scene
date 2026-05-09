import 'package:flutter_gpu/gpu.dart' as gpu;

const String _kBaseShaderBundlePath =
    'packages/flutter_scene/build/shaderbundles/base.shaderbundle';

gpu.ShaderLibrary? _baseShaderLibrary;
gpu.ShaderLibrary get baseShaderLibrary {
  if (_baseShaderLibrary != null) {
    return _baseShaderLibrary!;
  }
  _baseShaderLibrary = gpu.ShaderLibrary.fromAsset(_kBaseShaderBundlePath);
  if (_baseShaderLibrary != null) {
    return _baseShaderLibrary!;
  }

  throw Exception(
    "Failed to load base shader bundle! ($_kBaseShaderBundlePath)",
  );
}
