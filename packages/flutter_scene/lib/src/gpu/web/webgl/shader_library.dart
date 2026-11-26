part of '_webgl.dart';

/// Matches `uniform TypeName instanceName;` declarations (plain uniform
/// structs). Sampler uniforms like `uniform highp sampler2D foo;` are
/// filtered out by the caller.
final RegExp _uniformDecl = RegExp(
  r'uniform\s+(\w+)\s+(\w+)\s*;',
  multiLine: true,
);

/// A collection of shaders. Loads Impeller `.shaderbundle` assets (parsing
/// the flatbuffer, then transpiling a shader's `opengl_es` variant to GLSL ES
/// 3.00 and compiling it on its first lookup), and also offers a web-only
/// `fromInlineMap` for bundle-less smoke pipelines.
final class WebGlShaderLibrary extends ShaderLibrary {
  WebGlShaderLibrary._(
    this._entries, {
    Map<String, WebGlShader>? shaders,
    String? assetName,
  }) : _shaders = shaders ?? {},
       _assetName = assetName;

  /// The bundle entries, each compiled when first looked up. Libraries of one
  /// asset share this map.
  final Map<String, fb.BackendShader> _entries;
  final Map<String, WebGlShader> _shaders;
  final String? _assetName;

  /// Shaders loaded from each `.shaderbundle` asset, tracked weakly by their
  /// bundle entry name so [_reinitializeShaderLibraryAsync] can recompile the
  /// live ones in place on hot reload. Weak per shader: a shader stays
  /// tracked exactly as long as something (a material, a pipeline) holds it,
  /// regardless of whether its [ShaderLibrary] wrapper is still alive.
  static final Map<String, List<({String name, WeakReference<Shader> shader})>>
  _shadersByAsset = {};

  /// The bundle entries of each loaded asset, which hot reload replaces so a
  /// shader first looked up after it compiles the new source.
  static final Map<String, Map<String, fb.BackendShader>> _entriesByAsset = {};

  /// Look up a shader by the name it was given in the bundle (or in the
  /// inline map), compiling it on its first lookup.
  @override
  Shader? operator [](String name) => _shaders[name] ?? _compiled(name);

  WebGlShader? _compiled(String name) {
    final backend = _entries[name];
    if (backend == null) return null;
    final shader = _buildFromBackend(backend);
    final assetName = _assetName;
    if (assetName != null) {
      _shadersByAsset.putIfAbsent(assetName, () => []).add((
        name: name,
        shader: WeakReference(shader),
      ));
    }
    return _shaders[name] = shader;
  }

  /// Load a `.shaderbundle` asset, revalidated so a browser cache
  /// never pairs an old bundle with new Dart code.
  static Future<ShaderLibrary?> _loadFromAsset(String assetName) async {
    final fresh = _entriesOf(await loadGeneratedAsset(assetName));
    final entries = (_entriesByAsset[assetName] ??= {})
      ..clear()
      ..addAll(fresh);
    _shadersByAsset.putIfAbsent(assetName, () => []);
    return WebGlShaderLibrary._(entries, assetName: assetName);
  }

  static WebGlShaderLibrary _loadFromBytes(ByteData data) =>
      WebGlShaderLibrary._(_entriesOf(data));

