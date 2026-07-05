import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/hot_reload/hot_reloadable_fmat.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';

/// A material driven by a `.fmat` custom-material shader and its sidecar
/// metadata (produced at build time by `buildMaterials`).
///
/// Construct one from a shader bundle entry and its metadata, then set
/// parameters by name through [parameters]:
///
/// ```dart
/// final library = (await gpu.loadShaderLibraryAsync('build/shaderbundles/materials.shaderbundle'))!;
/// final metadata = jsonDecode(await rootBundle.loadString(
///     'build/shaderbundles/materials.fmat.json')) as Map<String, Object?>;
/// final toon = PreprocessedMaterial(
///   fragmentShader: library['Toon']!,
///   metadata: (metadata['Toon'] as Map).cast<String, Object?>(),
/// )..parameters.setColor('base_color', const Color(0xff8844ff));
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
       _vertexShaders = vertexShaders,
       parameters = MaterialParameters.fromMetadata(fragmentShader, metadata) {
    setFragmentShader(fragmentShader);
  }

  /// The material's parameters, set by name. See [MaterialParameters].
  final MaterialParameters parameters;

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
    gpu.HostBuffer transientsBuffer,
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

  /// Whether the engine runs its lighting ([FmatShadingModel.lit]) or the
  /// shader's color is output directly ([FmatShadingModel.unlit]).
  FmatShadingModel get shadingModel => _shadingModel;

  FmatShadingModel _shadingModel;
  FmatBlending _blending;
  FmatCulling _culling;

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
    setFragmentShader(fragmentShader);
    parameters.updateFromMetadata(fragmentShader, metadata);
  }

  /// Per-material image-based-lighting environment, overriding the scene-wide
  /// environment when set. Only used for [FmatShadingModel.lit] materials.
  EnvironmentMap? environment;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(renderCullMode);
    pass.setWindingOrder(gpu.WindingOrder.counterClockwise);

    if (shadingModel == FmatShadingModel.lit) {
      final env = environment ?? lighting.environmentMap;
      final fragInfo = Float32List(EngineLightingUniforms.fragInfoFloatCount);
      EngineLightingUniforms.packInto(fragInfo, lighting, env);
      // radiance_blend.zw [162]/[163]: this item's punctual-light slice
      // (count, offset) into the per-frame light-index buffer.
      fragInfo[162] = lightListCount.toDouble();
      fragInfo[163] = lightListOffset.toDouble();
      pass.bindUniform(
        fragmentShader.getUniformSlot('FragInfo'),
        transientsBuffer.emplace(ByteData.sublistView(fragInfo)),
      );
      EngineLightingUniforms.bindEngineTextures(
        pass,
        fragmentShader,
        lighting,
        env,
      );
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
    // in the emitter) to zero. The generated fragment references MaterialParams
    // through it so the block is not optimized out when Surface() reads no
    // parameter; it is declared only when the material has such a block.
    if (parameters.hasUniformBlock) {
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
  gpu.CullMode get renderCullMode => _cullMode(_culling);
}

gpu.CullMode _cullMode(FmatCulling culling) => switch (culling) {
  FmatCulling.back => gpu.CullMode.backFace,
  FmatCulling.front => gpu.CullMode.frontFace,
  FmatCulling.none => gpu.CullMode.none,
};

FmatShadingModel _parseShadingModel(Object? value) =>
    value == 'unlit' ? FmatShadingModel.unlit : FmatShadingModel.lit;

FmatBlending _parseBlending(Object? value) =>
    value == 'alpha' ? FmatBlending.alpha : FmatBlending.opaque;

FmatCulling _parseCulling(Object? value) => switch (value) {
  'front' => FmatCulling.front,
  'none' => FmatCulling.none,
  _ => FmatCulling.back,
};
