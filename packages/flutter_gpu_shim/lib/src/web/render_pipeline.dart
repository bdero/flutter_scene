part of '_gpu.dart';

/// A linked WebGL program built from a vertex + fragment shader pair, plus
/// cached reflection state used by RenderPass when binding resources.
base class RenderPipeline {
  RenderPipeline._(
    this._gpuContext,
    this.vertexShader,
    this.fragmentShader, {
    VertexLayout? vertexLayout,
  }) : _vertexLayout = vertexLayout {
    final gl = _gpuContext._gl;
    final program = gl.createProgram();
    if (program == null) {
      throw StateError('Failed to create WebGL program');
    }
    _program = program;

    final vs = vertexShader._glShader;
    final fs = fragmentShader._glShader;
    if (vs == null || fs == null) {
      throw StateError('Shader objects were not compiled before linking');
    }
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);

    // Bind attribute locations from the vertex shader's reflected inputs
    // so the layout is deterministic regardless of compiler ordering.
    // Inline pipelines have no reflection data; in that case we let the
    // linker assign locations and look them up post-link with
    // getAttribLocation when binding the vertex buffer.
    for (final input in vertexShader.vertexInputs) {
      gl.bindAttribLocation(program, input.location, input.name);
    }

    gl.linkProgram(program);
    final ok =
        (gl.getProgramParameter(program, web.WebGL2RenderingContext.LINK_STATUS)
                as JSBoolean?)
            ?.toDart ??
        false;
    if (!ok) {
      final log = gl.getProgramInfoLog(program) ?? '<no info log>';
      gl.deleteProgram(program);
      throw Exception('Failed to link program: $log');
    }
  }

  final GpuContext _gpuContext;
  final Shader vertexShader;
  final Shader fragmentShader;
  // ignore: unused_field
  final VertexLayout? _vertexLayout;
  late final web.WebGLProgram _program;

  /// Internal: the linked WebGL program handle.
  web.WebGLProgram get glProgram => _program;
}
