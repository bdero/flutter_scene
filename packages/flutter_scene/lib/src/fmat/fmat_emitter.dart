// Emits standard GLSL and a metadata sidecar from a parsed [FmatMaterial].
//
// The emitted fragment shader composes the engine framework includes, a
// generated `MaterialParams` uniform block plus sampler declarations, the
// author's verbatim `Surface()` body, and a generated `main()`. The sidecar
// records each parameter's type, default, and hint so the runtime can offer
// type-checked, name-based parameter setting (offsets come from shader
// reflection at load time; the sidecar supplies the types reflection does not
// expose).

import 'package:flutter_scene/src/fmat/fmat_ast.dart';

/// The GLSL uniform block name the runtime binds custom parameters through.
const String kMaterialParamsBlock = 'MaterialParams';

/// The GLES-fold-safe instance name for [kMaterialParamsBlock].
const String kMaterialParamsInstance = 'material_params';

/// The uniform block a generated vertex variant declares to keep the mesh
/// vertex inputs live (see the body includes). The runtime binds it to zero,
/// so it has no effect; it exists only so the optimizer cannot strip a
/// declared vertex attribute when a `Vertex()` hook fully replaces the stage
/// outputs (which would break shader reflection).
const String kVertexKeepAliveBlock = 'VertexKeepAlive';

/// The GLES-fold-safe instance name for [kVertexKeepAliveBlock].
const String kVertexKeepAliveInstance = 'vertex_keep_alive';

/// The uniform block a generated fragment declares to keep the `MaterialParams`
/// block live when `Surface()` reads no parameter (e.g. a material whose
/// parameters are used only in its `Vertex()` stage). The runtime binds it to
/// zero, so it has no effect; without it the optimizer strips the unreferenced
/// block, its uniform slot is then absent, and binding the parameters crashes
/// the Metal backend.
const String kFragmentKeepAliveBlock = 'FragmentKeepAlive';

/// The GLES-fold-safe instance name for [kFragmentKeepAliveBlock].
const String kFragmentKeepAliveInstance = 'fragment_keep_alive';

/// The framework varying schema version recorded in sidecars. Bumped whenever
/// standard varyings in material_varyings.glsl or material_vertex.glsl change.
const int kFrameworkVaryingSchemaVersion = 2;

/// The engine vertex variants a material with a `vertex { }` block generates a
/// shader for, mapping the sidecar key the runtime selects by to the shared
/// body include that variant reuses. The keys correspond to the geometry a
/// draw uses: `unskinned` for static meshes, `skinned` for skinned meshes, and
/// `depth` for the position-only shadow-map / depth-prepass pass.
const Map<String, String> kVertexVariants = <String, String>{
  'unskinned': 'flutter_scene_unskinned_body.glsl',
  'skinned': 'flutter_scene_skinned_body.glsl',
  'depth': 'flutter_scene_unskinned_depth_body.glsl',
};

const Map<String, String> _vertexVariantEntrySuffix = <String, String>{
  'unskinned': 'UnskinnedVertex',
  'skinned': 'SkinnedVertex',
  'depth': 'UnskinnedDepthVertex',
};

/// The shader-bundle entry name for [material]'s [variant] vertex shader (one
/// of the keys in [kVertexVariants]).
String vertexVariantEntryName(FmatMaterial material, String variant) =>
    '${material.name}${_vertexVariantEntrySuffix[variant]}';

/// Writes the custom-varying declarations for [material] into [sb], as `in`
/// (fragment stage) or `out` (vertex stage). They are matched across stages by
/// name, like the engine's standard `v_*` varyings.
void _writeVaryings(StringBuffer sb, FmatMaterial material, String direction) {
  if (material.varyings.isEmpty) return;
  sb.writeln('// Custom interpolants (vertex Vertex() -> fragment Surface()).');
  for (final v in material.varyings) {
    sb.writeln('$direction ${v.type.glslType} ${v.name};');
  }
  sb.writeln();
}

