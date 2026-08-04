import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/hot_reload/hot_reloadable_fmat.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

/// A material driven by a `.fmat` custom-material shader and its sidecar
/// metadata (produced at build time by `buildMaterials`).
///
/// Prefer `loadFmatMaterial`, which resolves the generated DataAssets by the
/// checked-in `.fmat` source path, then set parameters through [parameters]:
///
/// ```dart
/// final toon = await loadFmatMaterial('assets/toon.fmat');
/// toon.parameters.setColor('base_color', const Color(0xff8844ff));
/// ```
///
/// A `lit` material is lit by the engine's physically based pipeline (the
/// shader's `Surface()` fills the surface description); an `unlit` material
/// outputs its `base_color` directly. The render state (blending, culling)
/// comes from the material's metadata.
/// {@category Materials}
class PreprocessedMaterial extends Material implements HotReloadableFmat {
  PreprocessedMaterial({
    required gpu.Shader fragmentShader,
    required Map<String, Object?> metadata,
    Map<String, gpu.Shader>? vertexShaders,
  }) : _shadingModel = _parseShadingModel(metadata['shading_model']),
       _blending = _parseBlending(metadata['blending']),
       _culling = _parseCulling(metadata['culling']),
       _depthWrite = metadata['depth_write'] == true,
       _sceneInputs = _parseSceneInputs(metadata['engine_inputs']),
       _vertexShaders = vertexShaders,
       parameters = MaterialParameters.fromMetadata(fragmentShader, metadata) {
    setFragmentShader(fragmentShader);
  }

  /// Parses the sidecar's `engine_inputs` list into requested render inputs.
  static Set<RenderInput> _parseSceneInputs(Object? value) {
    if (value is! List) return const {};
    final inputs = <RenderInput>{};
    for (final entry in value) {
      switch (entry) {
        case 'scene_color':
          inputs.add(RenderInput.opaqueSceneColor);
        case 'filtered_scene_color':
          inputs.add(RenderInput.filteredSceneColor);
        case 'scene_depth':
          inputs.add(RenderInput.depth);
      }
    }
    return inputs;
  }

  Set<RenderInput> _sceneInputs;

  static final Float32List _fragInfoScratch = Float32List(
    EngineLightingUniforms.fragInfoFloatCount,
  );
  static final ByteData _fragInfoBytes = ByteData.sublistView(_fragInfoScratch);

  @override
  Set<RenderInput> get sceneInputs => _sceneInputs;

  /// The material's parameters, set by name. See [MaterialParameters].
  final MaterialParameters parameters;

  TextureSource? _depthMaskTexture;
  TextureTransform _depthMaskTransform = TextureTransform();
  double _depthMaskCutoff = 0.5;
  double _depthMaskAlpha = 1.0;
  int _depthMaskTexCoord = 0;

  /// Configures cutout coverage for the camera-depth and shadow passes.
  ///
  /// Call with null [texture] to disable masked depth. The color shader must
  /// apply the same cutoff to produce matching coverage.
  @protected
  void configureDepthAlphaMask({
    required TextureSource? texture,
    TextureTransform? transform,
    int texCoord = 0,
    double cutoff = 0.5,
    double alpha = 1.0,
  }) {
    _depthMaskTexture = texture;
    _depthMaskTransform = transform ?? TextureTransform();
    _depthMaskTexCoord = texCoord.clamp(0, 1);
    _depthMaskCutoff = cutoff;
    _depthMaskAlpha = alpha;
  }

  /// The generated vertex shaders for a `vertex { }` material, keyed by the
  /// variant the geometry selects (`'unskinned'`, `'skinned'`, `'depth'`), or
  /// null when the material does not customize the vertex stage. Resolved by
  /// the loader from the sidecar's `vertex` map and the shader bundle.
  final Map<String, gpu.Shader>? _vertexShaders;

  @override
  gpu.Shader? materialVertexShader(String variant) => _vertexShaders?[variant];

  // 16 zero bytes (a std140 vec4) for the VertexKeepAlive block below.
  static final ByteData _zeroKeepAlive = ByteData(16);

  @override
  void bindVertexStage(
    gpu.RenderPass pass,
    gpu.Shader vertexShader,
    TransientWriter transientsBuffer,
  ) {
    // The generated vertex variant declares the same MaterialParams block as
    // the fragment shader, so a parameter reads the same value in both stages.
    // The variant's keep-alive references the block (see
    // MATERIAL_PARAMS_KEEP_ALIVE in the emitter) so it survives compilation
    // even when Vertex() reads no parameter; binding an optimized-out block
    // crashes the Metal backend.
    parameters.bindUniformBlock(pass, vertexShader, transientsBuffer);
    // Bind the keep-alive block (name must match kVertexKeepAliveBlock in the
    // emitter) to zero: the generated shader multiplies the mesh inputs by it
    // so the optimizer cannot strip a declared attribute when a Vertex() hook
    // replaces the outputs, and zero makes it invisible.
    pass.bindUniform(
      vertexShader.getUniformSlot('VertexKeepAlive'),
      transientsBuffer.emplace(_zeroKeepAlive),
    );
  }

  /// The engine shading model used by this material.
  FmatShadingModel get shadingModel => _shadingModel;

  FmatShadingModel _shadingModel;
  FmatBlending _blending;
  FmatCulling _culling;
  bool _depthWrite;

