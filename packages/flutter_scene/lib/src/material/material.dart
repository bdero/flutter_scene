import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/light.dart';

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

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

  static gpu.Texture? _brdfLutTexture;
  static EnvironmentMap? _defaultEnvironmentMap;

  /// Returns the precomputed BRDF lookup texture used by the PBR
  /// fragment shader for environment-map specular sampling.
  ///
  /// Loaded by [initializeStaticResources]; throws if accessed before
  /// initialization completes.
  static gpu.Texture getBrdfLutTexture() {
    if (_brdfLutTexture == null) {
      throw Exception('BRDF LUT texture has not been initialized.');
    }
    return _brdfLutTexture!;
  }

  /// Returns the package's built-in procedural "studio" image-based
  /// lighting environment (see [EnvironmentMap.studio]).
  ///
  /// Used as the [Scene]-wide default when no environment is configured.
  /// Built by [initializeStaticResources]; throws if accessed before
  /// initialization completes.
  static EnvironmentMap getDefaultEnvironmentMap() {
    if (_defaultEnvironmentMap == null) {
      throw Exception('Default environment map has not been initialized.');
    }
    return _defaultEnvironmentMap!;
  }

  /// Loads the bundled BRDF lookup texture and builds the default
  /// procedural "studio" environment ([EnvironmentMap.studio]).
  ///
  /// Called by the [Scene] constructor; rendering is gated on the
  /// returned [Future] completing. The same future is reused on
  /// subsequent calls.
  static Future<void> initializeStaticResources() {
    _defaultEnvironmentMap = EnvironmentMap.studio();
    return gpuTextureFromAsset(
      'packages/flutter_scene/assets/ibl_brdf_lut.png',
    ).then((gpu.Texture value) {
      _brdfLutTexture = value;
    });
  }

  /// Constructs the appropriate concrete [Material] subclass for the
  /// supplied flatbuffer material description, resolving texture
  /// indices against [textures].
  static Material fromFlatbuffer(
    fb.Material fbMaterial,
    List<gpu.Texture> textures,
  ) {
    switch (fbMaterial.type) {
      case fb.MaterialType.kUnlit:
        return UnlitMaterial.fromFlatbuffer(fbMaterial, textures);
      case fb.MaterialType.kPhysicallyBased:
        return PhysicallyBasedMaterial.fromFlatbuffer(fbMaterial, textures);
      default:
        throw Exception('Unknown material type');
    }
  }

  gpu.Shader? _fragmentShader;

  /// The fragment shader used when rendering geometry with this material.
  ///
  /// Subclasses set this in their constructor (typically via
  /// [setFragmentShader]). Throws if accessed before a shader has been
  /// assigned.
  gpu.Shader get fragmentShader {
    if (_fragmentShader == null) {
      throw Exception('Fragment shader has not been set');
    }
    return _fragmentShader!;
  }

  /// Assigns the fragment [shader] used when this material is drawn.
  void setFragmentShader(gpu.Shader shader) {
    _fragmentShader = shader;
  }

  /// Binds this material's render-pass state, uniforms, and textures.
  ///
  /// The base implementation enables back-face culling with
  /// counter-clockwise winding (matching the glTF convention). Subclasses
  /// must call `super.bind` and then bind any per-material uniforms and
  /// textures expected by their fragment shader. [lighting] carries the
  /// [Scene]-level IBL [Environment] and analytic lights that materials
  /// shade against.
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(gpu.CullMode.backFace);
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