/// The instance attributes [material]'s fragment stage reads, in declared
/// order. Only these get an interpolant, so a material whose attributes drive
/// the vertex stage alone pays no varying slots. The whole-word check errs
/// toward forwarding when unsure, which costs a slot rather than a compile
/// error.
List<FmatInstanceAttribute> forwardedInstanceAttributes(FmatMaterial material) {
  if (material.instanceAttributes.isEmpty) return const [];
  return [
    for (final a in material.instanceAttributes)
      if (RegExp(
        '\\b${RegExp.escape(a.accessorName)}\\b',
      ).hasMatch(material.fragmentSource))
        a,
  ];
}

/// Writes the fragment stage's instance-attribute interpolants and accessors
/// into [sb]. `Surface()` reads each attribute through `GetInstance<Name>()`,
/// matching how it reads every other engine input.
void _writeInstanceAccessors(StringBuffer sb, FmatMaterial material) {
  final forwarded = forwardedInstanceAttributes(material);
  if (forwarded.isEmpty) return;
  sb.writeln('// Per-instance attributes forwarded by the vertex stage.');
  for (final a in forwarded) {
    sb.writeln('in ${a.type.glslType} ${a.varyingName};');
  }
  for (final a in forwarded) {
    sb.writeln(
      '${a.type.glslType} ${a.accessorName}() { return ${a.varyingName}; }',
    );
  }
  sb.writeln();
}

/// Emits the fragment shader GLSL for [material].
///
/// [defines] are written after the generated-file banner and before framework
/// includes.
/// Selects the cubemap prefiltered-radiance layout. Only the selected
/// layout's sampler is declared, so a material that samples the environment
/// ships one entry per layout and the runtime picks the one matching the
/// bound environment.
///
/// This doubles the entries a material that samples the environment
/// contributes. TODO(radiance-layout): remove it with the define in
/// `texture.glsl` once the engine's combined-limit validation is in every
/// supported stable, which halves those entries again.
const String kRadianceCubeDefine = 'FLUTTER_SCENE_RADIANCE_CUBE';

/// Whether [material] declares the prefiltered-radiance sampler, and so needs
/// an entry per radiance layout. A shadow catcher never samples the
/// environment (its generated `main()` skips `EvaluateLighting`, so the
/// radiance samplers are compiled out), so it ships no cube twin.
bool materialSamplesEnvironment(FmatMaterial material) =>
    switch (material.shadingModel) {
      FmatShadingModel.unlit ||
      FmatShadingModel.shadowCatcher => material.useEnvironment,
      _ => true,
    };

/// The bundle entry name of [entryName]'s cubemap-radiance twin.
String radianceCubeEntryName(String entryName) => '${entryName}Cube';

/// Declares the baked-lightmap sampler and swaps the SH diffuse ambient for
/// it. The sampler exists only in these entries, and it displaces
/// `sh_coefficients` rather than extending the sampler set, so a lightmap
/// entry costs the same texture units as its plain twin.
///
/// This doubles the entries of every material it is generated for, so it is
/// generated only where a lightmap is expected (see
/// `buildBundledPhysicalMaterials`).
///
/// TODO(lightmap-fmat): let a user `.fmat` opt into the axis (a declared
/// feature, so a material that wants a bake pays the entries and the rest do
/// not), which needs a runtime path to set the slot on a
/// `PreprocessedMaterial`.
const String kLightmapDefine = 'FLUTTER_SCENE_LIGHTMAP';

/// The bundle entry name of [entryName]'s baked-lightmap twin.
String lightmapEntryName(String entryName) => '${entryName}Lightmap';

/// Whether the material described by sidecar [metadata] samples the
/// environment, and so ships a [radianceCubeEntryName] twin.
bool sidecarSamplesEnvironment(Map<String, Object?> metadata) =>
    switch (metadata['shading_model']) {
      'unlit' || 'shadowCatcher' => metadata['use_environment'] == true,
      _ => true,
    };

