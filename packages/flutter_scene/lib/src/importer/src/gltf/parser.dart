import 'package:vector_math/vector_math.dart';

import 'extensions.dart';
import 'types.dart';
import 'warnings.dart';

GltfDocument parseGltfJson(Map<String, Object?> json) {
  // Required-extension validation happens before any buffer/image work: per
  // spec, a required extension this engine can't parse means the whole file
  // is refused rather than crashing later or rendering garbage.
  final extensionsRequired =
      (json['extensionsRequired'] as List?)?.cast<String>() ?? const [];
  final unsupportedRequired = [
    for (final name in extensionsRequired)
      if (!kRecognizedGltfExtensions.contains(name)) name,
  ];
  if (unsupportedRequired.isNotEmpty) {
    throw UnsupportedRequiredExtensionException(unsupportedRequired);
  }

  // An extensionsUsed entry this engine doesn't recognize is safe to ignore
  // (the spec only requires refusing unsupported *required* extensions), but
  // still worth surfacing so a caller notices missing functionality.
  final extensionsUsed =
      (json['extensionsUsed'] as List?)?.cast<String>() ?? const [];
  final warnings = [
    for (final name in extensionsUsed)
      if (!kRecognizedGltfExtensions.contains(name))
        GltfImportWarning(
          kPlannedGltfExtensions.contains(name)
              ? 'glTF uses extension "$name" (support planned), ignoring'
              : 'glTF uses unrecognized extension "$name", ignoring',
        ),
  ];

  // KHR_lights_punctual declares its lights at the document's extensions.
  final docExtensions = json['extensions'] as Map?;
  final punctual = docExtensions?['KHR_lights_punctual'] as Map?;
  final variants = docExtensions?['KHR_materials_variants'] as Map?;
  final imageBased = docExtensions?['EXT_lights_image_based'] as Map?;
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
    lights: _list(punctual?['lights'], _parsePunctualLight),
    imageBasedLights: _list(imageBased?['lights'], _parseImageBasedLight),
    materialsVariants: [
      for (final v in (variants?['variants'] as List?) ?? const [])
        ((v as Map)['name'] as String?) ?? '',
    ],
    warnings: warnings,
  );
}

GltfPunctualLight _parsePunctualLight(Map<String, Object?> j) {
  Vector3? color;
  if (j['color'] is List) {
    final c = (j['color'] as List).cast<num>();
    color = Vector3(c[0].toDouble(), c[1].toDouble(), c[2].toDouble());
  }
  final spot = j['spot'] as Map?;
  return GltfPunctualLight(
    name: j['name'] as String?,
    type: j['type'] as String? ?? 'point',
    color: color,
    intensity: (j['intensity'] as num?)?.toDouble() ?? 1.0,
    range: (j['range'] as num?)?.toDouble(),
    innerConeAngle: (spot?['innerConeAngle'] as num?)?.toDouble() ?? 0.0,
    outerConeAngle:
        (spot?['outerConeAngle'] as num?)?.toDouble() ?? 0.7853981633974483,
  );
}

GltfImageBasedLight _parseImageBasedLight(Map<String, Object?> j) {
  Quaternion? rotation;
  if (j['rotation'] is List) {
    final r = (j['rotation'] as List).cast<num>();
    rotation = Quaternion(
      r[0].toDouble(),
      r[1].toDouble(),
      r[2].toDouble(),
      r[3].toDouble(),
    );
  }
  final coefficients = <Vector3>[];
  for (final c in (j['irradianceCoefficients'] as List?) ?? const []) {
    final rgb = (c as List).cast<num>();
    coefficients.add(
      Vector3(rgb[0].toDouble(), rgb[1].toDouble(), rgb[2].toDouble()),
    );
  }
  if (coefficients.isNotEmpty && coefficients.length != 9) {
    throw FormatException(
      'EXT_lights_image_based irradianceCoefficients must hold 9 RGB triples, '
      'got ${coefficients.length}',
    );
  }
  return GltfImageBasedLight(
    name: j['name'] as String?,
    rotation: rotation,
    intensity: (j['intensity'] as num?)?.toDouble() ?? 1.0,
    irradianceCoefficients: coefficients,
    specularImageSize: (j['specularImageSize'] as num?)?.toInt() ?? 0,
    specularImages: [
      for (final level in (j['specularImages'] as List?) ?? const [])
        (level as List).cast<num>().map((e) => e.toInt()).toList(),
    ],
  );
}

List<T> _list<T>(Object? array, T Function(Map<String, Object?>) f) {
  if (array == null) return const [];
  return (array as List).map((e) => f(e as Map<String, Object?>)).toList();
}

