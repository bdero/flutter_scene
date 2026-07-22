import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// Selects how a sprite's color is blended into the scene.
/// {@category Materials}
enum SpriteBlendMode {
  /// Premultiplied source-over: the sprite occludes what is behind it by its
  /// alpha. Use for smoke, dust, and other absorbing media.
  alpha,

  /// Additive: the sprite's color is added to the scene and never darkens it.
  /// Order-independent, so additive sprites need no depth sorting. Use for
  /// fire, sparks, glows, and magic.
  additive,
}

/// A material for camera-facing quads drawn by [BillboardGeometry].
///
/// Samples [colorTexture] at the billboard's (flipbook-aware) UV, multiplies
/// by the per-instance color and [tint], and outputs linear HDR premultiplied
/// alpha. [blendMode] chooses alpha vs additive compositing; both run in the
/// renderer's one translucent pass.
///
/// Sprites are always treated as translucent (so they are depth-sorted
/// against the scene and skip the shadow and depth passes) and are drawn
/// double-sided, since a camera-facing quad's winding is not meaningful.
///
/// Wraps the `SpriteFragment` shader from [baseShaderLibrary].
/// {@category Materials}
class SpriteMaterial extends Material {
  /// Creates a [SpriteMaterial], optionally textured.
  ///
  /// When [colorTexture] is null a 1x1 white placeholder is used, so the
  /// sprite reduces to a flat [tint] times the per-instance color.
  SpriteMaterial({this.colorTexture}) {
    setFragmentShader(baseShaderLibrary['SpriteFragment']!);
  }

  /// The sprite's color texture, sampled and multiplied by the per-instance
  /// color and [tint]. Accepts a [Texture2D] or a `RenderTexture`; an empty
  /// slot resolves to a 1x1 white placeholder.
  TextureSource? colorTexture;

  /// Linear RGBA tint multiplied into every sprite of this material.
  Vector4 tint = Colors.white;

  /// How sprites of this material composite into the scene.
  SpriteBlendMode blendMode = SpriteBlendMode.alpha;

  /// Soft-particle fade distance in world units, `0` (the default) off.
  ///
  /// When set, fragments fade out as they approach the opaque geometry
  /// behind them, so fog, smoke, and dust dissolve through terrain and props
  /// instead of cutting a hard intersection edge. A nonzero value requests
  /// the scene depth input, which turns on the camera depth prepass.
  double softDepthFade = 0.0;

  /// Camera fade distance in world units, `0` (the default) off. Sprites
  /// dissolve as the camera gets within this distance, so it never clips
  /// through a hard-edged quad.
  double cameraNearFade = 0.0;

  // Soft particles read the opaque linear depth.
  @override
  Set<RenderInput> get sceneInputs =>
      softDepthFade > 0.0 ? const {RenderInput.depth} : const <RenderInput>{};

  /// The sampler used for [colorTexture]. Defaults to linear filtering with
  /// edge clamping, which suits both single sprites and flipbook atlases.
  gpu.SamplerOptions sampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  // Sprites always blend; they never write depth or cast shadows.
  @override
  bool isOpaque() => false;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);
    // A camera-facing quad's winding flips with the viewing angle, so cull
    // nothing rather than guess a front face.
    pass.setCullMode(gpu.CullMode.none);
    // Sprites keep the encoder's translucent depth state: the lessEqual test
    // (so opaque geometry occludes them) with depth writes off (so the
    // overlapping instances of one instanced draw do not self-occlude).

    final viewport = lighting.viewportSize;
    final depthAvailable = lighting.sceneDepthLinear != null;
    final fragInfo = Float32List(12);
    fragInfo[0] = tint.r;
    fragInfo[1] = tint.g;
    fragInfo[2] = tint.b;
    fragInfo[3] = tint.a;
    fragInfo[4] = blendMode == SpriteBlendMode.additive ? 1.0 : 0.0;
    fragInfo[5] = depthAvailable && softDepthFade > 0.0
        ? 1.0 / softDepthFade
        : 0.0;
    fragInfo[6] = cameraNearFade > 0.0 ? 1.0 / cameraNearFade : 0.0;
    fragInfo[8] = viewport.width > 0 ? 1.0 / viewport.width : 0.0;
    fragInfo[9] = viewport.height > 0 ? 1.0 / viewport.height : 0.0;
    pass.bindUniform(
      fragmentShader.getUniformSlot('FragInfo'),
      transientsBuffer.emplace(ByteData.sublistView(fragInfo)),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('base_color_texture'),
      Material.whitePlaceholder(resolveTextureSource(colorTexture)),
      sampler: textureSourceSampler(colorTexture) ?? sampler,
    );
    // Always bound (a white placeholder when the prepass did not run) so the
    // sampler is never left dangling; the fade is disabled in that case.
    EngineLightingUniforms.bindSceneInputTextures(
      pass,
      fragmentShader,
      lighting,
      const {RenderInput.depth},
    );
  }
}