String emitFragmentGlsl(
  FmatMaterial material, {
  Iterable<String> defines = const [],
}) {
  if (material.domain == FmatDomain.sky) {
    return _emitSkyGlsl(material, defines: defines);
  }
  final sb = StringBuffer();
  final lit = material.shadingModel != FmatShadingModel.unlit;

  sb.writeln(
    '// Generated from a .fmat material by flutter_scene. '
    'Do not edit.',
  );
  for (final define in defines) {
    sb.writeln('#define $define');
  }
  if (material.shadingModel == FmatShadingModel.physical) {
    sb.writeln('#define FLUTTER_SCENE_PHYSICAL_MATERIAL');
  }
  if (material.shadingModel == FmatShadingModel.shadowCatcher) {
    sb.writeln('#define FLUTTER_SCENE_SHADOW_CATCHER');
  }
  if (material.engineInputs.contains('filtered_scene_color')) {
    sb.writeln('#define FLUTTER_SCENE_SKIP_SSAO');
  }
  sb.writeln('#include <material_varyings.glsl>');
  sb.writeln('#include <pbr.glsl>');
  if (material.shadingModel != FmatShadingModel.shadowCatcher) {
    sb.writeln('#include <texture.glsl>');
  }
  sb.writeln('#include <normals.glsl>');
  sb.writeln('#include <material_inputs.glsl>');
  if (material.shadingModel == FmatShadingModel.shadowCatcher) {
    // The catcher samples the shadow atlas and occlusion chain but never
    // evaluates the lighting, so it takes the engine bindings plus the
    // sampling utilities without the full framework (whose dead code would
    // keep the image-based-lighting samplers in the binding surface).
    sb.writeln('#include <material_engine_lighting.glsl>');
    sb.writeln('#include <material_shadow_sampling.glsl>');
  } else if (lit) {
    sb.writeln('#include <material_engine_lighting.glsl>');
    sb.writeln('#include <material_lighting.glsl>');
  }
  sb.writeln();

  // Custom interpolants the vertex stage wrote, read by name in Surface().
  _writeVaryings(sb, material, 'in');
  _writeInstanceAccessors(sb, material);

  final uniforms = material.uniformParameters.toList();
  final samplers = material.samplerParameters.toList();
  if (uniforms.isNotEmpty) {
    sb.writeln('uniform $kMaterialParamsBlock {');
    for (final p in uniforms) {
      sb.writeln('  ${p.type.glslType} ${p.name};');
    }
    sb.writeln('}');
    sb.writeln('$kMaterialParamsInstance;');
    sb.writeln();
  }
  if (uniforms.isNotEmpty || samplers.isNotEmpty) {
    // Bound to zero by the runtime; main() folds the parameters into a term
    // multiplied by it so no declared parameter resource can be optimized out
    // (the runtime binds them all unconditionally, and binding an
    // optimized-out uniform or sampler is unsafe).
    sb.writeln('uniform $kFragmentKeepAliveBlock { vec4 keep_alive; }');
    sb.writeln('$kFragmentKeepAliveInstance;');
    sb.writeln();
  }

  for (final p in samplers) {
    sb.writeln('uniform ${p.type.glslType} ${p.name};');
  }
  if (samplers.isNotEmpty) sb.writeln();

  // Engine scene-input samplers and accessors, only for materials that
  // declared them (the lit framework sits near Metal's 16-sampler ceiling,
  // so these must never be unconditional). The gates and screen-UV helpers
  // ride the engine lighting block (scene_inputs / ssao_params.zw).
  if (material.engineInputs.contains('scene_color')) {
    sb.writeln('// The accumulated scene color behind this draw (linear HDR).');
    sb.writeln('uniform sampler2D scene_opaque_color;');
    sb.writeln('// Samples the composed scene behind this fragment, offset in');
    sb.writeln('// screen UV (pass vec2(0.0) for no distortion). Returns the');
    sb.writeln("// fragment's own black when the snapshot is unavailable.");
    sb.writeln('vec3 GetSceneColor(vec2 uv_offset) {');
    sb.writeln('  if (frag_info.scene_inputs.x < 0.5) return vec3(0.0);');
    sb.writeln(
      '  vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), '
      'vec2(0.999));',
    );
    sb.writeln('  return texture(scene_opaque_color, uv).rgb;');
    sb.writeln('}');
    sb.writeln();
  }
  if (material.engineInputs.contains('filtered_scene_color')) {
    sb.writeln('#include <filtered_scene_color.glsl>');
    sb.writeln();
  }
  if (material.engineInputs.contains('scene_depth')) {
    sb.writeln('// The opaque linear (planar view-space) depth, world units.');
    sb.writeln('uniform sampler2D scene_depth;');
    sb.writeln('// The opaque depth behind this fragment, offset in screen');
    sb.writeln('// UV. Returns a huge depth when unavailable, so');
    sb.writeln('// depth-difference effects fade out instead of popping.');
    sb.writeln('float GetSceneDepth(vec2 uv_offset) {');
    sb.writeln('  if (frag_info.scene_inputs.y < 0.5) return 1.0e8;');
    sb.writeln(
      '  vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), '
      'vec2(0.999));',
    );
    sb.writeln('  return texture(scene_depth, uv).r;');
    sb.writeln('}');
    sb.writeln();
  }
  if (material.engineInputs.contains('planar_reflection')) {
    sb.writeln("// This surface's planar reflection capture (linear HDR),");
    sb.writeln('// with the view-projection that rendered it.');
    sb.writeln('uniform sampler2D planar_reflection;');
    sb.writeln('uniform PlanarReflectionInfo {');
    sb.writeln('  mat4 view_projection;');
    sb.writeln('  vec4 params; // x: a capture is bound this draw');
    sb.writeln('}');
    sb.writeln('planar_reflection_info;');
    sb.writeln('// The mirrored scene color reflected at this fragment. a is');
    sb.writeln('// 1 when a capture is bound this draw and 0 otherwise (no');
    sb.writeln('// reflector routed one, or the draw is inside a capture);');
    sb.writeln('// fall back to the environment reflection at a == 0.');
    sb.writeln('vec4 GetPlanarReflection() {');
    sb.writeln('  if (planar_reflection_info.params.x < 0.5) {');
    sb.writeln('    return vec4(0.0);');
    sb.writeln('  }');
    sb.writeln('  vec4 clip = planar_reflection_info.view_projection *');
    sb.writeln('      vec4(GetWorldPosition(), 1.0);');
    sb.writeln('  if (clip.w <= 0.0) {');
    sb.writeln('    return vec4(0.0);');
    sb.writeln('  }');
    sb.writeln('  vec2 uv = vec2(0.5 + 0.5 * clip.x / clip.w,');
    sb.writeln('                 0.5 - 0.5 * clip.y / clip.w);');
    sb.writeln('  uv = clamp(uv, vec2(0.001), vec2(0.999));');
    sb.writeln('  return vec4(texture(planar_reflection, uv).rgb, 1.0);');
    sb.writeln('}');
    sb.writeln();
  }

  // Map compiler errors in the author's code back to the .fmat source line.
  sb.writeln('#line ${material.fragmentSourceLine}');
  sb.write(material.fragmentSource);
  if (!material.fragmentSource.endsWith('\n')) sb.writeln();
  sb.writeln();

  sb.writeln('void main() {');
  sb.writeln('  MaterialInputs material = InitMaterialInputs();');
  sb.writeln('  Surface(material);');
  final keepAlive = _fragmentKeepAliveTerm(material, uniforms, samplers);
  if (keepAlive != null) {
    sb.writeln(
      '  material.base_color.r += '
      '$kFragmentKeepAliveInstance.keep_alive.x * $keepAlive;',
    );
  }
  if (material.shadingModel == FmatShadingModel.shadowCatcher) {
    sb.writeln(
      '  // Shadow catcher: the surface color is the composed overlay,',
    );
    sb.writeln('  // output premultiplied without running the lighting.');
    sb.writeln(
      '  frag_color = vec4(material.base_color.rgb, 1.0) * '
      'material.base_color.a;',
    );
  } else if (lit) {
    sb.writeln('  frag_color = EvaluateLighting(material);');
  } else {
    sb.writeln('  // Unlit: output the surface color, premultiplied by alpha.');
    sb.writeln(
      '  frag_color = vec4(material.base_color.rgb, 1.0) * '
      'material.base_color.a;',
    );
  }
  sb.writeln('}');

  return sb.toString();
}

