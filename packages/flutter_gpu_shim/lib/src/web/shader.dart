part of '_gpu.dart';

/// Reflected metadata for one member of a uniform struct.
class _UniformMember {
  const _UniformMember(this.name, this.offset, this.sizeInBytes);
  final String name;
  final int offset;
  final int sizeInBytes;
}

/// Reflected metadata for a uniform struct (UBO binding).
class _UniformStruct {
  _UniformStruct(this.name, this.binding, this.sizeInBytes, this.members);
  final String name;
  final int binding;
  final int sizeInBytes;
  final List<_UniformMember> members;
}

/// Reflected metadata for a sampler binding.
class _TextureBinding {
  const _TextureBinding(this.name, this.unit);
  final String name;
  final int unit;
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

base class UniformSlot {
  UniformSlot._(this.shader, this.uniformName);
  final Shader shader;
  final String uniformName;

  int? get sizeInBytes {
    final s = shader._uniformStructs[uniformName];
    return s?.sizeInBytes;
  }

  int? getMemberOffsetInBytes(String memberName) {
    final s = shader._uniformStructs[uniformName];
    if (s == null) return null;
    for (final m in s.members) {
      if (m.name == memberName) return m.offset;
    }
    return null;
  }

  // Reflection-driven helpers will land in Phase 2+ when ShaderLibrary
  // starts populating the bindings list from the bundle's metadata.
}

base class Shader {
  Shader._(this._gpuContext, this.stage);

  final GpuContext _gpuContext;
  final ShaderStage stage;

  web.WebGLShader? _glShader;
  // ignore: unused_field
  String? _entrypoint;
  final Map<String, _UniformStruct> _uniformStructs = {};
  // ignore: unused_field
  final List<_TextureBinding> _textureBindings = [];
  final List<_VertexInput> _vertexInputs = [];
  // Set by the bundle loader once shader-bundle reflection lands in Phase 2+.
  final int _vertexStride = 0;

  /// Internal: the compiled GL shader handle.
  web.WebGLShader? get glShader => _glShader;

  /// Internal: vertex inputs reflected from the shader bundle. Empty for
  /// inline-source pipelines, which rely on the linker assigning
  /// attribute locations and `getAttribLocation` at bind time.
  // ignore: library_private_types_in_public_api
  List<_VertexInput> get vertexInputs => _vertexInputs;

  /// Internal: total per-vertex stride in bytes (vertex shaders only).
  int get vertexStride => _vertexStride;

  UniformSlot getUniformSlot(String uniformName) =>
      UniformSlot._(this, uniformName);

  /// Compile [source] (already in the target GLSL ES dialect) into this
  /// shader's `_glShader`. Internal use; callers (ShaderLibrary loader,
  /// inline factories) provide source that has been preprocessed if
  /// necessary.
  void _compile(String source) {
    final gl = _gpuContext._gl;
    final type =
        stage == ShaderStage.vertex
            ? web.WebGL2RenderingContext.VERTEX_SHADER
            : web.WebGL2RenderingContext.FRAGMENT_SHADER;
    final s = gl.createShader(type);
    if (s == null) {
      throw StateError('Failed to create WebGL shader object');
    }
    gl.shaderSource(s, source);
    gl.compileShader(s);
    final ok =
        (gl.getShaderParameter(s, web.WebGL2RenderingContext.COMPILE_STATUS)
                as JSBoolean?)
            ?.toDart ??
        false;
    if (!ok) {
      final log = gl.getShaderInfoLog(s) ?? '<no info log>';
      gl.deleteShader(s);
      throw Exception(
        'Failed to compile ${stage.name} shader:\n$log\n--- source ---\n$source',
      );
    }
    _glShader = s;
  }
}
