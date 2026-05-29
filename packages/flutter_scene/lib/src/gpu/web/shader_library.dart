part of '_gpu.dart';

/// Matches `uniform TypeName instanceName;` declarations (plain uniform
/// structs). Sampler uniforms like `uniform highp sampler2D foo;` are
/// filtered out by the caller.
final RegExp _uniformDecl = RegExp(
  r'uniform\s+(\w+)\s+(\w+)\s*;',
  multiLine: true,
);

/// A collection of pre-compiled shaders. Loads Impeller `.shaderbundle`
/// assets (parsing the flatbuffer, transpiling the `opengl_es` variant to
/// GLSL ES 3.00, and compiling it), and also offers a web-only
/// `fromInlineMap` for bundle-less smoke pipelines.
base class ShaderLibrary {
  ShaderLibrary._(this._shaders);

  final Map<String, Shader> _shaders;

  /// Look up a compiled shader by the name it was given in the bundle (or
  /// in the inline map).
  Shader? operator [](String name) => _shaders[name];

  /// flutter_gpu's `fromAsset` is synchronous (native FFI). Web asset
  /// loading is inherently async, so this throws; use the top-level
  /// [loadShaderLibraryAsync] instead.
  static ShaderLibrary? fromAsset(String assetName) {
    throw UnimplementedError(
      'ShaderLibrary.fromAsset is synchronous and unsupported on web. '
      'Use loadShaderLibraryAsync(assetName) instead.',
    );
  }

  /// Load and compile a `.shaderbundle` asset.
  static Future<ShaderLibrary?> _loadFromAsset(String assetName) async {
    final data = await rootBundle.load(assetName);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final bundle = fb.ShaderBundle(bytes);
    final shaders = <String, Shader>{};
    for (final entry in bundle.shaders ?? const <fb.Shader>[]) {
      final name = entry.name;
      final backend = entry.openglEs;
      if (name == null || backend == null) continue;
      shaders[name] = _buildFromBackend(backend);
    }
    return ShaderLibrary._(shaders);
  }

  static Shader _buildFromBackend(fb.BackendShader backend) {
    final stage = backend.stage == fb.ShaderStage.kFragment
        ? ShaderStage.fragment
        : ShaderStage.vertex;
    final shader = Shader._(gpuContext, stage);
    shader._entrypoint = backend.entrypoint;

    final sourceBytes = backend.shader;
    if (sourceBytes == null || sourceBytes.isEmpty) {
      throw Exception('Shader has no opengl_es source bytes.');
    }
    final source = transpileGlslEs100To300(
      utf8.decode(sourceBytes),
      isFragment: stage == ShaderStage.fragment,
    );
    shader._compile(source);

    // Parse `uniform TypeName instanceName;` so we can map reflected struct
    // type names to the instance names GL uniform lookups expect. Skips
    // sampler uniforms (handled separately via texture reflection).
    for (final m in _uniformDecl.allMatches(source)) {
      final type = m.group(1)!;
      final instance = m.group(2)!;
      if (type.startsWith('sampler') || type.startsWith('highp')) continue;
      shader._structInstanceNames[type] = instance;
    }

    // Vertex inputs (+ derived stride).
    int stride = 0;
    for (final input in backend.inputs ?? const <fb.ShaderInput>[]) {
      final name = input.name;
      if (name == null) continue;
      final components = input.vecSize;
      final offset = input.offset;
      shader._vertexInputs.add(
        _VertexInput(name, input.location, components, offset),
      );
      final end = offset + components * 4;
      if (end > stride) stride = end;
    }
    shader._vertexStride = stride;

    // Uniform structs.
    for (final s
        in backend.uniformStructs ?? const <fb.ShaderUniformStruct>[]) {
      final name = s.name;
      if (name == null) continue;
      final members = <_UniformMember>[];
      for (final f in s.fields ?? const <fb.ShaderUniformStructField>[]) {
        final fname = f.name;
        if (fname == null) continue;
        members.add(
          _UniformMember(
            fname,
            f.offsetInBytes,
            f.vecSize,
            f.columns,
            f.arrayElements,
            f.totalSizeInBytes,
          ),
        );
      }
      shader._uniformStructs[name] = _UniformStruct(
        name,
        s.sizeInBytes,
        members,
      );
    }

    // Texture (sampler) bindings.
    for (final t
        in backend.uniformTextures ?? const <fb.ShaderUniformTexture>[]) {
      final name = t.name;
      if (name == null) continue;
      shader._textureBindings.add(_TextureBinding(name));
    }

    return shader;
  }

  /// Web-only addition. Compile an inline map of GLSL ES 1.00 sources for
  /// quick smoke-test pipelines. Each entry's source is run through
  /// `transpileGlslEs100To300` before compilation. Reflection metadata is
  /// not populated, so these shaders only work with pipelines that don't
  /// need reflection-driven binding (single `position` attribute, no
  /// uniforms or textures).
  static ShaderLibrary fromInlineMap(
    Map<String, ({String source, ShaderStage stage})> shaders,
  ) {
    final compiled = <String, Shader>{};
    shaders.forEach((name, entry) {
      final s = Shader._(gpuContext, entry.stage);
      s._compile(
        transpileGlslEs100To300(
          entry.source,
          isFragment: entry.stage == ShaderStage.fragment,
        ),
      );
      compiled[name] = s;
    });
    return ShaderLibrary._(compiled);
  }
}

/// Asynchronously load and compile a `.shaderbundle` asset. The canonical
/// loading entry point on web (where synchronous asset reads aren't
/// possible).
Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) {
  return ShaderLibrary._loadFromAsset(assetName);
}

/// Compile a map of inline GLSL ES 1.00 sources into a ShaderLibrary.
/// Web-specific; on native targets this throws.
ShaderLibrary compileShaderLibraryInline(
  Map<String, ({String source, ShaderStage stage})> shaders,
) => ShaderLibrary.fromInlineMap(shaders);