/// A scalar GLSL expression reading one component of [p] through the
/// MaterialParams instance. Both stages fold it into their zero-bound
/// keep-alive term so the optimizer cannot strip the block when the author's
/// code reads no parameter (the runtime binds it unconditionally, and binding
/// an optimized-out block is unsafe).
String _paramsKeepAliveScalar(FmatParameter p) {
  final member = '$kMaterialParamsInstance.${p.name}';
  return switch (p.type) {
    FmatType.float_ => member,
    FmatType.int_ => 'float($member)',
    FmatType.mat4 => '$member[0].x',
    _ => '$member.x',
  };
}

/// The scalar keep-alive term for a fragment (or sky) shader, or null when
/// the material declares no parameters (no keep-alive block is emitted then).
///
/// Folds in a MaterialParams read plus a zero-multiplied fetch of every
/// sampler [source] never mentions, so the runtime can bind every declared
/// parameter resource safely. Samplers the author's code references are
/// skipped (their real fetch keeps them live and they pay nothing here);
/// the whole-word check errs toward the extra fetch when unsure.
String? _fragmentKeepAliveTerm(
  FmatMaterial material,
  List<FmatParameter> uniforms,
  List<FmatParameter> samplers,
) {
  if (uniforms.isEmpty && samplers.isEmpty) return null;
  final terms = <String>[
    if (uniforms.isNotEmpty) _paramsKeepAliveScalar(uniforms.first),
    for (final p in samplers)
      if (!RegExp(
        '\\b${RegExp.escape(p.name)}\\b',
      ).hasMatch(material.fragmentSource))
        p.type == FmatType.samplerCube
            ? 'texture(${p.name}, vec3(0.0, 0.0, 1.0)).x'
            : 'texture(${p.name}, vec2(0.0)).x',
  ];
  // Every declared resource is already referenced; the block still needs a
  // live operand of its own so it cannot be folded away.
  if (terms.isEmpty) {
    return '$kFragmentKeepAliveInstance.keep_alive.y';
  }
  return '(${terms.join(' + ')})';
}

