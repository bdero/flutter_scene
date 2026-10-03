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

/// Uniform blocks one binding packed from floats itself.
///
/// The next pack of the same size reuses its block in place, so a block
/// refreshed every frame stops allocating. A block stops being reused once a
/// caller supplies its own or reads it back, since others may then hold it.
class PackedFloatBlocks {
  final Map<String, ByteData> _owned = {};

  /// Packs [floats] for [name], into this binding's own block when [current]
  /// (the block now bound under [name]) is still it.
  ByteData pack(String name, ByteData? current, List<double> floats) {
    final length = floats.length * 4;
    final owned = _owned[name];
    final bytes =
        owned != null &&
            identical(owned, current) &&
            owned.lengthInBytes == length
        ? owned
        : _owned[name] = ByteData(length);
    for (var i = 0; i < floats.length; i++) {
      bytes.setFloat32(i * 4, floats[i], Endian.host);
    }
    return bytes;
  }

  /// Stops reusing [name]'s block.
  void release(String name) => _owned.remove(name);
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
  final PackedFloatBlocks _packed = PackedFloatBlocks();

  void setUniformBlock(String name, ByteData? bytes) {
    _packed.release(name);
    if (bytes == null) {
      _uniformBlocks.remove(name);
    } else {
      _uniformBlocks[name] = bytes;
    }
  }

  void setUniformBlockFromFloats(String name, List<double> floats) {
    _uniformBlocks[name] = _packed.pack(name, _uniformBlocks[name], floats);
  }

  ByteData? getUniformBlock(String name) {
    _packed.release(name);
    return _uniformBlocks[name];
  }

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
