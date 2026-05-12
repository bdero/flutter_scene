import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';

/// A [Material] backed by a caller-supplied fragment shader.
///
/// `ShaderMaterial` is the foundation for writing custom materials in
/// flutter_scene. Use it when [UnlitMaterial] and
/// [PhysicallyBasedMaterial] don't cover what you need: stylized
/// shading, custom alpha modes, screen-space effects, vertex-painted
/// looks, and so on.
///
/// ## Authoring a custom material
///
/// 1. Write a fragment shader. It should consume the engine's
///    standard vertex outputs and declare its own uniform blocks /
///    samplers for any parameters. See `MATERIALS.md` for the full
///    contract.
/// 2. Compile the shader through the `flutter_gpu_shaders` build
///    hook into a `.shaderbundle` packaged with your app.
/// 3. Load the bundle at runtime with
///    `gpu.ShaderLibrary.fromAsset('path/to/your.shaderbundle')` and
///    pull out the fragment shader entry.
/// 4. Construct a `ShaderMaterial` pointing at the shader, populate
///    its uniform blocks and textures by name, and attach it to a
///    [MeshPrimitive].
///
/// ## Engine-bound resources available to your fragment shader
///
/// These vertex outputs are written by the engine's standard vertex
/// shader and are always available as `in` declarations in your
/// fragment shader (the names are part of the engine contract):
///
/// ```glsl
/// in vec3 v_position;        // world space
/// in vec3 v_normal;          // world space (not necessarily unit)
/// in vec3 v_viewvector;      // camera_position - vertex_position, world space
/// in vec2 v_texture_coords;
/// in vec4 v_color;           // per-vertex color, white when absent
/// ```
///
/// Setting [useEnvironment] to `true` makes the engine bind the
/// active [Environment]'s IBL textures by their standard names when
/// your fragment shader declares them: `radiance_texture`,
/// `irradiance_texture`, and `brdf_lut` (all as `sampler2D`). Useful
/// when your custom shader still wants the engine's image-based
/// lighting.
///
/// ## Uniform block packing
///
/// Flutter GPU resolves uniform blocks by name (via
/// [gpu.Shader.getUniformSlot]) but the block's contents are a flat
/// byte buffer that your code packs and the GPU interprets according
/// to the shader's std140 layout. Common rules:
///
/// * `float`, `int`, `bool` occupy 4 bytes.
/// * `vec2` occupies 8 bytes aligned to 8.
/// * `vec3`, `vec4` occupy 16 bytes aligned to 16.
/// * `mat4` occupies 64 bytes; `mat3` occupies 48 bytes laid out as
///   three `vec4` columns (12 bytes of padding).
/// * Array elements stride to the next 16 bytes.
///
/// Put a `Float32List` together that matches the block's declared
/// member order (including padding) and pass it via
/// [setUniformBlock].
///
/// TODO(https://github.com/bdero/flutter_scene/issues/22): generate
/// this packing code at build time from a declarative material
/// source so callers don't write it by hand.
class ShaderMaterial extends Material {
  /// Creates a [ShaderMaterial] wrapping [fragmentShader].
  ///
  /// The shader is typically loaded from a `.shaderbundle` produced
  /// by `flutter_gpu_shaders`. May be omitted at construction and
  /// assigned later via [setFragmentShader]; rendering throws until a
  /// shader is set. Set [useEnvironment] to `true` to have the engine
  /// bind the scene environment's IBL textures by their standard
  /// names.
  ShaderMaterial({
    gpu.Shader? fragmentShader,
    this.useEnvironment = false,
    this.cullingMode = gpu.CullMode.backFace,
    this.windingOrder = gpu.WindingOrder.counterClockwise,
    this.isOpaqueOverride = true,
  }) {
    if (fragmentShader != null) {
      setFragmentShader(fragmentShader);
    }
  }

  /// Whether the engine should bind the active [Environment]'s IBL
  /// textures (`radiance_texture`, `irradiance_texture`, `brdf_lut`)
  /// when the fragment shader declares them. Defaults to `false`.
  bool useEnvironment;

  /// Backface culling mode applied before drawing. Defaults to
  /// [gpu.CullMode.backFace] to match the standard materials.
  gpu.CullMode cullingMode;

  /// Triangle winding order. Defaults to
  /// [gpu.WindingOrder.counterClockwise] to match the glTF
  /// convention and the standard materials.
  gpu.WindingOrder windingOrder;

  /// Whether this material participates in the opaque pass.
  ///
  /// Returned from [isOpaque]. Set to `false` for translucent
  /// materials, which the encoder defers to the back-to-front
  /// translucent pass with alpha blending.
  bool isOpaqueOverride;

  final Map<String, ByteData> _uniformBlocks = {};
  final Map<String, _BoundTexture> _textures = {};

  /// Assign the byte contents of a uniform block by name.
  ///
  /// [bytes] must already match the block's std140 layout. Replacing
  /// an existing assignment overrides the previous value. Pass `null`
  /// to clear the binding.
  void setUniformBlock(String name, ByteData? bytes) {
    if (bytes == null) {
      _uniformBlocks.remove(name);
    } else {
      _uniformBlocks[name] = bytes;
    }
  }

  /// Convenience wrapper around [setUniformBlock] that packs a list
  /// of float values. The caller is still responsible for std140
  /// padding; see the class doc.
  void setUniformBlockFromFloats(String name, List<double> floats) {
    setUniformBlock(name, ByteData.sublistView(Float32List.fromList(floats)));
  }

  /// Read back a previously-set uniform block, or `null` when none
  /// has been set.
  ByteData? getUniformBlock(String name) => _uniformBlocks[name];

  /// All currently-bound uniform block names. Order is insertion order.
  Iterable<String> get uniformBlockNames => _uniformBlocks.keys;

  /// Assign a texture to a sampler uniform by name.
  ///
  /// Pass `null` for [texture] to clear the binding.
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

  /// Read back a previously-set texture binding, or `null` when none
  /// has been set.
  gpu.Texture? getTexture(String name) => _textures[name]?.texture;

  /// All currently-bound sampler names. Order is insertion order.
  Iterable<String> get textureNames => _textures.keys;

  @override
  bool isOpaque() => isOpaqueOverride;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(cullingMode);
    pass.setWindingOrder(windingOrder);

    for (final entry in _uniformBlocks.entries) {
      pass.bindUniform(
        fragmentShader.getUniformSlot(entry.key),
        transientsBuffer.emplace(entry.value),
      );
    }

    for (final entry in _textures.entries) {
      pass.bindTexture(
        fragmentShader.getUniformSlot(entry.key),
        entry.value.texture,
        sampler: entry.value.sampler ?? gpu.SamplerOptions(),
      );
    }

    if (useEnvironment) {
      _bindEnvironmentTextures(pass, lighting.environment);
    }
  }

  void _bindEnvironmentTextures(gpu.RenderPass pass, Environment environment) {
    final samplerOptions = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('radiance_texture'),
      environment.environmentMap.radianceTexture,
      sampler: samplerOptions,
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('irradiance_texture'),
      environment.environmentMap.irradianceTexture,
      sampler: samplerOptions,
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('brdf_lut'),
      Material.getBrdfLutTexture(),
      sampler: samplerOptions,
    );
  }
}

class _BoundTexture {
  _BoundTexture(this.texture, this.sampler);
  final gpu.Texture texture;
  final gpu.SamplerOptions? sampler;
}