  /// The `opengl_es` entries of the bundle in [data], by name.
  static Map<String, fb.BackendShader> _entriesOf(ByteData data) {
    final bundle = fb.ShaderBundle(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return {
      for (final entry in bundle.shaders ?? const <fb.Shader>[])
        if ((entry.name, entry.openglEs) case (final name?, final backend?))
          name: backend,
    };
  }

  static WebGlShader _buildFromBackend(fb.BackendShader backend) {
    final stage = backend.stage == fb.ShaderStage.kFragment
        ? ShaderStage.fragment
        : ShaderStage.vertex;
    final shader = WebGlShader._(webGlContext, stage);
    _populateFromBackend(shader, backend);
    return shader;
  }

  /// (Re)compiles [backend] into [shader] in place: replaces the GL shader
  /// object and rebuilds the reflection state, keeping the [Shader]'s
  /// identity so materials and pipeline-cache keys stay valid.
  static void _populateFromBackend(Shader shader, fb.BackendShader backend) {
    shader.webGl._entrypoint = backend.entrypoint;

    final sourceBytes = backend.shader;
    if (sourceBytes == null || sourceBytes.isEmpty) {
      throw Exception('Shader has no opengl_es source bytes.');
    }
    var source = transpileGlslEs100To300(
      utf8.decode(sourceBytes),
      isFragment: shader.stage == ShaderStage.fragment,
    );
    if (shader.stage == ShaderStage.vertex && webGlContext.clipDepthZeroToOne) {
      source = stripClipSpaceDepthRemap(source);
    }
    shader.webGl._compile(source);

    // Rebuild the reflection state from scratch (a reload may have changed
    // the uniforms, inputs, or samplers).
    shader.webGl._structInstanceNames.clear();
    shader.webGl._vertexInputs.clear();
    shader.webGl._uniformStructs.clear();
    shader.webGl._textureBindings.clear();

    // Parse `uniform TypeName instanceName;` so we can map reflected struct
    // type names to the instance names GL uniform lookups expect. Skips
    // sampler uniforms (handled separately via texture reflection).
    for (final m in _uniformDecl.allMatches(source)) {
      final type = m.group(1)!;
      final instance = m.group(2)!;
      if (type.startsWith('sampler') || type.startsWith('highp')) continue;
      shader.webGl._structInstanceNames[type] = instance;
    }

    // Vertex inputs (+ derived stride).
    int stride = 0;
    for (final input in backend.inputs ?? const <fb.ShaderInput>[]) {
      final name = input.name;
      if (name == null) continue;
      final components = input.vecSize;
      final offset = input.offset;
      shader.webGl._vertexInputs.add(
        _VertexInput(name, input.location, components, offset),
      );
      final end = offset + components * 4;
      if (end > stride) stride = end;
    }
    shader.webGl._vertexStride = stride;

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
      shader.webGl._uniformStructs[name] = _UniformStruct(
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
      shader.webGl._textureBindings.add(_TextureBinding(name));
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
    final compiled = <String, WebGlShader>{};
    shaders.forEach((name, entry) {
      final s = WebGlShader._(webGlContext, entry.stage);
      s._compile(
        transpileGlslEs100To300(
          entry.source,
          isFragment: entry.stage == ShaderStage.fragment,
        ),
      );
      compiled[name] = s;
    });
    return WebGlShaderLibrary._({}, shaders: compiled);
  }
}

/// Asynchronously load and compile a `.shaderbundle` asset. The canonical
/// loading entry point on web (where synchronous asset reads aren't
/// possible).
Future<ShaderLibrary?> _loadShaderLibraryAsync(String assetName) async {
  final library = await WebGlShaderLibrary._loadFromAsset(assetName);
  if (library != null) {
    registerShaderLibrarySource(
      library,
      ShaderLibrarySource(assetKey: assetName),
    );
  }
  return library;
}

/// Loads a shader bundle directly from [bytes].
// TODO(shader-byte-reload): register byte-backed shaders with a reload source.
Future<ShaderLibrary?> _loadShaderLibraryFromBytesAsync(ByteData bytes) async {
  final library = WebGlShaderLibrary._loadFromBytes(bytes);
  registerShaderLibrarySource(library, ShaderLibrarySource(bytes: bytes));
  return library;
}

/// Re-fetches a `.shaderbundle` asset and recompiles every live shader that
/// was loaded from it, in place (shader identities are preserved, so
/// material references and pipeline-cache keys stay valid). The web
/// counterpart of flutter_gpu's `ShaderLibrary.reinitialize`; await it
/// before evicting cached pipelines so rebuilt pipelines link the new code.
Future<void> _reinitializeShaderLibraryAsync(String assetKey) async {
  final tracked = WebGlShaderLibrary._shadersByAsset[assetKey];
  if (tracked == null) {
    debugPrint(
      'flutter_scene (web): no shaders were loaded from "$assetKey"; '
      'nothing to reload',
    );
    return;
  }
  // A library whose shaders were never looked up still tracks into [tracked],
  // so it stays registered even when empty.
  tracked.removeWhere((entry) => entry.shader.target == null);

  final entries = WebGlShaderLibrary._entriesOf(
    await loadGeneratedAsset(assetKey),
  );
  WebGlShaderLibrary._entriesByAsset[assetKey]
    ?..clear()
    ..addAll(entries);
  var recompiled = 0;
  for (final MapEntry(key: name, value: backend) in entries.entries) {
    for (final record in tracked) {
      if (record.name != name) continue;
      final shader = record.shader.target;
      if (shader == null) continue;
      WebGlShaderLibrary._populateFromBackend(shader, backend);
      recompiled++;
    }
  }
  bumpShaderLibraryGeneration(assetKey);
  debugPrint(
    'flutter_scene (web): recompiled $recompiled shader(s) from "$assetKey"',
  );
}

/// Recompiles [library]'s shaders in place from regenerated bundle [bytes]
/// (shader identities are preserved so material references and pipeline-cache
/// keys stay valid; entries new to the bundle are added). Returns an error
/// description, or null on success.
Future<String?> _reinitializeShaderLibraryFromBytesAsync(
  ShaderLibrary library,
  ByteData bytes,
) async {
  try {
    registerShaderLibrarySource(library, ShaderLibrarySource(bytes: bytes));
    final webGl = library.webGl;
    for (final MapEntry(key: name, value: backend)
        in WebGlShaderLibrary._entriesOf(bytes).entries) {
      webGl._entries[name] = backend;
      final existing = webGl._shaders[name];
      if (existing != null) {
        WebGlShaderLibrary._populateFromBackend(existing, backend);
      }
    }
    return null;
  } catch (e) {
    return '$e';
  }
}

/// Compile a map of inline GLSL ES 1.00 sources into a ShaderLibrary.
/// Web-specific; on native targets this throws.
ShaderLibrary _compileShaderLibraryInline(
  Map<String, ({String source, ShaderStage stage})> shaders,
) => WebGlShaderLibrary.fromInlineMap(shaders);
