import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Stores caller-supplied uniform blocks and textures keyed by name and
/// binds them to a render pass against a shader's reflection.
///
/// Used by the custom-shader surfaces (a [PostEffect], and a candidate for
/// `ShaderMaterial`) so they pack and bind uniforms the same way. The
/// block bytes must already follow the shader's std140 layout.
class ShaderUniformBindings {
  final Map<String, ByteData> _uniformBlocks = {};
  final Map<String, _BoundTexture> _textures = {};

  void setUniformBlock(String name, ByteData? bytes) {
    if (bytes == null) {
      _uniformBlocks.remove(name);
    } else {
      _uniformBlocks[name] = bytes;
    }
  }

  void setUniformBlockFromFloats(String name, List<double> floats) {
    setUniformBlock(name, ByteData.sublistView(Float32List.fromList(floats)));
  }

  ByteData? getUniformBlock(String name) => _uniformBlocks[name];

  Iterable<String> get uniformBlockNames => _uniformBlocks.keys;

  void setTexture(
    String name,
    gpu.Texture? texture, {
    gpu.SamplerOptions? sampler,
  }) {
    if (texture == null) {
      _textures.remove(name);
    } else {
      _textures[name] = _BoundTexture(texture, sampler);
    }
  }

  gpu.Texture? getTexture(String name) => _textures[name]?.texture;

  Iterable<String> get textureNames => _textures.keys;

  /// Binds every stored block and texture to [pass], resolving slots
  /// against [shader] and emplacing block bytes into [transientsBuffer].
  void bind(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {
    for (final entry in _uniformBlocks.entries) {
      pass.bindUniform(
        shader.getUniformSlot(entry.key),
        transientsBuffer.emplace(entry.value),
      );
    }
    for (final entry in _textures.entries) {
      pass.bindTexture(
        shader.getUniformSlot(entry.key),
        entry.value.texture,
        sampler: entry.value.sampler ?? gpu.SamplerOptions(),
      );
    }
  }
}

class _BoundTexture {
  _BoundTexture(this.texture, this.sampler);
  final gpu.Texture texture;
  final gpu.SamplerOptions? sampler;
}