/// Emits the vertex-shader GLSL for each variant of [material], keyed by the
/// shader-bundle entry name. Empty when the material has no `vertex { }` block
/// (the draw then uses the engine's standard vertex shader for its geometry).
///
/// Each variant declares the shared `MaterialParams` block (so a parameter is
/// readable in both stages), splices the author's `Vertex()` after the
/// `VertexInputs` struct, and `#include`s the engine body for its mesh type,
/// which builds the struct, calls `Vertex()`, and writes the stage outputs.
Map<String, String> emitVertexGlsl(FmatMaterial material) {
  if (!material.hasVertexStage) return const <String, String>{};
  final result = <String, String>{};
  kVertexVariants.forEach((variant, bodyInclude) {
    result[vertexVariantEntryName(material, variant)] = _emitVertexVariant(
      material,
      bodyInclude,
      isDepth: variant == 'depth',
      // Only the unskinned color variant fetches the instance-rate slot the
      // custom attributes ride in; the skinned variant takes its transform
      // from FrameInfo and the depth variant binds a transform-only buffer.
      fetchesInstanceAttributes: variant == 'unskinned',
    );
  });
  return result;
}

/// The GLSL zero literal for a varying/attribute [type].
String _zeroLiteral(FmatType type) =>
    type == FmatType.float_ ? '0.0' : '${type.glslType}(0.0)';

/// Writes a vertex variant's custom-attribute declarations into [sb]. In the
/// color variants they are real vertex `in`s (bound from the mesh's streams by
/// name); in the depth variant, which fetches only position, they are
/// zero-initialized globals so the author's `Vertex()` still compiles.
void _writeAttributes(
  StringBuffer sb,
  FmatMaterial material, {
  required bool isDepth,
}) {
  if (material.attributes.isEmpty) return;
  if (isDepth) {
    sb.writeln(
      '// Custom vertex attributes are not fetched in the depth pass; they '
      'read',
    );
    sb.writeln('// zero here (attribute-driven displacement does not shadow).');
    for (final a in material.attributes) {
      sb.writeln('${a.type.glslType} ${a.name} = ${_zeroLiteral(a.type)};');
    }
  } else {
    sb.writeln('// Custom per-vertex attributes supplied by the mesh.');
    for (final a in material.attributes) {
      sb.writeln('in ${a.type.glslType} ${a.name};');
    }
  }
  sb.writeln();
}

