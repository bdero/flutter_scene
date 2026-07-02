import 'package:flutter/foundation.dart';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/light.dart';

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Validates a value assigned to a material texture slot.
///
/// Slots accept a [gpu.Texture], a [RenderTexture] (sampled live), or
/// null; anything else throws an [ArgumentError]. Returns [value]. The
/// setters are typed `Object?` because Dart has no overloads and the two
/// accepted types share no usable supertype.
@internal
Object? checkTextureSource(Object? value, String name) {
  if (value == null || value is gpu.Texture || value is RenderTexture) {
    return value;
  }
  throw ArgumentError.value(
    value,
    name,
    'Expected a gpu.Texture or a RenderTexture',
  );
}

/// Resolves a texture-slot value to the texture to sample this frame.
///
/// A [RenderTexture] resolves to its latest completed frame (null before
/// the first render, so the slot's placeholder applies).
@internal
gpu.Texture? resolveTextureSource(Object? source) =>
    source is RenderTexture ? source.texture : source as gpu.Texture?;

/// The sampler a texture-slot value asks for, or null to use the
/// material's default. A [RenderTexture] carries its own
/// [RenderTexture.sampling].
@internal
gpu.SamplerOptions? textureSourceSampler(Object? source) =>
    source is RenderTexture ? source.sampling.toSamplerOptions() : null;

/// Base class for shading a [MeshPrimitive].
///
/// A material owns the fragment shader plus any per-material parameters
/// (colors, factors, textures) bound when the primitive is drawn. The
/// built-in subclasses are [UnlitMaterial] (constant color / texture)
/// and [PhysicallyBasedMaterial] (PBR metallic-roughness with image-based
/// lighting). Custom subclasses can be implemented by overriding
/// [bind] and supplying their own fragment shader.
///
/// The default [bind] enables back-face culling with counter-clockwise
/// winding, matching the [glTF coordinate convention](https://github.com/KhronosGroup/glTF/tree/main/specification/2.0#coordinate-system-and-units).
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

  /// Loads the bundled BRDF lookup texture used by the PBR fragment
  /// shader's split-sum specular IBL.
  ///
  /// Called by the [Scene] constructor; rendering is gated on the
  /// returned [Future] completing. The same future is reused on
  /// subsequent calls.
  static Future<void> initializeStaticResources() {
    return gpuTextureFromAsset(
      'packages/flutter_scene/assets/ibl_brdf_lut.png',
    ).then((gpu.Texture value) {
      _brdfLutTexture = value;
    });
  }

  /// Whether to render both faces of triangles drawn with this material
  /// (glTF's `material.doubleSided`). When true, [bind] disables back-face
  /// culling so the geometry is visible from both sides; otherwise back faces
  /// are culled. Defaults to false. The runtime importer sets it from the glTF
  /// material.
  bool doubleSided = false;

  /// Per-draw level-of-detail cross-fade coverage, set by the encoder right
  /// before [bind] and written into the material's `FragInfo.fade`. 1 draws
  /// every fragment; a value in (0, 1) keeps that dithered fraction and a
  /// negative value keeps the complement (see lod_fade.glsl). Only the
  /// built-in lit and unlit materials honor it.
  @internal
  double lodFade = 1.0;

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
  }

  /// Assigns the fragment shader by [name] from [baseShaderLibrary].
  ///
  /// The shader is resolved lazily on first use and then cached, so a
  /// material can be constructed before [Scene.initializeStaticResources]
  /// has loaded the base shader bundle. The shader is only needed at render
  /// time, which the engine already defers until the bundle is ready.
  void setFragmentShaderName(String name) {
    _fragmentShaderName = name;
    _fragmentShader = null;
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

  /// Binds this material's vertex-stage uniforms to [vertexShader], called by
  /// the encoder only when it used a material-supplied vertex shader (see
  /// [materialVertexShader]). The base implementation is a no-op; a material
  /// with vertex-stage parameters binds them here.
  @internal
  void bindVertexStage(
    gpu.RenderPass pass,
    gpu.Shader vertexShader,
    gpu.HostBuffer transientsBuffer,
  ) {}

  /// Binds this material's render-pass state, uniforms, and textures.
  ///
  /// The base implementation enables back-face culling with
  /// counter-clockwise winding (matching the glTF convention). Subclasses
  /// must call `super.bind` and then bind any per-material uniforms and
  /// textures expected by their fragment shader. [lighting] carries the
  /// IBL [EnvironmentMap] (and its intensity) plus the analytic lights and
  /// shadow resources that materials shade against.
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    // Double-sided is honored only for opaque materials. A translucent
    // material is always back-face culled: drawing both sides would blend the
    // overlapping front and back surfaces in triangle-index order rather than
    // depth order (the translucent pass has no per-fragment sorting), which
    // seams thick double-sided glass. Single-sided draws just the outer
    // surface.
    final cullBackFace = !doubleSided || !isOpaque();
    pass.setCullMode(cullBackFace ? gpu.CullMode.backFace : gpu.CullMode.none);
    pass.setWindingOrder(gpu.WindingOrder.counterClockwise);
  }

  /// Whether geometry rendered with this material is fully opaque.
  ///
  /// The renderer uses this to split draws into the opaque and
  /// translucent passes (see [SceneEncoder]). Translucent draws are
  /// depth-sorted and drawn after the opaque pass with alpha blending
  /// enabled.
  bool isOpaque() {
    return true;
  }
}
