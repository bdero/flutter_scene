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

  /// Libraries loaded from each `.shaderbundle` asset, tracked weakly so
  /// [reinitializeShaderLibraryAsync] can recompile their shaders in place
  /// on hot reload without keeping a library alive.
  static final Map<String, List<WeakReference<ShaderLibrary>>> _loadedByAsset =
      {};

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

  /// Mirrors flutter_gpu's in-place shader hot reload on native. The web
  /// backend compiles its own GLSL, so the reload is asynchronous; this
  /// fires it and returns. Await [reinitializeShaderLibraryAsync] instead
  /// when ordering matters (evicting pipelines after the recompile).
  static void reinitialize(String assetKey) {
    unawaited(reinitializeShaderLibraryAsync(assetKey));
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
    final library = ShaderLibrary._(shaders);
    _loadedByAsset.putIfAbsent(assetName, () => []).add(WeakReference(library));
    return library;
  }

  static Shader _buildFromBackend(fb.BackendShader backend) {
    final stage = backend.stage == fb.ShaderStage.kFragment
        ? ShaderStage.fragment
        : ShaderStage.vertex;
    final shader = Shader._(gpuContext, stage);
    _populateFromBackend(shader, backend);
    return shader;
  }

  /// (Re)compiles [backend] into [shader] in place: replaces the GL shader
  /// object and rebuilds the reflection state, keeping the [Shader]'s
  /// identity so materials and pipeline-cache keys stay valid.
  static void _populateFromBackend(Shader shader, fb.BackendShader backend) {
    shader._entrypoint = backend.entrypoint;

    final sourceBytes = backend.shader;
    if (sourceBytes == null || sourceBytes.isEmpty) {
      throw Exception('Shader has no opengl_es source bytes.');
    }
    final source = transpileGlslEs100To300(
      utf8.decode(sourceBytes),
      isFragment: shader.stage == ShaderStage.fragment,
    );
    shader._compile(source);

    // Rebuild the reflection state from scratch (a reload may have changed
    // the uniforms, inputs, or samplers).
    shader._structInstanceNames.clear();
    shader._vertexInputs.clear();
    shader._uniformStructs.clear();
    shader._textureBindings.clear();

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

/// Re-fetches a `.shaderbundle` asset and recompiles every live shader that
/// was loaded from it, in place (shader identities are preserved, so
/// material references and pipeline-cache keys stay valid). The web
/// counterpart of flutter_gpu's `ShaderLibrary.reinitialize`; await it
/// before evicting cached pipelines so rebuilt pipelines link the new code.
Future<void> reinitializeShaderLibraryAsync(String assetKey) async {
  final references = ShaderLibrary._loadedByAsset[assetKey];
  if (references == null) return;
  references.removeWhere((reference) => reference.target == null);
  if (references.isEmpty) {
    ShaderLibrary._loadedByAsset.remove(assetKey);
    return;
  }

  rootBundle.evict(assetKey);
  final data = await rootBundle.load(assetKey);
  final bundle = fb.ShaderBundle(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  var recompiled = 0;
  for (final entry in bundle.shaders ?? const <fb.Shader>[]) {
    final name = entry.name;
    final backend = entry.openglEs;
    if (name == null || backend == null) continue;
    for (final reference in references) {
      final shader = reference.target?._shaders[name];
      if (shader == null) continue;
      ShaderLibrary._populateFromBackend(shader, backend);
      recompiled++;
    }
  }
  debugPrint(
    'flutter_scene (web): recompiled $recompiled shader(s) from "$assetKey"',
  );
}

/// Compile a map of inline GLSL ES 1.00 sources into a ShaderLibrary.
/// Web-specific; on native targets this throws.
ShaderLibrary compileShaderLibraryInline(
  Map<String, ({String source, ShaderStage stage})> shaders,
) => ShaderLibrary.fromInlineMap(shaders);
