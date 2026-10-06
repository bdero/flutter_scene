part of 'webgpu_backend.dart';

/// One member of a uniform struct, as the sidecar reflects it.
typedef _UniformMember = ({String name, int offset});

/// A uniform block: where it binds and how its members are laid out.
final class _UniformBlock {
  _UniformBlock(
    this.name,
    this.group,
    this.binding,
    this.size,
    this.members, {
    required this.declared,
  });

  final String name;
  final int group;
  final int binding;
  final int size;
  final List<_UniformMember> members;

  /// Whether the WGSL still declares it. Tint drops a block nothing reads,
  /// and a layout entry for it would need a buffer bound for nothing.
  final bool declared;
}

/// A sampled texture and the split sampler that pairs with it. [shape] is
/// what the WGSL declares, or null when Tint dropped the texture as unused;
/// [samplerDeclared] is false when only the sampler was dropped, as for a
/// texture read with `textureLoad`.
typedef _TextureSlot = ({
  String name,
  int group,
  int binding,
  int sampler,
  WgslTextureShape? shape,
  bool samplerDeclared,
});

/// A vertex input the shader reads.
typedef _VertexInput = ({String name, int location, int vecSize, int offset});

/// A [Shader] compiled from the WGSL sidecar that sits next to its bundle.
///
/// The module and reflection are replaced in place on hot reload, so
/// materials and pipeline-cache keys holding the shader stay valid; the
/// pipeline cache tells a reloaded shader apart by [generation].
final class _WebGpuShader extends Shader {
  _WebGpuShader(this.stage);

  @override
  final ShaderStage stage;

  late String name;
  late GPUShaderModule module;
  late String entryPoint;
  final Map<String, _UniformBlock> uniforms = {};
  final List<_TextureSlot> textures = [];
  final List<_VertexInput> inputs = [];

  /// The WGSL type of each vertex input the entry point declares, by
  /// location. A layout must feed exactly these, with a matching scalar.
  final Map<int, String> declaredInputs = {};

  /// The varyings at the stage boundary by location, as their WGSL type and
  /// interpolation: what a vertex shader writes, or what a fragment shader
  /// reads. A pipeline is valid only if the second is a subset of the first.
  final Map<int, String> varyings = {};

  /// Bytes per vertex implied by the inputs, for a pipeline built without an
  /// explicit layout.
  int vertexStride = 0;

  int generation = 0;

  @override
  UniformSlot getUniformSlot(String uniformName) =>
      _WebGpuUniformSlot(this, uniformName);

  /// Compiles [entry] and replaces this shader's module and reflection.
  Future<void> _populate(
    GPUDevice device,
    String name,
    Map<String, Object?> entry,
  ) async {
    final wgsl = entry['wgsl']! as String;
    final candidate = device.createShaderModule(
      _obj({'code': wgsl, 'label': name}),
    );
    final info = await candidate.getCompilationInfo().toDart;
    final errors = [
      for (final m in info.messages.toDart)
        if (m.type == 'error') '${m.lineNum}:${m.linePos} ${m.message}',
    ];
    if (errors.isNotEmpty) {
      throw StateError(
        'WGSL for "$name" did not compile:\n${errors.join('\n')}',
      );
    }
    this.name = name;
    module = candidate;
    entryPoint = entry['entryPoint']! as String;

    final declared = {
      for (final d in parseWgslDeclarations(wgsl)) (d.group, d.binding): d,
    };
    uniforms.clear();
    for (final u in (entry['uniforms']! as List).cast<Map>()) {
      uniforms[u['name'] as String] = _UniformBlock(
        u['name'] as String,
        u['group'] as int,
        u['binding'] as int,
        u['size'] as int,
        [
          for (final f in (u['fields']! as List).cast<Map>())
            (name: f['name'] as String, offset: f['offset'] as int),
        ],
        declared: declared.containsKey((u['group'], u['binding'])),
      );
    }
    textures
      ..clear()
      ..addAll([
        for (final t in (entry['textures']! as List).cast<Map>())
          (
            name: t['name'] as String,
            group: t['group'] as int,
            binding: t['binding'] as int,
            sampler: t['sampler'] as int,
            shape: switch (declared[(t['group'], t['binding'])]) {
              final d? => wgslTextureShape(d.type),
              null => null,
            },
            samplerDeclared: declared.containsKey((t['group'], t['sampler'])),
          ),
      ]);
    inputs
      ..clear()
      ..addAll([
        for (final i in (entry['inputs']! as List).cast<Map>())
          (
            name: i['name'] as String,
            location: i['location'] as int,
            vecSize: i['vecSize'] as int,
            offset: i['offset'] as int,
          ),
      ]);
    var stride = 0;
    for (final input in inputs) {
      final end = input.offset + input.vecSize * 4;
      if (end > stride) stride = end;
    }
    vertexStride = stride;
    declaredInputs
      ..clear()
      ..addAll(stage == ShaderStage.vertex ? _entryInputs(wgsl) : const {});
    varyings
      ..clear()
      ..addAll(
        stage == ShaderStage.vertex
            ? _vertexOutputs(wgsl)
            : _fragmentInputs(wgsl),
      );
    generation++;
  }
}

