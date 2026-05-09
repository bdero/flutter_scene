import 'package:vector_math/vector_math.dart';

import 'types.dart';

GltfDocument parseGltfJson(Map<String, Object?> json) {
  return GltfDocument(
    scene: json['scene'] as int?,
    scenes: _list(json['scenes'], _parseScene),
    nodes: _list(json['nodes'], _parseNode),
    meshes: _list(json['meshes'], _parseMesh),
    accessors: _list(json['accessors'], _parseAccessor),
    bufferViews: _list(json['bufferViews'], _parseBufferView),
    buffers: _list(json['buffers'], _parseBuffer),
    materials: _list(json['materials'], _parseMaterial),
    textures: _list(json['textures'], _parseTexture),
    images: _list(json['images'], _parseImage),
    samplers: _list(json['samplers'], _parseSampler),
    skins: _list(json['skins'], _parseSkin),
    animations: _list(json['animations'], _parseAnimation),
  );
}

List<T> _list<T>(Object? array, T Function(Map<String, Object?>) f) {
  if (array == null) return const [];
  return (array as List).map((e) => f(e as Map<String, Object?>)).toList();
}

GltfScene _parseScene(Map<String, Object?> j) {
  return GltfScene(
    name: j['name'] as String?,
    nodes: ((j['nodes'] as List?) ?? const []).cast<int>(),
  );
}

GltfNode _parseNode(Map<String, Object?> j) {
  Matrix4? matrix;
  Vector3? translation;
  Quaternion? rotation;
  Vector3? scale;
  if (j['matrix'] is List) {
    final m = (j['matrix'] as List)
        .cast<num>()
        .map((e) => e.toDouble())
        .toList(growable: false);
    matrix = Matrix4.fromList(m);
  }
  if (j['translation'] is List) {
    final t = (j['translation'] as List).cast<num>();
    translation = Vector3(t[0].toDouble(), t[1].toDouble(), t[2].toDouble());
  }
  if (j['rotation'] is List) {
    final r = (j['rotation'] as List).cast<num>();
    rotation = Quaternion(
      r[0].toDouble(),
      r[1].toDouble(),
      r[2].toDouble(),
      r[3].toDouble(),
    );
  }
  if (j['scale'] is List) {
    final s = (j['scale'] as List).cast<num>();
    scale = Vector3(s[0].toDouble(), s[1].toDouble(), s[2].toDouble());
  }
  return GltfNode(
    name: j['name'] as String?,
    mesh: j['mesh'] as int?,
    skin: j['skin'] as int?,
    children: ((j['children'] as List?) ?? const []).cast<int>(),
    matrix: matrix,
    translation: translation,
    rotation: rotation,
    scale: scale,
  );
}

GltfMesh _parseMesh(Map<String, Object?> j) {
  final primitives = ((j['primitives'] as List?) ?? const [])
      .map((p) {
        final pj = p as Map<String, Object?>;
        final attrs =
            (pj['attributes'] as Map?)?.cast<String, int>() ??
            const <String, int>{};
        return GltfMeshPrimitive(
          attributes: attrs,
          indices: pj['indices'] as int?,
          material: pj['material'] as int?,
          mode: (pj['mode'] as int?) ?? 4,
        );
      })
      .toList(growable: false);
  return GltfMesh(name: j['name'] as String?, primitives: primitives);
}

GltfAccessor _parseAccessor(Map<String, Object?> j) {
  return GltfAccessor(
    componentType: GltfComponentType.fromGlValue(j['componentType'] as int),
    count: j['count'] as int,
    type: GltfAccessorType.fromName(j['type'] as String),
    bufferView: j['bufferView'] as int?,
    byteOffset: (j['byteOffset'] as int?) ?? 0,
    normalized: (j['normalized'] as bool?) ?? false,
  );
}

GltfBufferView _parseBufferView(Map<String, Object?> j) {
  return GltfBufferView(
    buffer: j['buffer'] as int,
    byteLength: j['byteLength'] as int,
    byteOffset: (j['byteOffset'] as int?) ?? 0,
    byteStride: j['byteStride'] as int?,
  );
}

GltfBuffer _parseBuffer(Map<String, Object?> j) {
  return GltfBuffer(
    byteLength: j['byteLength'] as int,
    uri: j['uri'] as String?,
  );
}