  /// Re-reads the render state and parameters from a regenerated [fragmentShader]
  /// and sidecar [metadata] (a hot-reloaded `.fmat`), in place.
  ///
  /// Updates culling, blending, shading model, and the parameter layout without
  /// replacing the material instance, so every primitive already using it picks
  /// up the change. Explicitly-set parameter values are preserved; see
  /// [MaterialParameters.updateFromMetadata].
  @override
  void updateFromMetadata(
    gpu.Shader fragmentShader,
    Map<String, Object?> metadata,
  ) {
    _shadingModel = _parseShadingModel(metadata['shading_model']);
    _blending = _parseBlending(metadata['blending']);
    _culling = _parseCulling(metadata['culling']);
    _depthWrite = metadata['depth_write'] == true;
    _sceneInputs = _parseSceneInputs(metadata['engine_inputs']);
    markMaterialSceneInputsChanged();
    setFragmentShader(fragmentShader);
    parameters.updateFromMetadata(fragmentShader, metadata);
  }

  /// Per-material image-based-lighting environment, overriding the scene-wide
  /// environment when set. Only used for [FmatShadingModel.lit] materials.
  EnvironmentMap? environment;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(renderCullMode);
    pass.setWindingOrder(gpu.WindingOrder.counterClockwise);

    if (shadingModel != FmatShadingModel.unlit) {
      final env = environment ?? lighting.environmentMap;
      final fragInfo = _fragInfoScratch
        ..fillRange(0, _fragInfoScratch.length, 0);
      EngineLightingUniforms.packInto(fragInfo, lighting, env);
      // radiance_blend.zw [162]/[163]: this item's punctual-light slice
      // (count, offset) into the per-frame light-index buffer.
      fragInfo[162] = lightListCount.toDouble();
      fragInfo[163] = lightListOffset.toDouble();
      pass.bindUniform(
        fragmentShader.getUniformSlot('FragInfo'),
        transientsBuffer.emplace(_fragInfoBytes),
      );
      // TODO(material-permutations): add an SSAO sampler to filtered scene
      // color permutations without exceeding the backend sampler limit.
      EngineLightingUniforms.bindEngineTextures(
        pass,
        fragmentShader,
        lighting,
        env,
        bindSsao: !_sceneInputs.contains(RenderInput.filteredSceneColor),
      );
      if (_sceneInputs.isNotEmpty) {
        EngineLightingUniforms.bindSceneInputTextures(
          pass,
          fragmentShader,
          lighting,
          _sceneInputs,
        );
      }
      // Lit `.fmat` shaders include the lighting framework (and thus fog.glsl),
      // so they carry the FogInfo block. Unlit `.fmat` shaders do not; fog on
      // those is a TODO(fog): give the unlit `.fmat` template the fog block.
      EngineLightingUniforms.bindFog(
        pass,
        fragmentShader,
        transientsBuffer,
        lighting,
      );
    }

    parameters.bind(pass, fragmentShader, transientsBuffer);
    // Bind the fragment keep-alive block (name matches kFragmentKeepAliveBlock
    // in the emitter) to zero. The generated fragment references every
    // declared parameter resource through it (the MaterialParams block and
    // any unreferenced samplers) so none can be optimized out; the emitter
    // declares it whenever the material has any parameter.
    if (parameters.hasAnyParameters) {
      pass.bindUniform(
        fragmentShader.getUniformSlot('FragmentKeepAlive'),
        transientsBuffer.emplace(_zeroKeepAlive),
      );
    }
  }

  @override
  bool isOpaque() => _blending == FmatBlending.opaque;

  @override
  @internal
  bool get depthAlphaMasked => _depthMaskTexture != null;

  static final gpu.SamplerOptions _depthMaskSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    mipFilter: gpu.MipFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.repeat,
  );

  @override
  @internal
  void bindDepthAlphaMask(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {
    final transform = _depthMaskTransform;
    final rotation = transform.rotation;
    final values = Float32List(12)
      ..[0] = _depthMaskCutoff
      ..[1] = _depthMaskAlpha
      ..[2] = 1.0
      ..[4] = transform.offset.x
      ..[5] = transform.offset.y
      ..[6] = transform.scale.x
      ..[7] = transform.scale.y
      ..[8] = math.cos(rotation)
      ..[9] = math.sin(rotation)
      ..[10] = _depthMaskTexCoord.toDouble();
    pass.bindUniform(
      shader.getUniformSlot('MaskInfo'),
      transientsBuffer.emplace(ByteData.sublistView(values)),
    );
    final source = _depthMaskTexture;
    pass.bindTexture(
      shader.getUniformSlot('mask_texture'),
      Material.whitePlaceholder(resolveTextureSource(source)),
      sampler: textureSourceSampler(source) ?? _depthMaskSampler,
    );
  }

  @override
  @internal
  gpu.CullMode get renderCullMode {
    // Translucent double-sided surfaces keep one face per draw so depth
    // sorting remains stable.
    // TODO(translucent-sorting): emit and sort front/back surface draws
    // independently, then disable culling for double-sided materials.
    if (_culling == FmatCulling.back && doubleSided && isOpaque()) {
      return gpu.CullMode.none;
    }
    return _cullMode(_culling);
  }

  @override
  @internal
  bool get translucentDepthWrite => _depthWrite;
}

gpu.CullMode _cullMode(FmatCulling culling) => switch (culling) {
  FmatCulling.back => gpu.CullMode.backFace,
  FmatCulling.front => gpu.CullMode.frontFace,
  FmatCulling.none => gpu.CullMode.none,
};

FmatShadingModel _parseShadingModel(Object? value) => switch (value) {
  'unlit' => FmatShadingModel.unlit,
  'physical' => FmatShadingModel.physical,
  _ => FmatShadingModel.lit,
};

FmatBlending _parseBlending(Object? value) =>
    value == 'alpha' ? FmatBlending.alpha : FmatBlending.opaque;

FmatCulling _parseCulling(Object? value) => switch (value) {
  'front' => FmatCulling.front,
  'none' => FmatCulling.none,
  _ => FmatCulling.back,
};
