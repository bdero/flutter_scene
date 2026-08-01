import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/shader_stage.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

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
///    `await gpu.loadShaderLibraryAsync('path/to/your.shaderbundle')` and
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
/// Setting [useEnvironment] to `true` makes the engine bind the active
/// environment's IBL textures by their standard names when your fragment
/// shader declares them: `prefiltered_radiance` (the PMREM-style
/// roughness-band atlas; sample it with `SamplePrefilteredRadiance` from
/// `texture.glsl`) and `brdf_lut` (both as `sampler2D`). The diffuse
/// irradiance SH coefficients are not bound generically; declare them in
/// your own uniform block if you need them. Useful when a custom shader
/// still wants the engine's image-based lighting.
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
/// TODO(fmat-codegen): generate this packing from the shader's
/// reflection at build time so callers don't write it by hand, the
/// way `PreprocessedMaterial` packs a `.fmat`.
/// {@category Materials}
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
    gpu.Shader? vertexShader,
    gpu.Shader? skinnedVertexShader,
    gpu.Shader? depthVertexShader,
    this.useEnvironment = false,
    this.cullingMode = gpu.CullMode.backFace,
    this.windingOrder = gpu.WindingOrder.counterClockwise,
    this.isOpaqueOverride = true,
  }) {
    if (fragmentShader != null) {
      setFragmentShader(fragmentShader);
    }
    setVertexShader(vertexShader);
    setVertexShader(skinnedVertexShader, variant: MeshVariant.skinned);
    setVertexShader(depthVertexShader, variant: MeshVariant.depth);
  }

  /// Whether the engine should bind the active environment's IBL textures
  /// (`prefiltered_radiance`, `brdf_lut`) when the fragment shader
  /// declares them. Defaults to `false`.
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
  final Map<String, ByteData> _vertexUniformBlocks = {};
  final Map<String, _BoundTexture> _vertexTextures = {};
  final Map<MeshVariant, gpu.Shader> _vertexShaders = {};

  Map<String, ByteData> _blocksFor(ShaderStage stage) =>
      stage == ShaderStage.vertex ? _vertexUniformBlocks : _uniformBlocks;

  Map<String, _BoundTexture> _texturesFor(ShaderStage stage) =>
      stage == ShaderStage.vertex ? _vertexTextures : _textures;

  /// Assigns the vertex shader this material draws [variant] meshes with, or
  /// clears it when [shader] is null.
  ///
  /// With no vertex shader the engine's standard one runs, which is the
  /// fragment-only workflow. Supplying one takes over the vertex stage for
  /// that mesh kind, and the shader must then satisfy the engine contract
  /// (see `MATERIALS.md`): it declares the `FrameInfo` block, the attributes
  /// its geometry's layout provides, and the `v_*` outputs the fragment stage
  /// reads.
  ///
  /// A mesh kind with no shader falls back to the engine's, so a material can
  /// customize static meshes and leave skinned ones alone. Supply
  /// [MeshVariant.depth] when the vertex stage moves geometry and the shadow
  /// and depth passes should see the same displacement.
  void setVertexShader(
    gpu.Shader? shader, {
    MeshVariant variant = MeshVariant.unskinned,
  }) {
    if (shader == null) {
      _vertexShaders.remove(variant);
      return;
    }
    _vertexShaders[variant] = shader;
  }

  /// The vertex shader assigned for [variant], or null when the engine's
  /// standard one runs.
  gpu.Shader? vertexShaderFor(MeshVariant variant) => _vertexShaders[variant];

  final Set<MeshVariant> _warnedMissingVariants = <MeshVariant>{};

  @override
  gpu.Shader? materialVertexShader(String variant) {
    final kind = MeshVariant.fromName(variant);
    final shader = _vertexShaders[kind];
    // Falling back to the engine's shader is fine when the fragment shader
    // only reads engine varyings, and fatal when it reads one this material's
    // own vertex shader writes: the engine's does not write it, and pipeline
    // creation fails with a backend interface error naming an anonymous
    // location. Say which variant is missing while the author can still act
    // on it. Debug-only, and once per variant.
    assert(() {
      if (shader == null && _vertexShaders.isNotEmpty) {
        _warnMissingVertexVariant(kind);
      }
      return true;
    }());
    return shader;
  }

  // Validates a uniform block against the shader's reflection before binding
  // it. Debug-only (the reflection lookup is a native call, and it must stay
  // fresh across a shader hot reload rather than being memoized), and it turns
  // two silent-or-fatal mistakes into named exceptions: a block the shader
  // does not declare, and a buffer smaller than the block's std140 size.
  bool _checkBlock(
    gpu.UniformSlot slot,
    String name,
    ByteData bytes,
    ShaderStage stage,
  ) {
    final size = slot.sizeInBytes;
    if (size == null) {
      throw StateError(
        'ShaderMaterial: the ${stage.name} shader declares no uniform block '
        'named "$name". Check the spelling (a block binds by its type name, '
        'not its instance name), and note that a block nothing in the shader '
        'reads is optimized out and reflects as absent.',
      );
    }
    if (bytes.lengthInBytes < size) {
      throw StateError(
        'ShaderMaterial: uniform block "$name" on the ${stage.name} shader '
        'needs $size bytes but was given ${bytes.lengthInBytes}. std140 pads '
        'a vec3 to 16 bytes and strides array elements to 16, so a packed '
        'Float32List is usually short; see the std140 table in MATERIALS.md.',
      );
    }
    return true;
  }

  void _warnMissingVertexVariant(MeshVariant kind) {
    if (!_warnedMissingVariants.add(kind)) return;
    debugPrint(missingVertexVariantMessage(_vertexShaders.keys, kind));
  }

  /// Assign the byte contents of a uniform block by name.
  ///
  /// [bytes] must already match the block's std140 layout. Replacing
  /// an existing assignment overrides the previous value. Pass `null`
  /// to clear the binding. [stage] picks which shader the block binds
  /// against; a block declared in both stages must be set for both.
  void setUniformBlock(
    String name,
    ByteData? bytes, {
    ShaderStage stage = ShaderStage.fragment,
  }) {
    final blocks = _blocksFor(stage);
    if (bytes == null) {
      blocks.remove(name);
    } else {
      blocks[name] = bytes;
    }
  }

  /// Convenience wrapper around [setUniformBlock] that packs a list
  /// of float values. The caller is still responsible for std140
  /// padding; see the class doc.
  void setUniformBlockFromFloats(
    String name,
    List<double> floats, {
    ShaderStage stage = ShaderStage.fragment,
  }) {
    setUniformBlock(
      name,
      ByteData.sublistView(Float32List.fromList(floats)),
      stage: stage,
    );
  }

  /// Read back a previously-set uniform block, or `null` when none
  /// has been set.
  ByteData? getUniformBlock(
    String name, {
    ShaderStage stage = ShaderStage.fragment,
  }) => _blocksFor(stage)[name];

  /// All currently-bound fragment uniform block names, in insertion order.
  Iterable<String> get uniformBlockNames => _uniformBlocks.keys;

  /// All currently-bound vertex uniform block names, in insertion order.
  Iterable<String> get vertexUniformBlockNames => _vertexUniformBlocks.keys;

  /// Assign a texture to a sampler uniform by name.
  ///
  /// [texture] accepts a raw [gpu.Texture] (the low-level custom-shader path),
  /// a [Texture2D], or a `RenderTexture` (sampled live; an explicit [sampler]
  /// overrides the source's own sampling). Pass `null` to clear the binding.
  void setTexture(
    String name,
    Object? texture, {
    gpu.SamplerOptions? sampler,
    ShaderStage stage = ShaderStage.fragment,
  }) {
    final textures = _texturesFor(stage);
    if (texture == null) {
      textures.remove(name);
      return;
    }
    if (texture is! gpu.Texture && texture is! TextureSource) {
      throw ArgumentError.value(
        texture,
        'texture',
        'Expected a gpu.Texture, a Texture2D, or a RenderTexture',
      );
    }
    textures[name] = _BoundTexture(texture, sampler);
  }

  /// Read back a previously-set texture binding, or `null` when none
  /// has been set.
  ///
  /// A slot holding a `RenderTexture` resolves to its latest completed
  /// frame (null before the first render).
  gpu.Texture? getTexture(
    String name, {
    ShaderStage stage = ShaderStage.fragment,
  }) => _resolveShaderTexture(_texturesFor(stage)[name]?.source);

  // ShaderMaterial accepts a raw gpu.Texture in addition to a TextureSource, so
  // it resolves locally rather than through the material.dart helpers.
  static gpu.Texture? _resolveShaderTexture(Object? source) =>
      source is TextureSource ? source.sampledTexture : source as gpu.Texture?;
  static gpu.SamplerOptions? _shaderTextureSampler(Object? source) =>
      source is TextureSource ? source.sampledSampler : null;

  /// All currently-bound fragment sampler names, in insertion order.
  Iterable<String> get textureNames => _textures.keys;

  /// All currently-bound vertex sampler names, in insertion order.
  Iterable<String> get vertexTextureNames => _vertexTextures.keys;

  @override
  bool isOpaque() => isOpaqueOverride;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(cullingMode);
    pass.setWindingOrder(windingOrder);

    for (final entry in _uniformBlocks.entries) {
      final slot = fragmentShader.getUniformSlot(entry.key);
      assert(_checkBlock(slot, entry.key, entry.value, ShaderStage.fragment));
      pass.bindUniform(slot, transientsBuffer.emplace(entry.value));
    }

    for (final entry in _textures.entries) {
      // An empty render texture (no completed frame yet) binds the white
      // placeholder so the sampler slot is never left dangling.
      final resolved = _resolveShaderTexture(entry.value.source);
      pass.bindTexture(
        fragmentShader.getUniformSlot(entry.key),
        Material.whitePlaceholder(resolved),
        sampler:
            entry.value.sampler ??
            _shaderTextureSampler(entry.value.source) ??
            gpu.SamplerOptions(),
      );
    }

    if (useEnvironment) {
      _bindEnvironmentTextures(pass, lighting);
    }
  }

  @override
  void bindVertexStage(
    gpu.RenderPass pass,
    gpu.Shader vertexShader,
    TransientWriter transientsBuffer,
  ) {
    for (final entry in _vertexUniformBlocks.entries) {
      final slot = vertexShader.getUniformSlot(entry.key);
      assert(_checkBlock(slot, entry.key, entry.value, ShaderStage.vertex));
      pass.bindUniform(slot, transientsBuffer.emplace(entry.value));
    }
    for (final entry in _vertexTextures.entries) {
      final resolved = _resolveShaderTexture(entry.value.source);
      pass.bindTexture(
        vertexShader.getUniformSlot(entry.key),
        Material.whitePlaceholder(resolved),
        sampler:
            entry.value.sampler ??
            _shaderTextureSampler(entry.value.source) ??
            gpu.SamplerOptions(),
      );
    }
  }

  void _bindEnvironmentTextures(gpu.RenderPass pass, Lighting lighting) {
    EngineLightingUniforms.bindPrefilteredRadiance(
      pass,
      fragmentShader,
      lighting.environmentMap,
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('brdf_lut'),
      Material.getBrdfLutTexture(),
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }
}

class _BoundTexture {
  _BoundTexture(this.source, this.sampler);

  /// A gpu.Texture or a RenderTexture (see checkTextureSource).
  final Object source;
  final gpu.SamplerOptions? sampler;
}

/// The warning a [ShaderMaterial] prints when it is asked for a vertex shader
/// for [missing] while supplying [supplied]. Library-visible for tests.
@visibleForTesting
String missingVertexVariantMessage(
  Iterable<MeshVariant> supplied,
  MeshVariant missing,
) =>
    'flutter_scene: a ShaderMaterial supplies a vertex shader for '
    '${supplied.map((v) => v.name).join(', ')} but not for ${missing.name}, '
    'so this draw pairs the engine\'s ${missing.name} vertex shader with '
    'your fragment shader. That works only if the fragment shader reads '
    'engine varyings alone; a custom varying the engine shader does not write '
    'fails pipeline creation. Supply a ${missing.name} variant, or keep the '
    'fragment shader to the engine varyings.';
