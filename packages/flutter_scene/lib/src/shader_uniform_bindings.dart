import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';

/// Sampler options for a texture bound with none given. Shared rather than
/// allocated per bind; never mutate it.
final gpu.SamplerOptions defaultSamplerOptions = gpu.SamplerOptions();

/// Linear, clamp-to-edge sampling (the BRDF LUT's). Shared; never mutate it.
final gpu.SamplerOptions linearClampSamplerOptions = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

final Expando<bool> _packedFloatBlocks = Expando('packed float blocks');

/// Packs [floats] into a uniform block, reusing [previous] when an earlier
/// call made it at the same size, so a block refreshed every frame stops
/// allocating. Never writes into a block the caller supplied.
ByteData packUniformFloats(ByteData? previous, List<double> floats) {
  final length = floats.length * 4;
  final reuse =
      previous != null &&
      previous.lengthInBytes == length &&
      _packedFloatBlocks[previous] == true;
  final bytes = reuse ? previous : ByteData(length);
  for (var i = 0; i < floats.length; i++) {
    bytes.setFloat32(i * 4, floats[i], Endian.host);
  }
  if (!reuse) _packedFloatBlocks[bytes] = true;
  return bytes;
}

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
    setUniformBlock(name, packUniformFloats(_uniformBlocks[name], floats));
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
    // Keys and a lookup, since iterating `entries` allocates a MapEntry each.
    for (final name in _uniformBlocks.keys) {
      pass.bindUniform(
        shader.cachedUniformSlot(name),
        transientsBuffer.emplace(_uniformBlocks[name]!),
      );
    }
    for (final name in _textures.keys) {
      final bound = _textures[name]!;
      pass.bindTexture(
        shader.cachedUniformSlot(name),
        bound.texture,
        sampler: bound.sampler ?? defaultSamplerOptions,
      );
    }
  }
}

class _BoundTexture {
  _BoundTexture(this.texture, this.sampler);
  final gpu.Texture texture;
  final gpu.SamplerOptions? sampler;
}