GltfMaterial _parseMaterial(Map<String, Object?> j) {
  GltfPbrMetallicRoughness? pbr;
  if (j['pbrMetallicRoughness'] is Map) {
    final p = j['pbrMetallicRoughness'] as Map<String, Object?>;
    pbr = GltfPbrMetallicRoughness(
      baseColorFactor:
          p['baseColorFactor'] is List
              ? (p['baseColorFactor'] as List)
                  .cast<num>()
                  .map((e) => e.toDouble())
                  .toList(growable: false)
              : const [1.0, 1.0, 1.0, 1.0],
      baseColorTexture: _parseTextureInfo(p['baseColorTexture']),
      metallicFactor: ((p['metallicFactor'] as num?) ?? 1.0).toDouble(),
      roughnessFactor: ((p['roughnessFactor'] as num?) ?? 1.0).toDouble(),
      metallicRoughnessTexture: _parseTextureInfo(
        p['metallicRoughnessTexture'],
      ),
    );
  }
  final emissive = j['emissiveFactor'];
  final extensions = j['extensions'] as Map?;
  return GltfMaterial(
    name: j['name'] as String?,
    pbrMetallicRoughness: pbr,
    normalTexture: _parseTextureInfo(j['normalTexture']),
    occlusionTexture: _parseTextureInfo(j['occlusionTexture']),
    emissiveTexture: _parseTextureInfo(j['emissiveTexture']),
    emissiveFactor:
        emissive is List
            ? emissive
                .cast<num>()
                .map((e) => e.toDouble())
                .toList(growable: false)
            : const [0.0, 0.0, 0.0],
    alphaMode: (j['alphaMode'] as String?) ?? 'OPAQUE',
    alphaCutoff: ((j['alphaCutoff'] as num?) ?? 0.5).toDouble(),
    doubleSided: (j['doubleSided'] as bool?) ?? false,
    unlit: extensions?.containsKey('KHR_materials_unlit') ?? false,
  );
}

GltfTextureInfo? _parseTextureInfo(Object? j) {
  if (j is! Map) return null;
  final m = j as Map<String, Object?>;
  return GltfTextureInfo(
    index: m['index'] as int,
    texCoord: (m['texCoord'] as int?) ?? 0,
    scale: (m['scale'] as num?)?.toDouble(),
    strength: (m['strength'] as num?)?.toDouble(),
  );
}

GltfTexture _parseTexture(Map<String, Object?> j) {
  return GltfTexture(
    source: j['source'] as int?,
    sampler: j['sampler'] as int?,
  );
}

GltfImage _parseImage(Map<String, Object?> j) {
  return GltfImage(
    uri: j['uri'] as String?,
    bufferView: j['bufferView'] as int?,
    mimeType: j['mimeType'] as String?,
  );
}

GltfSampler _parseSampler(Map<String, Object?> j) {
  return GltfSampler(
    magFilter: j['magFilter'] as int?,
    minFilter: j['minFilter'] as int?,
    wrapS: (j['wrapS'] as int?) ?? 10497,
    wrapT: (j['wrapT'] as int?) ?? 10497,
  );
}

GltfSkin _parseSkin(Map<String, Object?> j) {
  return GltfSkin(
    name: j['name'] as String?,
    inverseBindMatrices: j['inverseBindMatrices'] as int?,
    skeleton: j['skeleton'] as int?,
    joints: ((j['joints'] as List?) ?? const []).cast<int>(),
  );
}

GltfAnimation _parseAnimation(Map<String, Object?> j) {
  final channels = ((j['channels'] as List?) ?? const [])
      .map((c) {
        final cj = c as Map<String, Object?>;
        final target = cj['target'] as Map<String, Object?>;
        return GltfAnimationChannel(
          sampler: cj['sampler'] as int,
          targetNode: target['node'] as int?,
          targetPath: target['path'] as String,
        );
      })
      .toList(growable: false);
  final samplers = ((j['samplers'] as List?) ?? const [])
      .map((s) {
        final sj = s as Map<String, Object?>;
        return GltfAnimationSampler(
          input: sj['input'] as int,
          output: sj['output'] as int,
          interpolation: (sj['interpolation'] as String?) ?? 'LINEAR',
        );
      })
      .toList(growable: false);
  return GltfAnimation(
    name: j['name'] as String?,
    channels: channels,
    samplers: samplers,
  );
}
