part of '_webgl.dart';

/// Reflected metadata for one member of a uniform struct.
class _UniformMember {
  const _UniformMember(
    this.name,
    this.offsetInBytes,
    this.vecSize,
    this.columns,
    this.arrayElements,
    this.totalSizeInBytes,
  );

  final String name;
  final int offsetInBytes;

  /// Components per column: 1 for a scalar, N for a vecN, the row count for a
  /// matrix.
  final int vecSize;

  /// 1 for scalars and vectors; N for an NxN matrix.
  final int columns;

  /// 0 if this member is not an array. Note: for a standalone matrix
  /// Impeller's reflection sets this to the column count, so it can't be
  /// trusted to mean "array length" for matrices - use [totalSizeInBytes].
  final int arrayElements;

  /// Total reflected size in bytes (includes std140 column/array padding).
  final int totalSizeInBytes;

  bool get isMatrix => columns > 1;
}

/// Reflected metadata for a uniform struct (set as individual uniforms).
class _UniformStruct {
  const _UniformStruct(this.name, this.sizeInBytes, this.members);
  final String name;
  final int sizeInBytes;
  final List<_UniformMember> members;
}

/// Reflected metadata for a sampler binding.
class _TextureBinding {
  const _TextureBinding(this.name);
  final String name;
}

/// Reflected metadata for a vertex attribute.
class _VertexInput {
  const _VertexInput(
    this.name,
    this.location,
    this.componentCount,
    this.offsetInBytes,
  );
  final String name;
  final int location;
  final int componentCount;
  final int offsetInBytes;
}

final class WebGlUniformSlot extends UniformSlot {
  WebGlUniformSlot._(this.shader, this.uniformName);
  @override
  final WebGlShader shader;
  @override
  final String uniformName;

  @override
  int? get sizeInBytes => shader._uniformStructs[uniformName]?.sizeInBytes;

  @override
  int? getMemberOffsetInBytes(String memberName) {
    final s = shader._uniformStructs[uniformName];
    if (s == null) return null;
    for (final m in s.members) {
      if (m.name == memberName) return m.offsetInBytes;
    }
    return null;
  }
}

final class WebGlShader extends Shader {
  WebGlShader._(this._gpuContext, this.stage);

  final WebGlContext _gpuContext;
  @override
  final ShaderStage stage;

  web.WebGLShader? _glShader;

  // Bumped by every (re)compile; pipeline caches key on it so a hot-reloaded
  // shader links a fresh program while untouched shaders keep their cache.
  int _generation = 0;
  // ignore: unused_field
  String? _entrypoint;
  final Map<String, _UniformStruct> _uniformStructs = {};

  /// Maps a uniform struct's type name (what reflection and flutter_scene
  /// use, e.g. "FrameInfo") to its GLSL instance name (what GL uniform
  /// lookups use, e.g. "frame_info"). Parsed from the shader source.
  final Map<String, String> _structInstanceNames = {};
  final List<_TextureBinding> _textureBindings = [];
  final List<_VertexInput> _vertexInputs = [];
  int _vertexStride = 0;

  web.WebGLShader? get glShader => _glShader;

  /// Internal: vertex inputs reflected from the shader bundle. Empty for
  /// inline-source pipelines, which rely on the linker assigning attribute
  /// locations and `getAttribLocation` at bind time.
  // ignore: library_private_types_in_public_api
  List<_VertexInput> get vertexInputs => _vertexInputs;

  /// The reflected vertex input named [name], or null if the vertex shader
  /// declares no such input.
  // ignore: library_private_types_in_public_api
  _VertexInput? vertexInputByName(String name) {
    for (final input in _vertexInputs) {
      if (input.name == name) return input;
    }
    return null;
  }

  /// Internal: total per-vertex stride in bytes (vertex shaders only).
  int get vertexStride => _vertexStride;

  // ignore: library_private_types_in_public_api
  Iterable<_UniformStruct> get uniformStructs => _uniformStructs.values;

  // ignore: library_private_types_in_public_api
  List<_TextureBinding> get textureBindings => _textureBindings;

  @override
  UniformSlot getUniformSlot(String uniformName) =>
      WebGlUniformSlot._(this, uniformName);

  /// Compiles [source] (already in the target GLSL ES dialect) into this
  /// shader's `_glShader`. Internal use; callers (ShaderLibrary loader,
  /// inline factories) provide source that has been preprocessed if
  /// necessary.
  ///
  /// A first compile does not wait for the result, so the driver can compile
  /// it in parallel with others; a failure surfaces at the first use of a
  /// program linking it. A recompile (hot reload) checks right away and throws
  /// on failure, keeping the working shader.
  void _compile(String source) {
    final gl = _gpuContext._gl;
    final type = stage == ShaderStage.vertex
        ? web.WebGL2RenderingContext.VERTEX_SHADER
        : web.WebGL2RenderingContext.FRAGMENT_SHADER;
    final s = gl.createShader(type);
    if (s == null) {
      throw StateError('Failed to create WebGL shader object');
    }
    gl.shaderSource(s, source);
    gl.compileShader(s);
    final previous = _glShader;
    if (previous != null) {
      final error = _compileErrorOf(gl, s, stage);
      if (error != null) {
        gl.deleteShader(s);
        throw Exception(error);
      }
      // Linked programs keep their own copy of the code, so this only frees
      // the standalone object.
      gl.deleteShader(previous);
    }
    _glShader = s;
    _generation++;
  }
}

/// Describes why [shader] failed to compile, or returns null if it compiled
/// or its status is unavailable (a deleted object, a lost context). Waits for
/// the compile to finish.
String? _compileErrorOf(
  web.WebGL2RenderingContext gl,
  web.WebGLShader shader,
  ShaderStage stage,
) {
  final status =
      gl.getShaderParameter(shader, web.WebGL2RenderingContext.COMPILE_STATUS)
          as JSBoolean?;
  if (status == null || status.toDart) return null;
  final log = gl.getShaderInfoLog(shader) ?? '<no info log>';
  final source = gl.getShaderSource(shader) ?? '<no source>';
  return 'Failed to compile ${stage.name} shader:\n$log\n--- source ---\n$source';
}