/// Writes a vertex variant's instance-attribute declarations into [sb]. The
/// unskinned color variant reads them from the instance-rate slot; the other
/// variants never bind that data, so they read zero (an attribute-driven
/// displacement does not shadow, matching custom vertex attributes).
void _writeInstanceAttributes(
  StringBuffer sb,
  FmatMaterial material, {
  required bool fetchesInstanceAttributes,
}) {
  if (material.instanceAttributes.isEmpty) return;
  if (fetchesInstanceAttributes) {
    sb.writeln('// Custom per-instance attributes (instance-rate slot).');
    for (final a in material.instanceAttributes) {
      sb.writeln('in ${a.type.glslType} ${a.inputName};');
    }
  } else {
    sb.writeln('// This variant binds no per-instance attribute data; they');
    sb.writeln('// read zero here.');
    // TODO(instance-attributes-skinned): a skinned mesh takes its transform
    // from FrameInfo and binds no instance-rate slot, so instancing it means
    // giving it one before these can carry real values.
    for (final a in material.instanceAttributes) {
      sb.writeln(
        '${a.type.glslType} ${a.inputName} = ${_zeroLiteral(a.type)};',
      );
    }
  }
  final forwarded = forwardedInstanceAttributes(material);
  for (final a in forwarded) {
    sb.writeln('out ${a.type.glslType} ${a.varyingName};');
  }
  if (forwarded.isNotEmpty) {
    // The body include invokes this after writing the stage outputs, so the
    // fragment accessors see the drawn instance's values.
    final assignments = forwarded
        .map((a) => '${a.varyingName} = ${a.inputName};')
        .join(' ');
    sb.writeln('#define MATERIAL_INSTANCE_VARYINGS $assignments');
  }
  sb.writeln();
}

String _emitVertexVariant(
  FmatMaterial material,
  String bodyInclude, {
  required bool isDepth,
  required bool fetchesInstanceAttributes,
}) {
  final sb = StringBuffer();
  sb.writeln(
    '// Generated from a .fmat material by flutter_scene. Do not edit.',
  );

  final uniforms = material.uniformParameters.toList();
  if (uniforms.isNotEmpty) {
    // The same block the fragment stage declares; the runtime binds the packed
    // bytes to both stages so `material_params.<name>` reads the same value in
    // Vertex() as in Surface().
    sb.writeln('uniform $kMaterialParamsBlock {');
    for (final p in uniforms) {
      sb.writeln('  ${p.type.glslType} ${p.name};');
    }
    sb.writeln('}');
    sb.writeln('$kMaterialParamsInstance;');
    sb.writeln();
    // The body include folds this into the zero-bound keep-alive so the block
    // survives even when Vertex() reads no parameter; the runtime binds it to
    // both stages unconditionally, and binding an optimized-out block crashes
    // the Metal backend.
    sb.writeln(
      '#define MATERIAL_PARAMS_KEEP_ALIVE '
      '(${_paramsKeepAliveScalar(uniforms.first)})',
    );
    sb.writeln();
  }

  // Bound to zero by the runtime; the body include multiplies the mesh inputs
  // by it so a hook that fully replaces the outputs cannot strip a declared
  // vertex attribute (which would break shader reflection).
  sb.writeln('uniform $kVertexKeepAliveBlock { vec4 keep_alive; }');
  sb.writeln('$kVertexKeepAliveInstance;');
  sb.writeln();

  // The material supplies its own Vertex(), so suppress the no-op hook in
  // material_vertex.glsl.
  sb.writeln('#define HAS_MATERIAL_VERTEX');
  sb.writeln('#include <material_vertex.glsl>');
  sb.writeln();

  // Custom per-vertex attributes Vertex() reads by name (real inputs in the
  // color variants, zero in the depth variant).
  _writeAttributes(sb, material, isDepth: isDepth);
  _writeInstanceAttributes(
    sb,
    material,
    fetchesInstanceAttributes: fetchesInstanceAttributes,
  );
  // Folded into the zero-bound keep-alive by the body include so an attribute
  // Vertex() never reads survives compilation; the geometry supplies its
  // buffer unconditionally and a stripped input breaks reflection and the
  // pipeline's vertex layout. The instance-rate inputs join it only in the
  // variant that actually declares them as inputs.
  final keepAliveTerms = <String>[
    for (final a in material.attributes)
      a.type == FmatType.float_ ? a.name : '${a.name}.x',
    if (fetchesInstanceAttributes)
      for (final a in material.instanceAttributes)
        a.type == FmatType.float_ ? a.inputName : '${a.inputName}.x',
  ];
  if (keepAliveTerms.isNotEmpty) {
    sb.writeln(
      '#define MATERIAL_ATTRIBUTES_KEEP_ALIVE (${keepAliveTerms.join(' + ')})',
    );
    sb.writeln();
  }

  // Custom interpolants Vertex() writes by name, read in the fragment stage.
  _writeVaryings(sb, material, 'out');

  // Map compiler errors in the author's code back to the .fmat source line.
  sb.writeln('#line ${material.vertexSourceLine}');
  sb.write(material.vertexSource);
  if (!material.vertexSource!.endsWith('\n')) sb.writeln();
  sb.writeln();

  // The engine body for this mesh type builds VertexInputs, calls Vertex(),
  // and writes the stage outputs.
  sb.writeln('#include <$bodyInclude>');
  return sb.toString();
}

