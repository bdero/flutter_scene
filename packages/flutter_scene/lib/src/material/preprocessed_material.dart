import 'dart:typed_data';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/render/y_flip.dart';

/// A material driven by a `.fmat` custom-material shader and its sidecar
/// metadata (produced at build time by `buildMaterials`).
///
/// Construct one from a shader bundle entry and its metadata, then set
/// parameters by name through [parameters]:
///
/// ```dart
/// final library = gpu.ShaderLibrary.fromAsset('build/shaderbundles/materials.shaderbundle')!;
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
class PreprocessedMaterial extends Material {
  PreprocessedMaterial({
    required gpu.Shader fragmentShader,
    required Map<String, Object?> metadata,
  }) : shadingModel = _parseShadingModel(metadata['shading_model']),
       _blending = _parseBlending(metadata['blending']),
       _culling = _parseCulling(metadata['culling']),
       parameters = MaterialParameters.fromMetadata(fragmentShader, metadata) {
    setFragmentShader(fragmentShader);
  }

  /// The material's parameters, set by name. See [MaterialParameters].
  final MaterialParameters parameters;

  /// Whether the engine runs its lighting ([FmatShadingModel.lit]) or the
  /// shader's color is output directly ([FmatShadingModel.unlit]).
  final FmatShadingModel shadingModel;

  final FmatBlending _blending;
  final FmatCulling _culling;

  /// Per-material image-based-lighting environment, overriding the scene-wide
  /// environment when set. Only used for [FmatShadingModel.lit] materials.
  EnvironmentMap? environment;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    pass.setCullMode(_cullMode(_culling));
    pass.setWindingOrder(backendWinding(gpu.WindingOrder.counterClockwise));

    if (shadingModel == FmatShadingModel.lit) {
      final env = environment ?? lighting.environmentMap;
      final fragInfo = Float32List(EngineLightingUniforms.fragInfoFloatCount);
      EngineLightingUniforms.packInto(fragInfo, lighting, env);
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
    }

    parameters.bind(pass, fragmentShader, transientsBuffer);
  }

  @override
  bool isOpaque() => _blending == FmatBlending.opaque;
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
