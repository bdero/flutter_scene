import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show AlphaMode;
import 'package:flutter_scene/src/shaders.dart';

import 'package:vector_math/vector_math.dart';

/// A material that draws geometry with a flat color or texture, ignoring
/// scene lighting.
///
/// Useful for UI overlays, debug visualization, or stylized rendering.
/// The final color is `baseColorFactor * baseColorTexture`, optionally
/// blended with the per-vertex color via [vertexColorWeight].
///
/// Wraps the `UnlitFragment` shader from [baseShaderLibrary].
/// {@category Materials}
class UnlitMaterial extends Material {
  /// Creates an [UnlitMaterial], optionally textured.
  ///
  /// When [colorTexture] is null a 1×1 white placeholder is used so the
  /// final color reduces to [baseColorFactor].
  UnlitMaterial({gpu.Texture? colorTexture}) : _baseColorSource = colorTexture {
    setFragmentShader(baseShaderLibrary['UnlitFragment']!);
  }

  Object? _baseColorSource;

  /// The base color texture, sampled and multiplied by [baseColorFactor].
  ///
  /// Accepts a [gpu.Texture] or a `RenderTexture` (sampled live). The
  /// getter never returns null; an empty slot (or a render texture with
  /// no completed frame yet) resolves to a 1×1 white placeholder so the
  /// final color reduces to [baseColorFactor].
  gpu.Texture get baseColorTexture =>
      Material.whitePlaceholder(resolveTextureSource(_baseColorSource));
  set baseColorTexture(Object? value) =>
      _baseColorSource = checkTextureSource(value, 'baseColorTexture');

  /// How the material's alpha is interpreted. [AlphaMode.opaque] ignores
  /// alpha; [AlphaMode.blend] routes the material through the depth-sorted
  /// translucent pass with alpha blending (use for widget textures and
  /// other surfaces with transparency).
  // TODO(materials): support AlphaMode.mask for unlit (needs a cutoff
  // uniform and a discard in the unlit fragment shader); it currently
  // behaves like blend.
  AlphaMode alphaMode = AlphaMode.opaque;

  @override
  bool isOpaque() => alphaMode == AlphaMode.opaque;

  /// Linear RGBA tint multiplied with [baseColorTexture].
  Vector4 baseColorFactor = Colors.white;

  /// How strongly per-vertex colors influence the final color. `0`
  /// disables vertex color contribution; `1` (the default) fully
  /// applies it.
  double vertexColorWeight = 1.0;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);

    var fragInfo = Float32List.fromList([
      baseColorFactor.r, baseColorFactor.g,
      baseColorFactor.b, baseColorFactor.a, // color
      vertexColorWeight, // vertex_color_weight
    ]);
    pass.bindUniform(
      fragmentShader.getUniformSlot("FragInfo"),
      transientsBuffer.emplace(ByteData.sublistView(fragInfo)),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('base_color_texture'),
      baseColorTexture,
      sampler:
          textureSourceSampler(_baseColorSource) ??
          gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat,
          ),
    );
  }
}