/// Emits the full-screen sky fragment GLSL for a `sky { }` material.
///
/// The engine's sky vertex shader supplies the world view direction as
/// `v_ray`; the generated `main()` calls the author's `Sky()` and outputs
/// linear HDR radiance with premultiplied alpha.
String _emitSkyGlsl(
  FmatMaterial material, {
  required Iterable<String> defines,
}) {
  final sb = StringBuffer();
  sb.writeln('// Generated from a .fmat sky by flutter_scene. Do not edit.');
  for (final define in defines) {
    sb.writeln('#define $define');
  }
  sb.writeln('#include <pbr.glsl>');
  sb.writeln('#include <texture.glsl>');
  sb.writeln();

  final uniforms = material.uniformParameters.toList();
  final samplers = material.samplerParameters.toList();
  if (uniforms.isNotEmpty) {
    sb.writeln('uniform $kMaterialParamsBlock {');
    for (final p in uniforms) {
      sb.writeln('  ${p.type.glslType} ${p.name};');
    }
    sb.writeln('}');
    sb.writeln('$kMaterialParamsInstance;');
    sb.writeln();
  }
  if (uniforms.isNotEmpty || samplers.isNotEmpty || material.useEnvironment) {
    // Same keep-alive as the surface fragment shader; see
    // _fragmentKeepAliveTerm.
    sb.writeln('uniform $kFragmentKeepAliveBlock { vec4 keep_alive; }');
    sb.writeln('$kFragmentKeepAliveInstance;');
    sb.writeln();
  }

  for (final p in samplers) {
    sb.writeln('uniform ${p.type.glslType} ${p.name};');
  }
  if (samplers.isNotEmpty) sb.writeln();

  if (material.useEnvironment) {
    sb.writeln(
      '// The environment\'s prefiltered radiance, bound by the engine in',
    );
    sb.writeln(
      '// whichever layout it uses (2D equirect or cube). Sample through',
    );
    sb.writeln('// SampleEnvironment(direction, roughness).');
    sb.writeln('uniform RadianceSampler prefiltered_radiance;');
    sb.writeln();
    sb.writeln('vec3 SampleEnvironment(vec3 direction, float roughness) {');
    sb.writeln(
      '  return SampleRadianceEnv(prefiltered_radiance, direction, roughness);',
    );
    sb.writeln('}');
    sb.writeln();
  }

  sb.writeln('in vec3 v_ray;');
  sb.writeln('out vec4 frag_color;');
  sb.writeln();

  // Map compiler errors in the author's code back to the .fmat source line.
  sb.writeln('#line ${material.fragmentSourceLine}');
  sb.write(material.fragmentSource);
  if (!material.fragmentSource.endsWith('\n')) sb.writeln();
  sb.writeln();

  sb.writeln('void main() {');
  sb.writeln('  // Linear HDR radiance, premultiplied alpha (opaque sky).');
  sb.writeln('  frag_color = vec4(Sky(normalize(v_ray)), 1.0);');
  var keepAlive = _fragmentKeepAliveTerm(material, uniforms, samplers);
  // A sky that requires the environment but never calls SampleEnvironment
  // would let the compiler strip the radiance samplers and layout block the
  // engine binds unconditionally; a zero-multiplied sample keeps them live.
  if (material.useEnvironment &&
      !RegExp(r'\bSampleEnvironment\b').hasMatch(material.fragmentSource)) {
    const envTerm = 'SampleEnvironment(vec3(0.0, 1.0, 0.0), 1.0).x';
    keepAlive = keepAlive == null ? envTerm : '($keepAlive + $envTerm)';
  }
  if (keepAlive != null) {
    sb.writeln(
      '  frag_color.r += '
      '$kFragmentKeepAliveInstance.keep_alive.x * $keepAlive;',
    );
  }
  sb.writeln('}');

  return sb.toString();
}