/// The `@location` parameters of a Tint-emitted `@vertex fn main(...)`.
Map<int, String> _entryInputs(String wgsl) {
  final entry = _vertexEntry.firstMatch(wgsl);
  if (entry == null) return const {};
  return {
    for (final m in _locationParam.allMatches(entry.group(1)!))
      int.parse(m.group(1)!): m.group(2)!,
  };
}

/// The `@location` members of the struct a Tint-emitted vertex entry point
/// returns.
Map<int, String> _vertexOutputs(String wgsl) {
  final returned = _vertexReturn.firstMatch(wgsl)?.group(1);
  if (returned == null) return const {};
  final body = RegExp(
    'struct\\s+$returned\\s*\\{([^}]*)\\}',
  ).firstMatch(wgsl)?.group(1);
  return body == null ? const {} : _varyings(body);
}

/// The `@location` parameters of a Tint-emitted fragment entry point.
Map<int, String> _fragmentInputs(String wgsl) {
  final params = _fragmentEntry.firstMatch(wgsl)?.group(1);
  return params == null ? const {} : _varyings(params);
}

Map<int, String> _varyings(String declarations) => {
  for (final m in _varying.allMatches(declarations))
    int.parse(m.group(1)!): '${m.group(3)}${_interpolation(m.group(2))}',
};

/// An `@interpolate` argument list in a form two equal declarations share,
/// with the defaults WebGPU fills in written out.
String _interpolation(String? arguments) {
  final parts = (arguments ?? 'perspective').replaceAll(' ', '').split(',');
  if (parts.first == 'flat') return ' flat';
  return ' ${parts.first}, ${parts.length > 1 ? parts[1] : 'center'}';
}

final _vertexEntry = RegExp(r'@vertex\s*fn\s+\w+\s*\(([^{]*)\)\s*(?:->|\{)');
final _vertexReturn = RegExp(r'@vertex\s*fn\s+\w+\s*\([^{]*\)\s*->\s*(\w+)');
final _fragmentEntry = RegExp(
  r'@fragment\s*fn\s+\w+\s*\(([^{]*)\)\s*(?:->|\{)',
);
final _varying = RegExp(
  r'@location\((\d+)u?\)\s*(?:@interpolate\(([^)]*)\)\s*)?\w+\s*:\s*([\w<>]+)',
);
final _locationParam = RegExp(
  r'@location\((\d+)u?\)\s*(?:@interpolate\([^)]*\)\s*)?\w+\s*:\s*([\w<>]+)',
);

final class _WebGpuUniformSlot extends UniformSlot {
  _WebGpuUniformSlot(this.shader, this.uniformName);

  @override
  final _WebGpuShader shader;

  @override
  final String uniformName;

  @override
  int? get sizeInBytes => shader.uniforms[uniformName]?.size;

  @override
  int? getMemberOffsetInBytes(String memberName) {
    final block = shader.uniforms[uniformName];
    if (block == null) return null;
    for (final member in block.members) {
      if (member.name == memberName) return member.offset;
    }
    return null;
  }
}

final class _WebGpuShaderLibrary extends ShaderLibrary {
  _WebGpuShaderLibrary._(this._shaders);

  final Map<String, _WebGpuShader> _shaders;

  /// Live shaders by the asset they came from, for hot reload.
  static final Map<String, Map<String, WeakReference<_WebGpuShader>>>
  _shadersByAsset = {};

  @override
  Shader? operator [](String shaderName) => _shaders[shaderName];

  /// Compiles every shader in [sidecarJson], after checking it was built with
  /// exactly [bundle].
  static Future<_WebGpuShaderLibrary> fromSidecar(
    GPUDevice device,
    Uint8List bundle,
    String sidecarJson, {
    required String source,
  }) async {
    final sidecar = _checkedSidecar(bundle, sidecarJson, source: source);
    final shaders = <String, _WebGpuShader>{};
    for (final MapEntry(:key, :value)
        in (sidecar['shaders']! as Map).cast<String, Map>().entries) {
      final shader = _WebGpuShader(
        value['stage'] == 'fragment'
            ? ShaderStage.fragment
            : ShaderStage.vertex,
      );
      await shader._populate(device, key, value.cast<String, Object?>());
      shaders[key] = shader;
    }
    return _WebGpuShaderLibrary._(shaders);
  }

  static Map<String, Object?> _checkedSidecar(
    Uint8List bundle,
    String sidecarJson, {
    required String source,
  }) {
    final sidecar = (jsonDecode(sidecarJson) as Map).cast<String, Object?>();
    final format = sidecar['format'];
    if (format != 2) {
      throw StateError(
        'The WGSL sidecar for "$source" has format $format; this build reads '
        'format 2. Rebuild so the hook rewrites it.',
      );
    }
    final expected = sidecar['bundle'];
    final actual = sidecarBundleHash(bundle);
    if (expected != actual) {
      throw StateError(
        'The WGSL sidecar for "$source" was built with a different bundle '
        '($expected, not $actual). A cache in front of the server may be '
        'serving a stale file; rebuild and reload.',
      );
    }
    return sidecar;
  }
}

