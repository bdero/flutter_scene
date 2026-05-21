/// Mechanical GLSL ES 1.00 -> 3.00 transformations sufficient for the
/// shapes of shader source that Impeller's `impellerc` emits for its
/// `opengl_es` backend. Lets Impeller bundles compile under a WebGL2
/// context, where the WebGL1-era extensions used to gate derivatives and
/// explicit-LOD sampling aren't available but the same features are core
/// in `#version 300 es`.
///
/// Not a general-purpose GLSL transpiler.
library;

final RegExp _strippableExtensions = RegExp(
  r'^(#extension\s+'
  r'(?:GL_OES_standard_derivatives|GL_EXT_shader_texture_lod)'
  r'\b[^\n]*)',
  multiLine: true,
);

final RegExp _versionDirective = RegExp(
  r'^#version\s+100\b[^\n]*',
  multiLine: true,
);

final RegExp _dropExtensionLines = RegExp(
  r'^#extension\s+'
  r'(?:GL_OES_standard_derivatives|GL_EXT_shader_texture_lod)'
  r'\b[^\n]*\n',
  multiLine: true,
);

final RegExp _attributeKeyword = RegExp(r'\battribute\b');
final RegExp _varyingKeyword = RegExp(r'\bvarying\b');
final RegExp _texture2DLodEXT = RegExp(r'\btexture2DLodEXT\b');
final RegExp _texture2DLod = RegExp(r'\btexture2DLod\b');
final RegExp _textureCubeLod = RegExp(r'\btextureCubeLod\b');
final RegExp _texture2DProj = RegExp(r'\btexture2DProj\b');
final RegExp _texture2D = RegExp(r'\btexture2D\b');
final RegExp _textureCube = RegExp(r'\btextureCube\b');
final RegExp _glFragColor = RegExp(r'\bgl_FragColor\b');
final RegExp _glFragData0 = RegExp(r'\bgl_FragData\s*\[\s*0\s*\]');
final RegExp _mainEntry = RegExp(r'\bvoid\s+main\s*\(\s*(?:void)?\s*\)');
final RegExp _precisionLine = RegExp(
  r'precision\s+\w+\s+\w+\s*;',
  multiLine: true,
);

/// Replace `#extension` directives that WebGL2 doesn't honor in GLSL ES
/// 1.00 mode with a `// stripped by shim:` comment. Preserves line numbers
/// so info-log references stay aligned with the original source.
///
/// Note: stripping alone is not sufficient. WebGL2 doesn't expose
/// derivatives or explicit-LOD as builtins in `#version 100` shaders even
/// when the extension directives are removed. Use [transpileGlslEs100To300]
/// for full WebGL2 compatibility.
String stripWebGl2CoreExtensions(String source) {
  return source.replaceAllMapped(
    _strippableExtensions,
    (m) => '// stripped by shim: ${m.group(1)}',
  );
}

/// Mechanically transpile a GLSL ES 1.00 shader source (as emitted by
/// Impeller's `opengl_es` backend) to GLSL ES 3.00 so it compiles under a
/// WebGL2 context.
///
/// The transformations applied:
///
///   * `#version 100` -> `#version 300 es`
///   * Drop `#extension GL_OES_standard_derivatives` and
///     `#extension GL_EXT_shader_texture_lod` (core in 300 es)
///   * `attribute` -> `in`
///   * `varying` -> `in` (fragment) or `out` (vertex)
///   * `texture2D` / `textureCube` -> `texture` (overloaded on sampler)
///   * `texture2DLod` / `texture2DLodEXT` / `textureCubeLod` -> `textureLod`
///   * `texture2DProj` -> `textureProj`
///   * In fragment shaders: `gl_FragColor` and `gl_FragData[0]` are
///     redirected to an injected `out highp vec4 _frag_color`.
///   * In vertex shaders: `gl_Position.y` is negated (the entry point is
///     wrapped) so render-to-texture content is stored top-down, matching
///     what flutter_scene's shaders assume when they later sample those
///     targets. See [transpileGlslEs100To300]'s body for the rationale.
///
/// [isFragment] selects the right `varying` translation, gates the
/// fragment-output injection, and gates the vertex Y-flip. Use `false` for
/// vertex shaders.
String transpileGlslEs100To300(String source, {required bool isFragment}) {
  var out = source;

  out = out.replaceFirst(_versionDirective, '#version 300 es');
  out = out.replaceAll(_dropExtensionLines, '');

  out = out.replaceAll(_attributeKeyword, 'in');
  out = out.replaceAll(_varyingKeyword, isFragment ? 'in' : 'out');

  out = out.replaceAll(_texture2DLodEXT, 'textureLod');
  out = out.replaceAll(_texture2DLod, 'textureLod');
  out = out.replaceAll(_textureCubeLod, 'textureLod');
  out = out.replaceAll(_texture2DProj, 'textureProj');
  out = out.replaceAll(_texture2D, 'texture');
  out = out.replaceAll(_textureCube, 'texture');

  if (isFragment) {
    out = out.replaceAll(_glFragColor, '_frag_color');
    out = out.replaceAll(_glFragData0, '_frag_color');

    const injection = '\n\nout highp vec4 _frag_color;\n';
    final precisionMatches = _precisionLine.allMatches(out).toList();
    if (precisionMatches.isNotEmpty) {
      final last = precisionMatches.last;
      out = out.substring(0, last.end) + injection + out.substring(last.end);
    } else {
      final firstNewline = out.indexOf('\n');
      out =
          '${out.substring(0, firstNewline + 1)}'
          '$injection'
          '${out.substring(firstNewline + 1)}';
    }
  } else {
    // Vertex stage: absorb the render-to-texture Y-axis difference here.
    // WebGL2 rasterizes into FBO textures bottom-up, but flutter_scene (like
    // Impeller's Metal/Vulkan backends) assumes render-to-texture content is
    // stored top-down - that's what its shaders expect when they later sample
    // those targets (the IBL prefilter atlas, the HDR scene color). Negating
    // gl_Position.y makes every offscreen render the shim does store top-down.
    // The winding order is inverted to match (see RenderPass.setWindingOrder).
    // Mirrors flutter/flutter#186556, which does the same in Impeller's GLES
    // backend. Every shim render pass targets an offscreen texture (the
    // present is a blit, not a render pass), so the flip is unconditional.
    final mainMatch = _mainEntry.firstMatch(out);
    if (mainMatch != null) {
      out = out.replaceRange(
        mainMatch.start,
        mainMatch.end,
        'void _impeller_vertex_main()',
      );
      out =
          '$out\n\n'
          'void main() {\n'
          '  _impeller_vertex_main();\n'
          '  gl_Position.y = -gl_Position.y;\n'
          '}\n';
    }
  }

  return out;
}