/// Builds the JSON-serializable metadata sidecar for [material].
Map<String, Object?> buildSidecar(FmatMaterial material) {
  return <String, Object?>{
    'name': material.name,
    'framework_varying_schema': kFrameworkVaryingSchemaVersion,
    'domain': material.domain.name,
    if (material.useEnvironment) 'use_environment': true,
    'shading_model': material.shadingModel.name,
    'blending': material.blending.name,
    'culling': material.culling.name,
    if (material.depthWrite) 'depth_write': true,
    if (material.engineInputs.isNotEmpty)
      'engine_inputs': material.engineInputs,
    'uniform_block': kMaterialParamsBlock,
    // Declared order plus the resolved record offsets, so the runtime lays out
    // the instance-rate buffer without re-deriving the padding rule.
    if (material.instanceAttributes.isNotEmpty)
      'instance_attributes': [
        for (final a in material.instanceAttributes)
          <String, Object?>{
            'name': a.name,
            'type': a.type.glslType,
            'offset': a.byteOffset,
          },
      ],
    if (material.instanceAttributes.isNotEmpty)
      'instance_record_bytes': material.instanceRecordBytes,
    if (material.hasVertexStage)
      'vertex': <String, Object?>{
        for (final variant in kVertexVariants.keys)
          variant: vertexVariantEntryName(material, variant),
      },
    'parameters': [
      for (final p in material.uniformParameters)
        <String, Object?>{
          'name': p.name,
          'type': p.type.glslType,
          if (p.defaultValue != null) 'default': p.defaultValue,
          if (p.hint != null) 'hint': _hintJson(p.hint!),
        },
    ],
    'samplers': [
      for (final p in material.samplerParameters)
        <String, Object?>{
          'name': p.name,
          'type': p.type.glslType,
          if (p.hint != null) 'hint': _hintJson(p.hint!),
        },
    ],
  };
}

Map<String, Object?> _hintJson(FmatHint hint) {
  return switch (hint.kind) {
    FmatHintKind.range => <String, Object?>{
      'kind': 'range',
      'min': hint.rangeMin,
      'max': hint.rangeMax,
      'step': hint.rangeStep,
    },
    FmatHintKind.sourceColor => const {'kind': 'source_color'},
    FmatHintKind.defaultWhite => const {'kind': 'default_white'},
    FmatHintKind.defaultBlack => const {'kind': 'default_black'},
    FmatHintKind.defaultNormal => const {'kind': 'default_normal'},
    FmatHintKind.defaultTransparent => const {'kind': 'default_transparent'},
  };
}
