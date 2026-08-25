import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Matrix4;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/dfg_lut.dart';

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/instance_attributes.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/planar_reflection.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

int _sceneInputsRevision = 0;

/// Changes whenever live material metadata changes its scene inputs.
@internal
int get materialSceneInputsRevision => _sceneInputsRevision;

/// Invalidates cached scene-input summaries after material hot reload.
@internal
void markMaterialSceneInputsChanged() {
  _sceneInputsRevision++;
}

/// Resolves a texture-slot value to the texture to sample this frame.
///
/// A [RenderTexture] resolves to its latest completed frame (null before
/// the first render, so the slot's placeholder applies).
@internal
gpu.Texture? resolveTextureSource(TextureSource? source) =>
    source?.sampledTexture;

/// The sampler a texture-slot value asks for, or null to use the material's
/// default (only when there is no source; every [TextureSource] carries one).
@internal
gpu.SamplerOptions? textureSourceSampler(TextureSource? source) =>
    source?.sampledSampler;

/// Base class for shading a [MeshPrimitive].
///
/// A material owns the fragment shader plus any per-material parameters
/// (colors, factors, textures) bound when the primitive is drawn. The
/// built-in subclasses are [UnlitMaterial] (constant color / texture)
/// and [PhysicallyBasedMaterial] (PBR metallic-roughness with image-based
/// lighting). Custom subclasses can be implemented by overriding
/// [bind] and supplying their own fragment shader.
///
/// The default [bind] enables back-face culling with native counter-clockwise
/// winding.
/// {@category Materials}
abstract class Material {
  static gpu.Texture? _whitePlaceholderTexture;

