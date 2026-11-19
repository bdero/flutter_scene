import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show AlphaMode, TextureTransform;
import 'package:flutter_scene/src/material/texture_transform_cache.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:vector_math/vector_math.dart';

/// A material that draws geometry with a flat color or texture, ignoring
/// scene lighting.
///
/// Useful for UI overlays, debug visualization, or stylized rendering.
/// The final color is `baseColorFactor * baseColorTexture`, optionally
/// blended with the per-vertex color via [vertexColorWeight].
///
/// Wraps the `UnlitFragment` shader from the base shader library.
/// {@category Materials}
class UnlitMaterial extends Material {
  @override
  bool get participatesInDebugViews => true;

  /// Creates an [UnlitMaterial], optionally textured.
  ///
  /// When [colorTexture] is null a 1×1 white placeholder is used so the
  /// final color reduces to [baseColorFactor].
  UnlitMaterial({TextureSource? colorTexture})
    : baseColorTexture = colorTexture {
    setFragmentShaderName('UnlitFragment');
  }

  /// The raw slot source, for serialization (same value as [baseColorTexture]).
  @internal
  TextureSource? get baseColorTextureSource => baseColorTexture;

  /// The base color texture, sampled and multiplied by [baseColorFactor].
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live). An empty slot
  /// (or a render texture with no completed frame yet) samples a 1×1 white
  /// placeholder so the final color reduces to [baseColorFactor].
  TextureSource? baseColorTexture;

  /// UV transform applied to [baseColorTexture].
  TextureTransform baseColorTextureTransform = TextureTransform();

  /// Texture-coordinate channel used by [baseColorTexture].
  int baseColorTextureTexCoord = 0;

  static final Float32List _fragInfoScratch = Float32List(7);
  static final ByteData _fragInfoBytes = ByteData.sublistView(_fragInfoScratch);

  static final gpu.SamplerOptions _repeatSampler = gpu.SamplerOptions(
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.repeat,
  );

  final TextureTransformCache _textureTransform =
      TextureTransformCache.single();

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

  @override
  bool get lodCrossFades => true;

  /// Treats [baseColorTexture] and [baseColorFactor] as display-referred
  /// (final screen values) instead of scene-referred radiance.
  ///
  /// The surface is drawn past the tone curve and composited onto the
  /// resolved image, so an authored color arrives on screen unchanged. Use it
  /// for captured widgets and other UI textured into the scene;
  /// `WidgetComponent` sets it on the material it owns. The surface keeps its
  /// depth test against the scene but takes no exposure, grading, tone
  /// mapping, fog or bloom, and does not order against translucent geometry.
  ///
  /// With this set, [baseColorFactor] multiplies in display space rather than
  /// linear space.
  @override
  bool displayReferred = false;

  /// Linear RGBA tint multiplied with [baseColorTexture].
  Vector4 baseColorFactor = Colors.white;

  /// How strongly per-vertex colors influence the final color. `0`
  /// disables vertex color contribution; `1` (the default) fully
  /// applies it.
  double vertexColorWeight = 1.0;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);

    _fragInfoScratch
      ..[0] = baseColorFactor.r
      ..[1] = baseColorFactor.g
      ..[2] = baseColorFactor.b
      ..[3] = baseColorFactor.a
      ..[4] = vertexColorWeight
      ..[5] = lodFade
      ..[6] = displayReferred ? 1.0 : 0.0;
    pass.bindUniform(
      fragmentShader.cachedUniformSlot("FragInfo"),
      transientsBuffer.emplace(_fragInfoBytes),
    );
    pass.bindUniform(
      fragmentShader.cachedUniformSlot('TextureTransform'),
      transientsBuffer.emplace(
        _textureTransform.packSingle(
          baseColorTextureTransform,
          baseColorTextureTexCoord,
        ),
      ),
    );
    final resolved = resolveTextureSource(baseColorTexture);
    pass.bindTexture(
      fragmentShader.cachedUniformSlot('base_color_texture'),
      Material.whitePlaceholder(resolved),
      sampler: samplerOrPlaceholder(
        resolved,
        textureSourceSampler(baseColorTexture) ?? _repeatSampler,
      ),
    );
    // The unlit shader carries the FogInfo block (fog.glsl) too.
    EngineLightingUniforms.bindFog(
      pass,
      fragmentShader,
      transientsBuffer,
      lighting,
    );
    EngineLightingUniforms.bindViewInfo(
      pass,
      fragmentShader,
      transientsBuffer,
      lighting,
    );
  }
}