/// Where a bundle's WGSL sidecar is served from.
String _sidecarKeyFor(String bundleKey) => '$bundleKey.wgsl.json';

Future<(Uint8List, String)> _loadBundleAndSidecar(String assetKey) async {
  final data = await loadGeneratedAsset(assetKey);
  final bundle = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  try {
    return (bundle, await loadGeneratedAssetString(_sidecarKeyFor(assetKey)));
  } on FlutterError {
    throw StateError(
      'The shader bundle "$assetKey" has no WGSL sidecar, which the WebGPU '
      'backend needs. Set `flutter_scene_webgpu: true` under '
      '`hooks: user_defines:` for the package that builds it, and build raw '
      'shader bundles with buildTargetShaderBundleJson rather than calling '
      'flutter_gpu_shaders directly.',
    );
  }
}

Future<ShaderLibrary?> _loadShaderLibraryAsync(
  _WebGpuContext context,
  String assetKey,
) async {
  final (bundle, sidecar) = await _loadBundleAndSidecar(assetKey);
  final library = await _WebGpuShaderLibrary.fromSidecar(
    context.device.device,
    bundle,
    sidecar,
    source: assetKey,
  );
  _WebGpuShaderLibrary._shadersByAsset[assetKey] = {
    for (final MapEntry(:key, :value) in library._shaders.entries)
      key: WeakReference(value),
  };
  registerShaderLibrarySource(library, ShaderLibrarySource(assetKey: assetKey));
  return library;
}

/// Recompiles every live shader loaded from [assetKey] in place.
Future<void> _reinitializeShaderLibraryAsync(
  _WebGpuContext context,
  String assetKey,
) async {
  final tracked = _WebGpuShaderLibrary._shadersByAsset[assetKey];
  if (tracked == null) {
    debugPrint(
      'flutter_scene (WebGPU): no shaders were loaded from "$assetKey"; '
      'nothing to reload',
    );
    return;
  }
  tracked.removeWhere((_, shader) => shader.target == null);
  if (tracked.isEmpty) {
    _WebGpuShaderLibrary._shadersByAsset.remove(assetKey);
    return;
  }
  final (bundle, sidecarJson) = await _loadBundleAndSidecar(assetKey);
  final sidecar = _WebGpuShaderLibrary._checkedSidecar(
    bundle,
    sidecarJson,
    source: assetKey,
  );
  final entries = (sidecar['shaders']! as Map).cast<String, Map>();
  for (final MapEntry(:key, :value) in tracked.entries) {
    final entry = entries[key];
    final shader = value.target;
    if (entry == null || shader == null) continue;
    await shader._populate(
      context.device.device,
      key,
      entry.cast<String, Object?>(),
    );
  }
}

/// Compiles a library straight from a bundle and its sidecar text, for
/// tests that serve neither as assets.
@visibleForTesting
Future<ShaderLibrary> webGpuShaderLibraryFromSidecar(
  Uint8List bundle,
  String sidecarJson,
) {
  final backend = gpuContext as _WebGpuContext;
  return _WebGpuShaderLibrary.fromSidecar(
    backend.device.device,
    bundle,
    sidecarJson,
    source: 'test',
  );
}

/// Recompiles every shader of [library] in place from [sidecarJson], as a
/// hot reload does, for tests that serve no assets.
@visibleForTesting
Future<void> webGpuReloadShaderLibrary(
  ShaderLibrary library,
  Uint8List bundle,
  String sidecarJson,
) async {
  final device = (gpuContext as _WebGpuContext).device.device;
  final sidecar = _WebGpuShaderLibrary._checkedSidecar(
    bundle,
    sidecarJson,
    source: 'test',
  );
  final entries = (sidecar['shaders']! as Map).cast<String, Map>();
  for (final MapEntry(:key, :value)
      in (library as _WebGpuShaderLibrary)._shaders.entries) {
    final entry = entries[key];
    if (entry != null) {
      await value._populate(device, key, entry.cast<String, Object?>());
    }
  }
}

/// What a shader exposes to a test: its uniform blocks, textures, and inputs.
@visibleForTesting
({
  int generation,
  List<String> uniforms,
  List<(String, int, int)> textures,
  List<(String, int)> inputs,
  int vertexStride,
})
webGpuDescribeShader(Shader shader) {
  final s = shader as _WebGpuShader;
  return (
    generation: s.generation,
    uniforms: [for (final u in s.uniforms.values) '${u.name}@${u.binding}'],
    textures: [for (final t in s.textures) (t.name, t.binding, t.sampler)],
    inputs: [for (final i in s.inputs) (i.name, i.location)],
    vertexStride: s.vertexStride,
  );
}
