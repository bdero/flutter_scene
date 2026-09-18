part of '_gpu.dart';

/// Builds a texture's mip chain on the GPU with the engine's 2x2 box filter
/// (linear light for color, raw for data, renormalized for normals), so a
/// chain built here matches one uploaded level by level on other backends.
///
/// Each level renders into a scratch texture from the level above and is then
/// copied into place, so no draw samples the texture it writes.
class _MipGenerator {
  _MipGenerator(this._context);

  final GpuContext _context;
  web.WebGLProgram? _program;
  web.WebGLVertexArrayObject? _vao;
  web.WebGLUniformLocation? _sourceLocation;
  web.WebGLUniformLocation? _levelLocation;
  web.WebGLUniformLocation? _modeLocation;

  static const _vertexSource = '''#version 300 es
void main() {
  // One triangle covering clip space; no vertex buffer.
  vec2 corner = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);
  gl_Position = vec4(corner, 0.0, 1.0);
}
''';

  // Mirrors generateMipChain in lib/src/texture/mipmap.dart, including the
  // edge clamp for odd source sizes.
  static const _fragmentSource = '''#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2D u_source;
uniform int u_level;
uniform int u_mode;
out vec4 frag_color;

vec3 SrgbToLinear(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 LinearToSrgb(vec3 c) {
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void main() {
  ivec2 limit = textureSize(u_source, u_level) - 1;
  ivec2 origin = ivec2(gl_FragCoord.xy) * 2;
  vec4 a = texelFetch(u_source, min(origin, limit), u_level);
  vec4 b = texelFetch(u_source, min(origin + ivec2(1, 0), limit), u_level);
  vec4 c = texelFetch(u_source, min(origin + ivec2(0, 1), limit), u_level);
  vec4 d = texelFetch(u_source, min(origin + ivec2(1, 1), limit), u_level);
  float alpha = (a.a + b.a + c.a + d.a) * 0.25;
  vec3 rgb;
  if (u_mode == 0) {
    rgb = LinearToSrgb((SrgbToLinear(a.rgb) + SrgbToLinear(b.rgb) + SrgbToLinear(c.rgb) + SrgbToLinear(d.rgb)) * 0.25);
  } else if (u_mode == 2) {
    vec3 n = (a.rgb + b.rgb + c.rgb + d.rgb) * 2.0 - 4.0;
    float len = length(n);
    n = len > 1e-6 ? n / len : vec3(0.0, 0.0, 1.0);
    rgb = n * 0.5 + 0.5;
    alpha = 1.0;
  } else {
    rgb = (a.rgb + b.rgb + c.rgb + d.rgb) * 0.25;
  }
  frag_color = vec4(rgb, alpha);
}
''';

  static int _mode(MipContent content) => switch (content) {
    MipContent.color => 0,
    MipContent.data => 1,
    MipContent.normal => 2,
  };

