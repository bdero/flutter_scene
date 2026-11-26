// Checks a compiled shader bundle for the shapes that compile cleanly but
// misbehave on some backends.

import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;

/// Problems in [bundle] by entry name, one sentence each. [glsl] maps entry
/// names to the GLSL each was compiled from, when known. Only the backends
/// the bundle still carries are checked.
///
/// - A fragment resource left at binding 0 was never assigned one, because
///   the shader declares it and never reads it. Vulkan builds one descriptor
///   layout for both stages, so it collides with the vertex stage's binding 0
///   and the draw is dropped, and the WGSL sidecar cannot match it to Tint's
///   output.
/// - A sample mask output in an entry that never writes coverage reaches
///   Vulkan and WebGPU as a mask of 0, which discards every sample. It is read
///   from the SPIR-V, since the Metal output may already have dropped it.
Map<String, List<String>> lintShaderBundle(
  fb.ShaderBundle bundle, [
  Map<String, String> glsl = const {},
]) {
  final problems = <String, List<String>>{};
  void add(String name, String problem) => (problems[name] ??= []).add(problem);
  for (final shader in bundle.shaders ?? const <fb.Shader>[]) {
    final name = shader.name ?? '?';
    final vulkan = shader.vulkan;
    if (vulkan != null && vulkan.stage == fb.ShaderStage.kFragment) {
      final dead = [
        for (final u
            in vulkan.uniformStructs ?? const <fb.ShaderUniformStruct>[])
          if (u.binding == 0) 'block ${u.name}',
        for (final t
            in vulkan.uniformTextures ?? const <fb.ShaderUniformTexture>[])
          if (t.binding == 0) 'sampler ${t.name}',
      ];
      if (dead.isNotEmpty) {
        add(
          name,
          'declares resources it never reads, left at binding 0 '
          '(${dead.join(', ')})',
        );
      }
      final writesCoverage =
          glsl[name]?.contains('ApplyAlphaToCoverage(') ?? true;
      if (!writesCoverage && declaresSampleMask(vulkan.shader ?? const [])) {
        add(
          name,
          'declares a sample mask it never writes, which drops every sample '
          'on Vulkan and WebGPU',
        );
      }
    }
  }
  return problems;
}

/// Whether the SPIR-V module in [bytes] decorates a variable as the
/// `SampleMask` builtin.
bool declaresSampleMask(List<int> bytes) {
  // SPIR-V 1.6 section 2.3: a 5-word header, then instructions whose first
  // word holds the word count (high 16 bits) and opcode (low 16 bits).
  // OpDecorate is opcode 71, Decoration BuiltIn is 11, BuiltIn SampleMask
  // is 20.
  if (bytes.length < 20 || bytes.length % 4 != 0) return false;
  int word(int i) =>
      bytes[i * 4] |
      bytes[i * 4 + 1] << 8 |
      bytes[i * 4 + 2] << 16 |
      bytes[i * 4 + 3] << 24;
  if (word(0) != 0x07230203) return false;
  final count = bytes.length ~/ 4;
  var i = 5;
  while (i < count) {
    final head = word(i);
    final length = head >> 16;
    if (length == 0) return false;
    if ((head & 0xFFFF) == 71 &&
        length >= 4 &&
        word(i + 2) == 11 &&
        word(i + 3) == 20) {
      return true;
    }
    i += length;
  }
  return false;
}

/// [problems] from [lintShaderBundle], one `entry: problem` line each.
String describeLintProblems(Map<String, List<String>> problems) => [
  for (final MapEntry(key: entry, value: list) in problems.entries)
    for (final problem in list) '$entry: $problem',
].join('\n');
