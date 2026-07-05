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

/// Emits the fragment shader GLSL for [material].
String emitFragmentGlsl(FmatMaterial material) {
  if (material.domain == FmatDomain.sky) {
    return _emitSkyGlsl(material);
  }
  final sb = StringBuffer();
  final lit = material.shadingModel == FmatShadingModel.lit;

  sb.writeln(
    '// Generated from a .fmat material by flutter_scene. '
    'Do not edit.',
  );
  sb.writeln('#include <material_varyings.glsl>');
  sb.writeln('#include <pbr.glsl>');
  sb.writeln('#include <texture.glsl>');
  sb.writeln('#include <normals.glsl>');
  sb.writeln('#include <material_inputs.glsl>');
  if (lit) {
    sb.writeln('#include <material_engine_lighting.glsl>');
    sb.writeln('#include <material_lighting.glsl>');
  }
  sb.writeln();

  // Custom interpolants the vertex stage wrote, read by name in Surface().
  _writeVaryings(sb, material, 'in');

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
  if (lit) {
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

String _emitVertexVariant(
  FmatMaterial material,
  String bodyInclude, {
  required bool isDepth,
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
  if (material.attributes.isNotEmpty) {
    // Folded into the zero-bound keep-alive by the body include so an
    // attribute Vertex() never reads survives compilation; the geometry
    // supplies its buffer unconditionally and a stripped input breaks
    // reflection and the pipeline's vertex layout.
    final terms = material.attributes
        .map((a) => a.type == FmatType.float_ ? a.name : '${a.name}.x')
        .join(' + ');
    sb.writeln('#define MATERIAL_ATTRIBUTES_KEEP_ALIVE ($terms)');
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
String _emitSkyGlsl(FmatMaterial material) {
  final sb = StringBuffer();
  sb.writeln('// Generated from a .fmat sky by flutter_scene. Do not edit.');
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
  if (uniforms.isNotEmpty || samplers.isNotEmpty) {
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
      '// The scene environment\'s prefiltered-radiance atlas, bound by the',
    );
    sb.writeln(
      '// engine. Sample with SamplePrefilteredRadiance(prefiltered_radiance,',
    );
    sb.writeln('// direction, roughness).');
    sb.writeln('uniform sampler2D prefiltered_radiance;');
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
  final keepAlive = _fragmentKeepAliveTerm(material, uniforms, samplers);
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
    'domain': material.domain.name,
    if (material.useEnvironment) 'use_environment': true,
    'shading_model': material.shadingModel.name,
    'blending': material.blending.name,
    'culling': material.culling.name,
    'uniform_block': kMaterialParamsBlock,
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