  /// Fills levels 1 and up of [texture] from its level 0.
  void generate(Texture texture, MipContent content) {
    if (texture.mipLevelCount <= 1) return;
    if (texture.textureType != TextureType.texture2D) {
      throw UnsupportedError(
        'Mip generation is only supported for 2D textures',
      );
    }
    final gl = _context._gl;
    _ensureProgram(gl);
    const target = web.WebGL2RenderingContext.TEXTURE_2D;
    const fb = web.WebGL2RenderingContext.FRAMEBUFFER;

    // The scratch chain holds levels 1 and up, so it starts at half size.
    final scratch = gl.createTexture();
    final fbo = gl.createFramebuffer();
    if (scratch == null || fbo == null) {
      throw StateError('Failed to allocate mip generation scratch');
    }
    _context._bindTextureForSetup(target, scratch);
    gl.texStorage2D(
      target,
      texture.mipLevelCount - 1,
      web.WebGL2RenderingContext.RGBA8,
      (texture.width >> 1).clamp(1, texture.width).toInt(),
      (texture.height >> 1).clamp(1, texture.height).toInt(),
    );

    final blend = gl.isEnabled(web.WebGL2RenderingContext.BLEND);
    final depth = gl.isEnabled(web.WebGL2RenderingContext.DEPTH_TEST);
    final stencil = gl.isEnabled(web.WebGL2RenderingContext.STENCIL_TEST);
    final scissor = gl.isEnabled(web.WebGL2RenderingContext.SCISSOR_TEST);
    final cull = gl.isEnabled(web.WebGL2RenderingContext.CULL_FACE);
    gl.disable(web.WebGL2RenderingContext.BLEND);
    gl.disable(web.WebGL2RenderingContext.DEPTH_TEST);
    gl.disable(web.WebGL2RenderingContext.STENCIL_TEST);
    gl.disable(web.WebGL2RenderingContext.SCISSOR_TEST);
    gl.disable(web.WebGL2RenderingContext.CULL_FACE);

    gl.useProgram(_program);
    gl.bindVertexArray(_vao);
    gl.uniform1i(_sourceLocation, _context._setupTextureUnit);
    gl.uniform1i(_modeLocation, _mode(content));
    // The source is sampled from, and copied into, on the setup unit.
    _context._bindTextureForSetup(target, texture._texture);
    gl.bindFramebuffer(fb, fbo);
    for (var level = 1; level < texture.mipLevelCount; level++) {
      final width = (texture.width >> level).clamp(1, texture.width).toInt();
      final height = (texture.height >> level).clamp(1, texture.height).toInt();
      gl.framebufferTexture2D(
        fb,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        target,
        scratch,
        level - 1,
      );
      gl.viewport(0, 0, width, height);
      gl.uniform1i(_levelLocation, level - 1);
      gl.drawArrays(web.WebGL2RenderingContext.TRIANGLES, 0, 3);
      gl.copyTexSubImage2D(target, level, 0, 0, 0, 0, width, height);
    }
    gl.bindFramebuffer(fb, null);
    gl.deleteFramebuffer(fbo);
    gl.deleteTexture(scratch);
    gl.bindVertexArray(null);
    gl.useProgram(null);

    if (blend) gl.enable(web.WebGL2RenderingContext.BLEND);
    if (depth) gl.enable(web.WebGL2RenderingContext.DEPTH_TEST);
    if (stencil) gl.enable(web.WebGL2RenderingContext.STENCIL_TEST);
    if (scissor) gl.enable(web.WebGL2RenderingContext.SCISSOR_TEST);
    if (cull) gl.enable(web.WebGL2RenderingContext.CULL_FACE);
  }

  void _ensureProgram(web.WebGL2RenderingContext gl) {
    if (_program != null) return;
    final program = gl.createProgram();
    final vao = gl.createVertexArray();
    if (program == null || vao == null) {
      throw StateError('Failed to create the mip generation program');
    }
    gl.attachShader(
      program,
      _compile(gl, web.WebGL2RenderingContext.VERTEX_SHADER, _vertexSource),
    );
    gl.attachShader(
      program,
      _compile(gl, web.WebGL2RenderingContext.FRAGMENT_SHADER, _fragmentSource),
    );
    gl.linkProgram(program);
    final linked = gl.getProgramParameter(
      program,
      web.WebGL2RenderingContext.LINK_STATUS,
    );
    if (!(linked.isA<JSBoolean>() && (linked as JSBoolean).toDart)) {
      throw StateError(
        'Mip generation program failed to link: '
        '${gl.getProgramInfoLog(program)}',
      );
    }
    _program = program;
    _vao = vao;
    _sourceLocation = gl.getUniformLocation(program, 'u_source');
    _levelLocation = gl.getUniformLocation(program, 'u_level');
    _modeLocation = gl.getUniformLocation(program, 'u_mode');
  }

  static web.WebGLShader _compile(
    web.WebGL2RenderingContext gl,
    int type,
    String source,
  ) {
    final shader = gl.createShader(type);
    if (shader == null) {
      throw StateError('Failed to create a mip generation shader');
    }
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    final compiled = gl.getShaderParameter(
      shader,
      web.WebGL2RenderingContext.COMPILE_STATUS,
    );
    if (!(compiled.isA<JSBoolean>() && (compiled as JSBoolean).toDart)) {
      throw StateError(
        'Mip generation shader failed to compile: '
        '${gl.getShaderInfoLog(shader)}',
      );
    }
    return shader;
  }
}
