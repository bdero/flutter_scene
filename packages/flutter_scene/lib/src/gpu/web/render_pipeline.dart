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

    // Bind attribute locations from the vertex shader's reflected inputs so
    // the layout is deterministic. Inline pipelines have no reflection data;
    // there the linker assigns locations and bindVertexBuffer looks them up
    // with getAttribLocation.
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

    _buildUniformCaches();
  }

  final GpuContext _gpuContext;
  final Shader vertexShader;
  final Shader fragmentShader;
  // ignore: unused_field
  final VertexLayout? _vertexLayout;

  /// The explicit vertex layout this pipeline was created with, or null for
  /// the default reflection-derived single-buffer layout.
  VertexLayout? get vertexLayout => _vertexLayout;
  late final web.WebGLProgram _program;

  /// GL uniform locations keyed by "structName.memberName".
  final Map<String, web.WebGLUniformLocation?> _memberLocations = {};

  /// Member locations per struct type name, parallel to the struct's member
  /// list, so the per-draw uniform bind avoids building lookup strings.
  final Map<String, List<web.WebGLUniformLocation?>> _structLocations = {};

  /// Uniform-block binding point per struct type name. Populated when the
  /// linked program exposes the struct as a real uniform block (GLSL ES
  /// 3.00 bundles), in which case the per-draw bind uses bindBufferRange
  /// instead of per-member glUniform calls.
  final Map<String, int> _structBlockBindings = {};

  /// Texture unit assigned to each reflected sampler name.
  final Map<String, int> _samplerUnits = {};

  web.WebGLProgram get glProgram => _program;

  void _buildUniformCaches() {
    final gl = _gpuContext._gl;
    gl.useProgram(_program);
    final yFlipLocation = gl.getUniformLocation(_program, '_impeller_y_flip');
    if (yFlipLocation != null) {
      // Impeller's generated GLES shaders multiply gl_Position.y by this
      // backend uniform. The web shim does not use Impeller's runtime uniform
      // binding layer, so set the value that stores FBO render targets
      // top-down, matching Flutter GPU's render-to-texture convention.
      gl.uniform1f(yFlipLocation, -1.0);
    }
    var nextUnit = 0;
    var nextBlockBinding = 0;
    for (final shader in [vertexShader, fragmentShader]) {
      for (final struct in shader.uniformStructs) {
        if (_structBlockBindings.containsKey(struct.name) ||
            _structLocations.containsKey(struct.name)) {
          continue; // already resolved via the other stage
        }
        // GLSL ES 3.00 bundles emit uniform structs as std140 uniform
        // blocks (named by type). Assign each block a binding point once;
        // the per-draw bind attaches the data with bindBufferRange.
        final blockIndex = gl.getUniformBlockIndex(_program, struct.name);
        if (blockIndex != web.WebGL2RenderingContext.INVALID_INDEX) {
          final binding = nextBlockBinding++;
          gl.uniformBlockBinding(_program, blockIndex, binding);
          _structBlockBindings[struct.name] = binding;
          continue;
        }
        // GLSL ES 1.00 bundles flatten the struct to plain uniforms. GL
        // uniform names use the struct's instance name; reflection and
        // callers use its type name. Look up via instance, key by type.
        final instance =
            shader._structInstanceNames[struct.name] ?? struct.name;
        final locations = <web.WebGLUniformLocation?>[];
        for (final m in struct.members) {
          final glName = '$instance.${m.name}';
          final loc =
              gl.getUniformLocation(_program, glName) ??
              gl.getUniformLocation(_program, '$glName[0]');
          _memberLocations['${struct.name}.${m.name}'] = loc;
          locations.add(loc);
        }
        _structLocations[struct.name] = locations;
      }
      for (final tex in shader.textureBindings) {
        if (_samplerUnits.containsKey(tex.name)) continue;
        final unit = nextUnit++;
        _samplerUnits[tex.name] = unit;
        final loc = gl.getUniformLocation(_program, tex.name);
        if (loc != null) {
          // Bind the sampler uniform to its texture unit once at link time.
          gl.uniform1i(loc, unit);
        }
      }
    }
  }
}
