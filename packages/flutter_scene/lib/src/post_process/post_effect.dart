import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/shader_uniform_bindings.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Where in the post-processing chain a [PostEffect] runs.
/// {@category Rendering}
enum PostInsertion {
  /// Runs on the linear HDR scene color, before tone mapping. The shader
  /// should output linear HDR premultiplied by alpha, the same contract as
  /// a material fragment shader.
  beforeTonemap,

  /// Runs on the display-referred image, after tone mapping.
  afterTonemap,
}

/// A custom, user-authored post-processing effect: a fragment shader that
/// reads the current color and writes a new one.
///
/// This is the post-processing counterpart of `ShaderMaterial`. Author a
/// fragment shader, compile it through the `flutter_gpu_shaders` build hook
/// into a `.shaderbundle`, load it, wrap it in a [PostEffect], and add it
/// to `Scene.postProcess.customEffects`.
///
/// ## Engine-bound resources
///
/// The engine binds the current color to a `sampler2D input_color`, which
/// the shader samples at the `v_uv` varying:
///
/// ```glsl
/// uniform sampler2D input_color;
/// in vec2 v_uv;
/// out vec4 frag_color;
/// void main() { frag_color = texture(input_color, v_uv); }
/// ```
///
/// Set [useFrameInfo] to also receive a `PostFrameInfo` block with the
/// target resolution, texel size, and a seconds time value:
///
/// ```glsl
/// uniform PostFrameInfo {
///   vec2 resolution;
///   vec2 texel_size;
///   float time;
///   float _pad;
/// } frame;
/// ```
///
/// Declare your own uniform blocks and textures and set them by name with
/// [setUniformBlock] / [setTexture], exactly like `ShaderMaterial`; the
/// std140 packing rules are the same (see `MATERIALS.md`).
///
/// A [PostInsertion.beforeTonemap] effect should output linear HDR
/// premultiplied by alpha; a [PostInsertion.afterTonemap] effect works on
/// the display-referred image.
/// {@category Rendering}
class PostEffect {
  PostEffect({
    gpu.Shader? fragmentShader,
    this.insertion = PostInsertion.beforeTonemap,
    this.enabled = true,
    this.useFrameInfo = false,
  }) : _fragmentShader = fragmentShader;

  gpu.Shader? _fragmentShader;

  /// The fragment shader run for this effect. Set it via the constructor or
  /// [setFragmentShader]; reading it throws until one is set.
  gpu.Shader get fragmentShader {
    final shader = _fragmentShader;
    if (shader == null) {
      throw StateError('PostEffect has no fragment shader set.');
    }
    return shader;
  }

  /// Assigns the fragment shader run for this effect.
  void setFragmentShader(gpu.Shader shader) => _fragmentShader = shader;

  /// Where in the chain this effect runs.
  PostInsertion insertion;

  /// Whether this effect runs. Disabled effects are skipped.
  bool enabled;

  /// Whether the engine binds the `PostFrameInfo` block. Set this when the
  /// shader declares and uses it.
  bool useFrameInfo;

  final ShaderUniformBindings _bindings = ShaderUniformBindings();

  /// Assigns the byte contents of a uniform block by name (std140 layout).
  void setUniformBlock(String name, ByteData? bytes) =>
      _bindings.setUniformBlock(name, bytes);

  /// Convenience wrapper around [setUniformBlock] that packs floats.
  void setUniformBlockFromFloats(String name, List<double> floats) =>
      _bindings.setUniformBlockFromFloats(name, floats);

  /// Reads back a previously-set uniform block, or `null`.
  ByteData? getUniformBlock(String name) => _bindings.getUniformBlock(name);

  /// All currently-bound uniform block names.
  Iterable<String> get uniformBlockNames => _bindings.uniformBlockNames;

  /// Assigns a texture to a sampler uniform by name.
  void setTexture(
    String name,
    gpu.Texture? texture, {
    gpu.SamplerOptions? sampler,
  }) => _bindings.setTexture(name, texture, sampler: sampler);

  /// Reads back a previously-set texture binding, or `null`.
  gpu.Texture? getTexture(String name) => _bindings.getTexture(name);

  /// All currently-bound sampler names.
  Iterable<String> get textureNames => _bindings.textureNames;

  /// Binds this effect's own uniform blocks and textures. Engine-internal.
  void bindUniforms(gpu.RenderPass pass, TransientWriter transientsBuffer) =>
      _bindings.bind(pass, fragmentShader, transientsBuffer);
}
