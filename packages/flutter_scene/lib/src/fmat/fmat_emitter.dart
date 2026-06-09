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

  final uniforms = material.uniformParameters.toList();
  if (uniforms.isNotEmpty) {
    sb.writeln('uniform $kMaterialParamsBlock {');
    for (final p in uniforms) {
      sb.writeln('  ${p.type.glslType} ${p.name};');
    }
    sb.writeln('}');
    sb.writeln('$kMaterialParamsInstance;');
    sb.writeln();
  }

  final samplers = material.samplerParameters.toList();
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
  if (uniforms.isNotEmpty) {
    sb.writeln('uniform $kMaterialParamsBlock {');
    for (final p in uniforms) {
      sb.writeln('  ${p.type.glslType} ${p.name};');
    }
    sb.writeln('}');
    sb.writeln('$kMaterialParamsInstance;');
    sb.writeln();
  }

  final samplers = material.samplerParameters.toList();
  for (final p in samplers) {
    sb.writeln('uniform ${p.type.glslType} ${p.name};');
  }
  if (samplers.isNotEmpty) sb.writeln();

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
  sb.writeln('}');

  return sb.toString();
}

/// Builds the JSON-serializable metadata sidecar for [material].
Map<String, Object?> buildSidecar(FmatMaterial material) {
  return <String, Object?>{
    'name': material.name,
    'domain': material.domain.name,
    'shading_model': material.shadingModel.name,
    'blending': material.blending.name,
    'culling': material.culling.name,
    'uniform_block': kMaterialParamsBlock,
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