  /// Returns a 1×1 opaque-white texture, lazily created on first use.
  ///
  /// Used as a default for missing color textures so shader code can
  /// always sample without conditionals.
  static gpu.Texture getWhitePlaceholderTexture() {
    if (_whitePlaceholderTexture != null) {
      return _whitePlaceholderTexture!;
    }
    _whitePlaceholderTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      1,
      1,
    );
    if (_whitePlaceholderTexture == null) {
      throw Exception('Failed to create white placeholder texture.');
    }
    _whitePlaceholderTexture!.overwrite(
      Uint32List.fromList(<int>[0xFFFFFFFF]).buffer.asByteData(),
    );
    return _whitePlaceholderTexture!;
  }

  /// Returns [texture] if non-null, otherwise [getWhitePlaceholderTexture].
  static gpu.Texture whitePlaceholder(gpu.Texture? texture) {
    return texture ?? getWhitePlaceholderTexture();
  }

  static gpu.Texture? _normalPlaceholderTexture;

  /// Returns a 1×1 "flat" tangent-space normal texture (`(0.5, 0.5, 1)`),
  /// lazily created on first use.
  ///
  /// Used as a default for missing normal maps so shader code can always
  /// sample without conditionals.
  static gpu.Texture getNormalPlaceholderTexture() {
    if (_normalPlaceholderTexture != null) {
      return _normalPlaceholderTexture!;
    }
    _normalPlaceholderTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      1,
      1,
    );
    if (_normalPlaceholderTexture == null) {
      throw Exception('Failed to create normal placeholder texture.');
    }
    _normalPlaceholderTexture!.overwrite(
      Uint32List.fromList(<int>[0xFFFF7F7F]).buffer.asByteData(),
    );
    return _normalPlaceholderTexture!;
  }

  /// Returns [texture] if non-null, otherwise [getNormalPlaceholderTexture].
  static gpu.Texture normalPlaceholder(gpu.Texture? texture) {
    return texture ?? getNormalPlaceholderTexture();
  }

  static gpu.Texture? _blackPlaceholderTexture;

  /// Returns a 1×1 opaque-black texture, lazily created on first use.
  ///
  /// Used as the specular source for [EnvironmentMap.empty] so the shader
  /// can sample an "atlas" that contributes no reflection.
  static gpu.Texture getBlackPlaceholderTexture() {
    if (_blackPlaceholderTexture != null) {
      return _blackPlaceholderTexture!;
    }
    _blackPlaceholderTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      1,
      1,
    );
    if (_blackPlaceholderTexture == null) {
      throw Exception('Failed to create black placeholder texture.');
    }
    _blackPlaceholderTexture!.overwrite(
      Uint32List.fromList(<int>[0xFF000000]).buffer.asByteData(),
    );
    return _blackPlaceholderTexture!;
  }

  static gpu.Texture? _brdfLutTexture;
  static EnvironmentMap? _defaultEnvironmentMap;

  /// Returns the precomputed BRDF lookup texture used by the PBR
  /// fragment shader for environment-map specular sampling.
  ///
  /// Loaded by [initializeStaticResources]; throws if accessed before
  /// initialization completes.
  @internal
  static gpu.Texture getBrdfLutTexture() {
    if (_brdfLutTexture == null) {
      throw Exception('BRDF LUT texture has not been initialized.');
    }
    return _brdfLutTexture!;
  }

  /// Returns the package's built-in procedural "studio" image-based
  /// lighting environment (see [EnvironmentMap.studio]), built once and
  /// memoized.
  ///
  /// Used as the [Scene]-wide default when no environment is configured.
  static EnvironmentMap getDefaultEnvironmentMap() {
    return _defaultEnvironmentMap ??= EnvironmentMap.studio();
  }

  /// Builds the BRDF lookup texture and loads the physical shader variants.
  ///
  /// Called by the [Scene] constructor; rendering is gated on the returned
  /// [Future] completing. The texture is built once and reused.
  static Future<void> initializeStaticResources() async {
    if (_brdfLutTexture == null) {
      final ltc = await rootBundle.load(
        'packages/flutter_scene/assets/ltc.bin',
      );
      _brdfLutTexture = buildBrdfLutTexture(
        ltcHalfData: ltc.buffer.asUint16List(
          ltc.offsetInBytes,
          ltc.lengthInBytes ~/ 2,
        ),
      );
    }
    await PhysicallyBasedMaterial.initializeStaticResources();
  }

  /// The name of this material, used for identification.
  ///
  /// The importers set it from the source asset's material name; empty when
  /// the source material is unnamed or the material was created directly.
  String name = '';

  /// Whether to render both faces of triangles drawn with this material
  /// (glTF's `material.doubleSided`). When true, [bind] disables back-face
  /// culling so the geometry is visible from both sides; otherwise back faces
  /// are culled. Defaults to false. The runtime importer sets it from the glTF
  /// material.
  bool doubleSided = false;

  /// World-space offset toward the camera used for coplanar surface details.
  /// Positive values keep an overlay in front of its supporting surface
  /// without modifying its node transform. Zero and negative values leave the
  /// draw position unchanged. A fixed world offset provides fewer depth-buffer
  /// units as camera distance grows, so distant coplanar surfaces may need a
  /// larger value.
  // TODO(depth-bias-distance): add a distance or slope-scaled mode for decals
  // that must remain separated across a large depth range.
  double depthBias = 0.0;

  /// Per-draw level-of-detail cross-fade coverage, set by the encoder right
  /// before [bind] and written into the material's `FragInfo.fade`. 1 draws
  /// every fragment; a value in (0, 1) keeps that dithered fraction and a
  /// negative value keeps the complement (see lod_fade.glsl). Only the
  /// built-in lit and unlit materials honor it.
  @internal
  double lodFade = 1.0;

  /// The owning render item's punctual-light slice, set by the encoder right
  /// before [bind] and written into `FragInfo.radiance_blend.zw`. The lit
  /// materials loop the `[lightListOffset, +lightListCount)` range of the
  /// per-frame light-index buffer, so each item shades only the lights that
  /// reach it. Both default to 0 (no punctual lights).
  @internal
  int lightListOffset = 0;
  @internal
  int lightListCount = 0;

  /// The owning render item's light channels, set by the encoder right before
  /// [bind]. The punctual lights are already filtered by the culler, so this
  /// only gates the primary directional light, whose data rides its own
  /// uniform path. Defaults to `0xFF` (every channel).
  @internal
  int lightChannelMask = 0xFF;

  /// The draw's model scale (world-space lengths of the model transform's
  /// basis vectors), set by the encoder right before [bind] and packed into
  /// `FragInfo.model_scale`. Scales local-space lengths like the transmission
  /// volume thickness into world units. An instanced draw carries its node's
  /// scale (not per-instance), and a skinned draw its node's (not per-joint).
  @internal
  double modelScaleX = 1.0;
  @internal
  double modelScaleY = 1.0;
  @internal
  double modelScaleZ = 1.0;

  /// Sets [modelScaleX]/[modelScaleY]/[modelScaleZ] from [transform]'s basis
  /// vector lengths. Called by the encoder with the drawn world transform.
  @internal
  void setModelScaleFromTransform(Matrix4 transform) {
    final s = transform.storage;
    modelScaleX = math.sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]);
    modelScaleY = math.sqrt(s[4] * s[4] + s[5] * s[5] + s[6] * s[6]);
    modelScaleZ = math.sqrt(s[8] * s[8] + s[9] * s[9] + s[10] * s[10]);
  }

  gpu.Shader? _fragmentShader;
  String? _fragmentShaderName;

  /// The fragment shader used when rendering geometry with this material.
  ///
  /// Subclasses assign this in their constructor, either directly with
  /// [setFragmentShader] or, for a shader from [baseShaderLibrary], by name
  /// with [setFragmentShaderName]. A name is resolved on first access and
  /// cached, so the lookup happens once (at render time) rather than per
  /// draw. Throws if accessed before a shader has been assigned, or before
  /// the base shader bundle has loaded for a named shader.
  gpu.Shader get fragmentShader {
    final resolved = _fragmentShader ??= _fragmentShaderName == null
        ? null
        : baseShaderLibrary[_fragmentShaderName!];
    if (resolved == null) {
      throw Exception('Fragment shader has not been set');
    }
    return resolved;
  }

  /// Assigns the fragment [shader] used when this material is drawn.
  void setFragmentShader(gpu.Shader shader) {
    _fragmentShader = shader;
    _fragmentShaderName = null;
    _noShadowFragmentShader = null;
    _noShadowFragmentShaderName = null;
    _noShadowRadianceCubeFragmentShader = null;
    _noShadowRadianceCubeFragmentShaderName = null;
  }

  /// Assigns the fragment shader by [name] from [baseShaderLibrary].
  ///
  /// The shader is resolved lazily on first use and then cached, so a
  /// material can be constructed before [Scene.initializeStaticResources]
  /// has loaded the base shader bundle. The shader is only needed at render
  /// time, which the engine already defers until the bundle is ready.
  ///
  /// [cubeName] is the twin built for the cubemap radiance layout, needed by
  /// any shader that samples the environment (see [radianceCubeFragmentShader]).
  ///
  /// [noShadowName] and [noShadowCubeName] are the twins built with
  /// `FLUTTER_SCENE_SKIP_SHADOWS`, selected for a draw with no shadow atlas
  /// bound (see [fragmentShaderForLighting]). A material without them always
  /// draws with the full shaders.
  void setFragmentShaderName(
    String name, {
    String? cubeName,
    String? noShadowName,
    String? noShadowCubeName,
  }) {
    _fragmentShaderName = name;
    _fragmentShader = null;
    _radianceCubeFragmentShaderName = cubeName;
    _radianceCubeFragmentShader = null;
    _noShadowFragmentShaderName = noShadowName;
    _noShadowFragmentShader = null;
    _noShadowRadianceCubeFragmentShaderName = noShadowCubeName;
    _noShadowRadianceCubeFragmentShader = null;
  }

  gpu.Shader? _radianceCubeFragmentShader;
  String? _radianceCubeFragmentShaderName;
  gpu.Shader? _noShadowFragmentShader;
  String? _noShadowFragmentShaderName;
  gpu.Shader? _noShadowRadianceCubeFragmentShader;
  String? _noShadowRadianceCubeFragmentShaderName;

  /// Assigns the already-loaded variant built with
  /// `FLUTTER_SCENE_RADIANCE_CUBE`, the counterpart of [setFragmentShader]
  /// for a material that samples the environment.
  void setRadianceCubeFragmentShader(gpu.Shader? shader) {
    _radianceCubeFragmentShader = shader;
    _radianceCubeFragmentShaderName = null;
  }

  /// The variant compiled for a cubemap prefiltered radiance, or null when
  /// this material does not sample the environment.
  ///
  /// Backends differ in the radiance layout they can build and each variant
  /// declares only its own sampler type, so a material that reads the
  /// environment carries one shader per layout and picks by the environment
  /// bound for the draw.
  @internal
  gpu.Shader? get radianceCubeFragmentShader =>
      _radianceCubeFragmentShader ??= _radianceCubeFragmentShaderName == null
      ? null
      : baseShaderLibrary[_radianceCubeFragmentShaderName!];

  /// Whether this material draws with its cubemap-radiance variant for
  /// [lighting], which is also what decides the radiance texture bound to it.
  ///
  /// False when the material carries no cube variant, so a material that was
  /// built without one keeps its 2D sampler and is bound a 2D texture rather
  /// than a mismatched cubemap.
  ///
  /// Both decisions must come from here. Picking the shader and the texture
  /// separately lets a material fall back to its 2D sampler while the bound
  /// environment hands it a cubemap, which no sampler can read; it then
  /// samples whatever texture the unit still held, which is silent on
  /// backends that leave nothing there and garbage on the ones that do.
  @internal
  bool usesRadianceCubeVariant(Lighting lighting) =>
      lighting.environmentMap.usesCubeRadianceLayout &&
      radianceCubeFragmentShader != null;

  /// The `FLUTTER_SCENE_SKIP_SHADOWS` twin of [fragmentShader], or null when
  /// this material carries none and always draws with the full shader.
  @internal
  gpu.Shader? get noShadowFragmentShader =>
      _noShadowFragmentShader ??= _noShadowFragmentShaderName == null
      ? null
      : baseShaderLibrary[_noShadowFragmentShaderName!];

  /// The `FLUTTER_SCENE_SKIP_SHADOWS` twin of [radianceCubeFragmentShader],
  /// or null when this material carries none.
  @internal
  gpu.Shader? get noShadowRadianceCubeFragmentShader =>
      _noShadowRadianceCubeFragmentShader ??=
          _noShadowRadianceCubeFragmentShaderName == null
          ? null
          : baseShaderLibrary[_noShadowRadianceCubeFragmentShaderName!];

  /// Whether [fragmentShaderForLighting] picks a no-shadow twin for
  /// [lighting], which is also what decides whether the `shadow_map` sampler
  /// (which that twin does not declare) gets bound. Both decisions must come
  /// from here, like [usesRadianceCubeVariant].
  @internal
  bool usesNoShadowVariant(Lighting lighting) =>
      lighting.shadowMap == null &&
      (usesRadianceCubeVariant(lighting)
              ? noShadowRadianceCubeFragmentShader
              : noShadowFragmentShader) !=
          null;

  /// Selects this material's fragment shader for the frame lighting state.
  ///
  /// The radiance-layout variant wins over the shadow one: a shadow variant
  /// in the wrong layout would be handed a texture its sampler cannot read,
  /// while dropping the no-shadow variant only costs dead shadow code.
  @internal
  gpu.Shader fragmentShaderForLighting(Lighting lighting) {
    final noShadow = usesNoShadowVariant(lighting);
    if (usesRadianceCubeVariant(lighting)) {
      return noShadow
          ? noShadowRadianceCubeFragmentShader!
          : radianceCubeFragmentShader!;
    }
    return noShadow ? noShadowFragmentShader! : fragmentShader;
  }

  /// The vertex shader this material supplies for a geometry's [variant]
  /// (`'unskinned'` / `'skinned'` for the color pass, `'depth'` for the
  /// position-only depth/shadow pass; see [Geometry.materialVertexVariant]),
  /// or null to use the engine's standard vertex shader for the geometry.
  ///
  /// The base class supplies none, so drawing is unchanged. A `.fmat` with a
  /// `vertex { }` block (see [PreprocessedMaterial]) returns the matching
  /// generated variant, which the encoder pairs with this material's fragment
  /// shader.
  @internal
  gpu.Shader? materialVertexShader(String variant) => null;

  /// The per-instance attributes this material declares, or null when it
  /// declares none. A `.fmat` `instance_attributes` block declares them, as
  /// does a raw `ShaderMaterial` constructed with `instanceAttributes`.
  ///
  /// The schema widens the instance-rate vertex buffer, so it is part of the
  /// pipeline's vertex layout as well as of what an instanced mesh accepts.
  @internal
  InstanceAttributeSchema? get instanceAttributes => null;

  /// Binds this material's vertex-stage uniforms to [vertexShader], called by
  /// the encoder only when it used a material-supplied vertex shader (see
  /// [materialVertexShader]). The base implementation is a no-op; a material
  /// with vertex-stage parameters binds them here.
  @internal
  void bindVertexStage(
    gpu.RenderPass pass,
    gpu.Shader vertexShader,
    TransientWriter transientsBuffer,
  ) {}

  /// Binds this material's render-pass state, uniforms, and textures.
  ///
  /// The base implementation enables back-face culling with clockwise
  /// winding on the Y-down rasterizer (accepting model-space CCW front faces).
  /// Subclasses must call `super.bind` and then bind any per-material uniforms
  /// and textures expected by their fragment shader. [lighting] carries the
  /// IBL [EnvironmentMap] (and its intensity) plus the analytic lights and
  /// shadow resources that materials shade against.
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(renderCullMode);
    pass.setWindingOrder(gpu.WindingOrder.clockwise);
  }

  /// The face-culling mode geometry drawn with this material renders with.
  ///
  /// Passes that draw the geometry without calling [bind] (the depth/normal
  /// prepass behind SSAO and SSR) read this to cull the same faces the color
  /// pass does. If they disagree, a double-sided material's back faces are
  /// missing from the prepass and screen-space effects sample the wrong
  /// (farther) surface where a front face is actually drawn.
  ///
  /// Double-sided is honored only for opaque materials. A translucent material
  /// is always back-face culled: drawing both sides would blend the overlapping
  /// front and back surfaces in triangle-index order rather than depth order
  /// (the translucent pass has no per-fragment sorting), which seams thick
  /// double-sided glass.
  @internal
  gpu.CullMode get renderCullMode =>
      (!doubleSided || !isOpaque()) ? gpu.CullMode.backFace : gpu.CullMode.none;

  /// Whether this translucent material writes the nearest fragment depth.
  ///
  /// Most alpha-blended surfaces leave this off. Refractive surfaces can turn
  /// it on so nearer glass wins within one draw even when its triangles are not
  /// ordered back-to-front.
  @internal
  bool get translucentDepthWrite => false;

  /// Whether this material's geometry joins the camera depth prepass that
  /// feeds the screen-space chain (ambient occlusion, contact shadows,
  /// reflections, depth of field).
  ///
  /// Opaque materials do; translucent ones normally do not (the chain wants
  /// the opaque scene). A translucent surface that must be known to the
  /// screen-space chain, the shadow catcher, overrides this to true so
  /// occlusion is evaluated at its own depth instead of the backdrop's.
  @internal
  bool get depthPrepassParticipates => isOpaque();

  /// Whether this material currently draws nothing at all, keeping its render
  /// items out of every pass (color, depth prepass, shadows).
  ///
  /// Refreshed per frame by the scene pre-pass, so a material can toggle it
  /// live. The base material always draws; the shadow catcher returns true at
  /// `shadowIntensity == 0` as a true early-out.
  @internal
  bool get drawsNothing => false;

  /// Whether geometry rendered with this material is fully opaque.
  ///
  /// The renderer uses this to split draws into the opaque and
  /// translucent passes (see [SceneEncoder]). Translucent draws are
  /// depth-sorted and drawn after the opaque pass with alpha blending
  /// enabled.
  bool isOpaque() {
    return true;
  }

  /// Per-frame engine inputs this material samples, produced only when a
  /// visible material asks for them: [RenderInput.depth] binds the linear
  /// scene depth of the opaque geometry (forcing the depth prepass), and
  /// [RenderInput.opaqueSceneColor] binds the accumulated scene color behind
  /// the current draw, and [RenderInput.filteredSceneColor] adds its
  /// roughness-filtered atlas.
  /// Together they enable refraction, depth-fade absorption, shoreline
  /// foam, and soft-particle style effects on translucent surfaces. The
  /// base material requests nothing; a `.fmat` material declares these with
  /// `engine_inputs:`.
  Set<RenderInput> get sceneInputs => const {};

  /// Whether this material samples a planar reflection capture (a `.fmat`
  /// that declares the `planar_reflection` engine input). The
  /// `PlanarReflectorComponent` governing the surface routes its capture to
  /// materials that report true.
  // TODO(planar-pbm-hook): give PhysicallyBasedMaterial a planar hook that
  // swaps the capture in for its environment specular; the lit shader sits
  // at the fragment sampler cap, so the sampler needs a variant axis or a
  // displaced slot first. The `.fmat` engine input is the supported seam.
  @internal
  bool get usesPlanarReflection => false;

  /// The planar reflection capture this material samples, or null when none
  /// is active. Refreshed each frame by the governing reflector; only read
  /// when [usesPlanarReflection] is true.
  @internal
  PlanarReflectionFrame? planarReflectionFrame;

  /// Maximum local-space distance sampled beyond the current surface.
  ///
  /// Null means the shader may sample anywhere on screen. Unknown sampling is
  /// kept unbounded so it cannot skip an accumulated scene-color capture.
  @internal
  double? get sceneColorSampleBoundsExpansion => null;

  /// Fraction of the scene-color filter pyramid sampled by this material.
  @internal
  double get sceneColorSampleFilterLodFraction => 0;

  /// The metallic-roughness texture the camera depth prepass samples so
  /// screen-space reflections have a per-pixel roughness (roughness in G),
  /// or null to use a fully-rough placeholder. The base material has none, so
  /// it reads as fully rough and receives no screen-space reflection; a lit
  /// material overrides this.
  @internal
  gpu.Texture? get reflectionRoughnessTexture => null;

  /// The UV transform applied to [reflectionRoughnessTexture] in the depth
  /// prepass.
  @internal
  TextureTransform get reflectionRoughnessTextureTransform =>
      TextureTransform();

  /// The UV channel sampled by [reflectionRoughnessTexture] in the depth
  /// prepass.
  @internal
  int get reflectionRoughnessTextureTexCoord => 0;

  /// The sampler used by [reflectionRoughnessTexture] in the depth prepass.
  @internal
  gpu.SamplerOptions? get reflectionRoughnessTextureSampler => null;

  /// The roughness multiplier applied to [reflectionRoughnessTexture] in the
  /// depth prepass (the material's roughness factor).
  @internal
  double get reflectionRoughnessFactor => 1.0;

  /// Whether the depth-writing passes (the shadow map and the camera depth
  /// prepass) must alpha-test this material's coverage instead of writing its
  /// full geometry, so cutout surfaces (foliage, fences) occlude, shadow, and
  /// receive screen-space effects only where they are actually opaque. When
  /// true, those passes draw with a masked fragment shader (which needs the
  /// full-vertex varyings, so the position-only depth path is skipped) and
  /// call [bindDepthAlphaMask]. The base material writes full geometry.
  @internal
  bool get depthAlphaMasked => false;

  /// Binds the mask texture and MaskInfo parameters consumed by the masked
  /// depth fragment shaders; [shader] is the masked variant the pass drew
  /// with. Called only when [depthAlphaMasked] is true.
  @internal
  void bindDepthAlphaMask(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {}
}