GltfScene _parseScene(Map<String, Object?> j) {
  final imageBased =
      (j['extensions'] as Map?)?['EXT_lights_image_based'] as Map?;
  return GltfScene(
    name: j['name'] as String?,
    nodes: ((j['nodes'] as List?) ?? const []).cast<int>(),
    imageBasedLight: (imageBased?['light'] as num?)?.toInt(),
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
  final nodeExtensions = j['extensions'] as Map?;
  final punctual = nodeExtensions?['KHR_lights_punctual'] as Map?;
  return GltfNode(
    name: j['name'] as String?,
    mesh: j['mesh'] as int?,
    skin: j['skin'] as int?,
    light: punctual?['light'] as int?,
    children: ((j['children'] as List?) ?? const []).cast<int>(),
    matrix: matrix,
    translation: translation,
    rotation: rotation,
    scale: scale,
    weights: _numList(j['weights']),
  );
}

GltfMesh _parseMesh(Map<String, Object?> j) {
  final primitives = ((j['primitives'] as List?) ?? const [])
      .map((p) {
        final pj = p as Map<String, Object?>;
        final attrs =
            (pj['attributes'] as Map?)?.cast<String, int>() ??
            const <String, int>{};
        // KHR_materials_variants: flatten each mapping's variant list into
        // variant index -> material index. Later mappings do not overwrite
        // earlier ones (the spec forbids a variant appearing twice).
        final variantMappings = <int, int>{};
        final variantsExt =
            (pj['extensions'] as Map?)?['KHR_materials_variants'] as Map?;
        for (final m in (variantsExt?['mappings'] as List?) ?? const []) {
          final mapping = m as Map;
          final material = mapping['material'] as int?;
          if (material == null) continue;
          for (final v in (mapping['variants'] as List?) ?? const []) {
            variantMappings.putIfAbsent(v as int, () => material);
          }
        }
        // KHR_draco_mesh_compression: the compressed payload's buffer view
        // plus the attribute name to Draco attribute id map.
        final dracoExt =
            (pj['extensions'] as Map?)?['KHR_draco_mesh_compression'] as Map?;
        GltfDracoCompression? draco;
        if (dracoExt != null) {
          draco = GltfDracoCompression(
            bufferView: dracoExt['bufferView'] as int,
            attributes:
                (dracoExt['attributes'] as Map?)?.cast<String, int>() ??
                const {},
          );
        }
        return GltfMeshPrimitive(
          attributes: attrs,
          indices: pj['indices'] as int?,
          material: pj['material'] as int?,
          mode: (pj['mode'] as int?) ?? 4,
          variantMappings: variantMappings,
          draco: draco,
          targets: [
            for (final t in (pj['targets'] as List?) ?? const [])
              (t as Map).cast<String, int>(),
          ],
        );
      })
      .toList(growable: false);
  final extras = j['extras'] as Map?;
  return GltfMesh(
    name: j['name'] as String?,
    primitives: primitives,
    weights: _numList(j['weights']) ?? const [],
    targetNames: [
      for (final name in (extras?['targetNames'] as List?) ?? const [])
        name as String,
    ],
  );
}

GltfAccessor _parseAccessor(Map<String, Object?> j) {
  return GltfAccessor(
    componentType: GltfComponentType.fromGlValue(j['componentType'] as int),
    count: j['count'] as int,
    type: GltfAccessorType.fromName(j['type'] as String),
    bufferView: j['bufferView'] as int?,
    byteOffset: (j['byteOffset'] as int?) ?? 0,
    normalized: (j['normalized'] as bool?) ?? false,
    min: _numList(j['min']),
    max: _numList(j['max']),
    sparse: _parseAccessorSparse(j['sparse']),
  );
}

GltfAccessorSparse? _parseAccessorSparse(Object? raw) {
  if (raw is! Map) return null;
  final indices = raw['indices'] as Map<String, Object?>;
  final values = raw['values'] as Map<String, Object?>;
  return GltfAccessorSparse(
    count: raw['count'] as int,
    indicesBufferView: indices['bufferView'] as int,
    indicesByteOffset: (indices['byteOffset'] as int?) ?? 0,
    indicesComponentType: GltfComponentType.fromGlValue(
      indices['componentType'] as int,
    ),
    valuesBufferView: values['bufferView'] as int,
    valuesByteOffset: (values['byteOffset'] as int?) ?? 0,
  );
}

List<double>? _numList(Object? raw) {
  if (raw is! List) return null;
  return [for (final v in raw) (v as num).toDouble()];
}

GltfBufferView _parseBufferView(Map<String, Object?> j) {
  final meshopt = _extension(
    j['extensions'] as Map?,
    'EXT_meshopt_compression',
  );
  return GltfBufferView(
    buffer: j['buffer'] as int,
    byteLength: j['byteLength'] as int,
    byteOffset: (j['byteOffset'] as int?) ?? 0,
    byteStride: j['byteStride'] as int?,
    meshopt: meshopt == null
        ? null
        : GltfMeshoptCompression(
            buffer: meshopt['buffer'] as int,
            byteOffset: (meshopt['byteOffset'] as int?) ?? 0,
            byteLength: meshopt['byteLength'] as int,
            byteStride: meshopt['byteStride'] as int,
            count: meshopt['count'] as int,
            mode: meshopt['mode'] as String,
            filter: (meshopt['filter'] as String?) ?? 'NONE',
          ),
  );
}

GltfBuffer _parseBuffer(Map<String, Object?> j) {
  final meshopt = _extension(
    j['extensions'] as Map?,
    'EXT_meshopt_compression',
  );
  return GltfBuffer(
    byteLength: j['byteLength'] as int,
    uri: j['uri'] as String?,
    meshoptFallback: (meshopt?['fallback'] as bool?) ?? false,
  );
}

GltfMaterial _parseMaterial(Map<String, Object?> j) {
  GltfPbrMetallicRoughness? pbr;
  if (j['pbrMetallicRoughness'] is Map) {
    final p = j['pbrMetallicRoughness'] as Map<String, Object?>;
    pbr = GltfPbrMetallicRoughness(
      baseColorFactor: p['baseColorFactor'] is List
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
  final anisotropy = _extension(extensions, 'KHR_materials_anisotropy');
  final clearcoat = _extension(extensions, 'KHR_materials_clearcoat');
  final diffuseTransmission = _extension(
    extensions,
    'KHR_materials_diffuse_transmission',
  );
  final dispersion = _extension(extensions, 'KHR_materials_dispersion');
  final emissiveStrength = _extension(
    extensions,
    'KHR_materials_emissive_strength',
  );
  final ior = _extension(extensions, 'KHR_materials_ior');
  final iridescence = _extension(extensions, 'KHR_materials_iridescence');
  final sheen = _extension(extensions, 'KHR_materials_sheen');
  final specular = _extension(extensions, 'KHR_materials_specular');
  final transmission = _extension(extensions, 'KHR_materials_transmission');
  final volume = _extension(extensions, 'KHR_materials_volume');
  return GltfMaterial(
    name: j['name'] as String?,
    pbrMetallicRoughness: pbr,
    normalTexture: _parseTextureInfo(j['normalTexture']),
    occlusionTexture: _parseTextureInfo(j['occlusionTexture']),
    emissiveTexture: _parseTextureInfo(j['emissiveTexture']),
    emissiveFactor: emissive is List
        ? emissive.cast<num>().map((e) => e.toDouble()).toList(growable: false)
        : const [0.0, 0.0, 0.0],
    alphaMode: (j['alphaMode'] as String?) ?? 'OPAQUE',
    alphaCutoff: ((j['alphaCutoff'] as num?) ?? 0.5).toDouble(),
    doubleSided: (j['doubleSided'] as bool?) ?? false,
    unlit: extensions?.containsKey('KHR_materials_unlit') ?? false,
    anisotropy: anisotropy == null
        ? null
        : GltfMaterialAnisotropy(
            strength: _double(anisotropy, 'anisotropyStrength', 0.0),
            rotation: _double(anisotropy, 'anisotropyRotation', 0.0),
            texture: _parseTextureInfo(anisotropy['anisotropyTexture']),
          ),
    clearcoat: clearcoat == null
        ? null
        : GltfMaterialClearcoat(
            factor: _double(clearcoat, 'clearcoatFactor', 0.0),
            texture: _parseTextureInfo(clearcoat['clearcoatTexture']),
            roughnessFactor: _double(
              clearcoat,
              'clearcoatRoughnessFactor',
              0.0,
            ),
            roughnessTexture: _parseTextureInfo(
              clearcoat['clearcoatRoughnessTexture'],
            ),
            normalTexture: _parseTextureInfo(
              clearcoat['clearcoatNormalTexture'],
            ),
          ),
    diffuseTransmission: diffuseTransmission == null
        ? null
        : GltfMaterialDiffuseTransmission(
            factor: _double(
              diffuseTransmission,
              'diffuseTransmissionFactor',
              0.0,
            ),
            texture: _parseTextureInfo(
              diffuseTransmission['diffuseTransmissionTexture'],
            ),
            colorFactor: _vector(
              diffuseTransmission,
              'diffuseTransmissionColorFactor',
              const [1.0, 1.0, 1.0],
            ),
            colorTexture: _parseTextureInfo(
              diffuseTransmission['diffuseTransmissionColorTexture'],
            ),
          ),
    dispersion: _double(dispersion, 'dispersion', 0.0),
    emissiveStrength: _double(emissiveStrength, 'emissiveStrength', 1.0),
    ior: _double(ior, 'ior', 1.5),
    iridescence: iridescence == null
        ? null
        : GltfMaterialIridescence(
            factor: _double(iridescence, 'iridescenceFactor', 0.0),
            texture: _parseTextureInfo(iridescence['iridescenceTexture']),
            ior: _double(iridescence, 'iridescenceIor', 1.3),
            thicknessMinimum: _double(
              iridescence,
              'iridescenceThicknessMinimum',
              100.0,
            ),
            thicknessMaximum: _double(
              iridescence,
              'iridescenceThicknessMaximum',
              400.0,
            ),
            thicknessTexture: _parseTextureInfo(
              iridescence['iridescenceThicknessTexture'],
            ),
          ),
    sheen: sheen == null
        ? null
        : GltfMaterialSheen(
            colorFactor: _vector(sheen, 'sheenColorFactor', const [
              0.0,
              0.0,
              0.0,
            ]),
            colorTexture: _parseTextureInfo(sheen['sheenColorTexture']),
            roughnessFactor: _double(sheen, 'sheenRoughnessFactor', 0.0),
            roughnessTexture: _parseTextureInfo(sheen['sheenRoughnessTexture']),
          ),
    specular: specular == null
        ? null
        : GltfMaterialSpecular(
            factor: _double(specular, 'specularFactor', 1.0),
            texture: _parseTextureInfo(specular['specularTexture']),
            colorFactor: _vector(specular, 'specularColorFactor', const [
              1.0,
              1.0,
              1.0,
            ]),
            colorTexture: _parseTextureInfo(specular['specularColorTexture']),
          ),
    transmission: transmission == null
        ? null
        : GltfMaterialTransmission(
            factor: _double(transmission, 'transmissionFactor', 0.0),
            texture: _parseTextureInfo(transmission['transmissionTexture']),
          ),
    volume: volume == null
        ? null
        : GltfMaterialVolume(
            thicknessFactor: _double(volume, 'thicknessFactor', 0.0),
            thicknessTexture: _parseTextureInfo(volume['thicknessTexture']),
            attenuationDistance: _double(
              volume,
              'attenuationDistance',
              double.infinity,
            ),
            attenuationColor: _vector(volume, 'attenuationColor', const [
              1.0,
              1.0,
              1.0,
            ]),
          ),
  );
}

Map<String, Object?>? _extension(Map? extensions, String name) {
  final value = extensions?[name];
  return value is Map ? value.cast<String, Object?>() : null;
}

double _double(Map<String, Object?>? values, String key, double fallback) =>
    (values?[key] as num?)?.toDouble() ?? fallback;

List<double> _vector(
  Map<String, Object?> values,
  String key,
  List<double> fallback,
) {
  final value = values[key];
  return value is List
      ? value.cast<num>().map((e) => e.toDouble()).toList(growable: false)
      : fallback;
}

GltfTextureInfo? _parseTextureInfo(Object? j) {
  if (j is! Map) return null;
  final m = j as Map<String, Object?>;
  final transform = _extension(
    m['extensions'] as Map?,
    'KHR_texture_transform',
  );
  return GltfTextureInfo(
    index: m['index'] as int,
    texCoord: (m['texCoord'] as int?) ?? 0,
    scale: (m['scale'] as num?)?.toDouble(),
    strength: (m['strength'] as num?)?.toDouble(),
    transform: transform == null
        ? null
        : GltfTextureTransform(
            offset: _vector(transform, 'offset', const [0.0, 0.0]),
            rotation: _double(transform, 'rotation', 0.0),
            scale: _vector(transform, 'scale', const [1.0, 1.0]),
            texCoord: transform['texCoord'] as int?,
          ),
  );
}

GltfTexture _parseTexture(Map<String, Object?> j) {
  final basisu = _extension(j['extensions'] as Map?, 'KHR_texture_basisu');
  return GltfTexture(
    source: j['source'] as int?,
    sampler: j['sampler'] as int?,
    basisuSource: basisu?['source'] as int?,
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
