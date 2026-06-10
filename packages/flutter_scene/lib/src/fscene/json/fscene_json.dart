import 'dart:convert';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/canonical.dart';
import 'package:flutter_scene/src/fscene/json/jsonc.dart';
import 'package:flutter_scene/src/fscene/json/property_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// The current `.fscene` format version this build reads and writes.
const int currentFsceneVersion = 1;

/// The format feature flags this build understands. A document that lists a
/// feature outside this set in its `featuresRequired` is refused.
const Set<String> supportedFeatures = {
  'skinning',
  'prefabInstances',
  'streaming',
};

/// Upgrades a raw decoded document one version forward (version `N` to
/// `N + 1`). Indexed by source version in the migration list.
typedef FsceneMigration =
    Map<String, dynamic> Function(Map<String, dynamic> json);

// The built-in migration chain. Empty at v1 (the first version); a future
// breaking change appends a `vN -> vN+1` step here.
const List<FsceneMigration> _builtInMigrations = [];

/// Thrown when a `.fscene` document is malformed.
class FsceneFormatException implements Exception {
  /// Creates a format exception with the given [message].
  const FsceneFormatException(this.message);

  /// What is wrong with the document.
  final String message;

  @override
  String toString() => 'FsceneFormatException: $message';
}

/// Thrown when a document's version cannot be loaded (newer than supported,
/// or missing a migration step).
class FsceneVersionException implements Exception {
  /// Creates a version exception with the given [message].
  const FsceneVersionException(this.message);

  /// What went wrong with the version.
  final String message;

  @override
  String toString() => 'FsceneVersionException: $message';
}

/// Thrown when a document requires a format feature this build does not
/// support.
class FsceneUnsupportedFeatureException implements Exception {
  /// Creates an exception naming the unsupported [feature].
  const FsceneUnsupportedFeatureException(this.feature);

  /// The required feature this build does not support.
  final String feature;

  @override
  String toString() =>
      'FsceneUnsupportedFeatureException: required feature "$feature" '
      'is not supported';
}

/// Serializes [doc] to canonical `.fscene` JSON text.
String writeFscene(SceneDocument doc) => canonicalJson(encodeDocument(doc));

/// Parses a `.fscene` document from [source].
///
/// Accepts a JSONC superset on read (`//` and `/* */` comments, trailing
/// commas), runs the version migration chain, then decodes. Pass [migrations]
/// to override the built-in chain (for tests). Unknown fields are ignored.
SceneDocument readFscene(String source, {List<FsceneMigration>? migrations}) {
  final decoded = jsonDecode(stripJsonc(source));
  if (decoded is! Map) {
    throw const FsceneFormatException('Top-level value must be an object');
  }
  final migrated = migrateFscene(
    Map<String, dynamic>.from(decoded),
    migrations: migrations,
  );
  return decodeDocument(migrated);
}

/// Runs the version migration chain over a raw decoded [json] document,
/// upgrading it to [currentFsceneVersion]. Throws [FsceneVersionException]
/// for a newer-than-supported version or a missing migration step.
Map<String, dynamic> migrateFscene(
  Map<String, dynamic> json, {
  List<FsceneMigration>? migrations,
}) {
  final steps = migrations ?? _builtInMigrations;
  var version = json['fscene'] as int? ?? currentFsceneVersion;
  if (version > currentFsceneVersion) {
    throw FsceneVersionException(
      'Document version $version is newer than supported $currentFsceneVersion',
    );
  }
  while (version < currentFsceneVersion) {
    if (version >= steps.length) {
      throw FsceneVersionException('No migration from version $version');
    }
    json = steps[version](json);
    version++;
    json['fscene'] = version;
  }
  return json;
}

//-----------------------------------------------------------------------------
// Encode
//-----------------------------------------------------------------------------

/// Encodes [doc] as a JSON tree (maps, lists, and primitives).
Map<String, dynamic> encodeDocument(SceneDocument doc) {
  final prefixes = _buildPrefixMap(doc);
  String idKey(LocalId id) => '${prefixes[id] ?? 'id'}:${id.toToken()}';

  final json = <String, dynamic>{
    'fscene': doc.formatVersion,
    'documentId': doc.documentId.toToken(),
  };
  if (doc.featuresUsed.isNotEmpty) {
    json['featuresUsed'] = doc.featuresUsed.toList()..sort();
  }
  if (doc.featuresRequired.isNotEmpty) {
    json['featuresRequired'] = doc.featuresRequired.toList()..sort();
  }
  if (doc.generator != null) json['generator'] = doc.generator;
  json['stage'] = encodeStage(doc.stage);
  if (doc.resources.isNotEmpty) {
    json['resources'] = _encodeIdMap(
      doc.resources,
      idKey,
      (r) => _encodeResource(r, idKey),
    );
  }
  json['nodes'] = _encodeIdMap(doc.nodes, idKey, (n) => _encodeNode(n, idKey));
  json['roots'] = [for (final id in doc.roots) idKey(id)];
  if (doc.skins.isNotEmpty) {
    json['skins'] = _encodeIdMap(
      doc.skins,
      idKey,
      (s) => _encodeSkin(s, idKey),
    );
  }
  if (doc.animations.isNotEmpty) {
    json['animations'] = _encodeIdMap(
      doc.animations,
      idKey,
      (a) => _encodeAnimation(a, idKey),
    );
  }
  if (doc.payloads.isNotEmpty) {
    json['payloads'] = _encodeIdMap(doc.payloads, idKey, _encodePayload);
  }
  return json;
}

Map<LocalId, String> _buildPrefixMap(SceneDocument doc) {
  final prefixes = <LocalId, String>{};
  for (final id in doc.nodes.keys) {
    prefixes[id] = 'n';
  }
  for (final r in doc.resources.values) {
    prefixes[r.id] = switch (r) {
      GeometryResource() => 'geo',
      MaterialResource() => 'mat',
      TextureResource() => 'tex',
    };
  }
  for (final id in doc.skins.keys) {
    prefixes[id] = 'skin';
  }
  for (final id in doc.animations.keys) {
    prefixes[id] = 'anim';
  }
  for (final id in doc.payloads.keys) {
    prefixes[id] = 'chunk';
  }
  return prefixes;
}

Map<String, dynamic> _encodeIdMap<V>(
  Map<LocalId, V> map,
  String Function(LocalId) idKey,
  Object Function(V) encode,
) {
  final entries = map.entries.toList()
    ..sort((a, b) => a.key.toToken().compareTo(b.key.toToken()));
  return {for (final e in entries) idKey(e.key): encode(e.value)};
}

/// Encodes [s] to its canonical JSON map (also used to compare stages for
/// equality in the scene diff).
Map<String, dynamic> encodeStage(StageMetadata s) => {
  'upAxis': s.upAxis.name,
  'handedness': s.handedness.name,
  'unitsPerMeter': s.unitsPerMeter,
  'environment': switch (s.environment) {
    StudioEnvironment() => {'type': 'studio'},
    AssetEnvironment(:final asset) => {'type': 'asset', 'ref': asset.key},
    EmptyEnvironment() => {'type': 'empty'},
  },
  'environmentIntensity': s.environmentIntensity,
  'exposure': s.exposure,
  'toneMapping': s.toneMapping,
  if (s.skybox != null)
    'skybox': {
      'source': encodeSkySource(s.skybox!.source),
      'intensity': s.skybox!.intensity,
    },
  if (s.skyEnvironment != null)
    'skyEnvironment': {
      'source': encodeSkySource(s.skyEnvironment!.source),
      'refresh': s.skyEnvironment!.refresh,
      'intervalSeconds': s.skyEnvironment!.intervalSeconds,
      'faceResolution': s.skyEnvironment!.faceResolution,
      'equirectWidth': s.skyEnvironment!.equirectWidth,
    },
};

/// Encodes a sky source spec to its canonical JSON form (also used to key
/// realized sky sources for sharing).
Object encodeSkySource(SkySourceSpec source) => switch (source) {
  EnvironmentSkySpec(:final blurriness) => {
    'type': 'environment',
    'blurriness': blurriness,
  },
  FmatSkySpec(:final asset, :final properties) => {
    'type': 'fmat',
    'ref': asset.key,
    if (properties.isNotEmpty)
      'properties': {
        for (final e in properties.entries)
          e.key: encodePropertyValue(e.value, (id) => id.toToken()),
      },
  },
  GradientSkySpec s => {
    'type': 'gradient',
    'zenithColor': _vec3Json(s.zenithColor),
    'horizonColor': _vec3Json(s.horizonColor),
    'groundColor': _vec3Json(s.groundColor),
    'sunDirection': _vec3Json(s.sunDirection),
    'sunColor': _vec3Json(s.sunColor),
    'sunSharpness': s.sunSharpness,
  },
  PhysicalSkySpec s => {
    'type': 'physical',
    'sunDirection': _vec3Json(s.sunDirection),
    'sunAngularRadius': s.sunAngularRadius,
    'rayleighCoefficient': s.rayleighCoefficient,
    'rayleighColor': _vec3Json(s.rayleighColor),
    'mieCoefficient': s.mieCoefficient,
    'mieEccentricity': s.mieEccentricity,
    'mieColor': _vec3Json(s.mieColor),
    'turbidity': s.turbidity,
    'groundColor': _vec3Json(s.groundColor),
    'energy': s.energy,
  },
};

List<double> _vec3Json(Vector3 v) => [v.x, v.y, v.z];

Object _encodeResource(ResourceSpec r, String Function(LocalId) idKey) {
  switch (r) {
    case GeometryResource(
      :final vertices,
      :final indices,
      :final procedural,
      :final bounds,
    ):
      return {
        'kind': 'geometry',
        if (vertices != null) 'vertices': idKey(vertices),
        if (indices != null) 'indices': idKey(indices),
        if (procedural != null) 'procedural': _encodeProcedural(procedural),
        if (bounds != null)
          'bounds': {
            'min': [bounds.min.x, bounds.min.y, bounds.min.z],
            'max': [bounds.max.x, bounds.max.y, bounds.max.z],
          },
      };
    case TextureResource(:final payload, :final asset):
      return {
        'kind': 'texture',
        if (payload != null) 'payload': idKey(payload),
        if (asset != null) 'ref': asset.key,
      };
    case MaterialResource(:final type, :final properties, :final asset):
      return {
        'kind': 'material',
        'type': type,
        if (asset != null) 'ref': asset.key,
        if (properties.isNotEmpty)
          'properties': {
            for (final e in properties.entries)
              e.key: encodePropertyValue(e.value, idKey),
          },
      };
  }
}

Map<String, dynamic> _encodeNode(NodeSpec n, String Function(LocalId) idKey) {
  return {
    if (n.name.isNotEmpty) 'name': n.name,
    'transform': _encodeTransform(n.transform),
    if (n.children.isNotEmpty)
      'children': [for (final c in n.children) idKey(c)],
    if (n.components.isNotEmpty)
      'components': [for (final c in n.components) _encodeComponent(c, idKey)],
    if (n.layers != 1) 'layers': n.layers,
    if (n.skin != null) 'skin': idKey(n.skin!),
    if (n.instance != null) 'instance': _encodeInstance(n.instance!, idKey),
    if (n.excludeFromWindingParity) 'excludeWindingParity': true,
  };
}

Map<String, dynamic> _encodeTransform(TransformSpec t) => switch (t) {
  MatrixTransform(:final matrix) => {'matrix': matrix.storage.toList()},
  TrsTransform(:final translation, :final rotation, :final scale) => {
    'trs': {
      't': [translation.x, translation.y, translation.z],
      'r': [rotation.x, rotation.y, rotation.z, rotation.w],
      's': [scale.x, scale.y, scale.z],
    },
  },
};

Map<String, dynamic> _encodeComponent(
  ComponentSpec c,
  String Function(LocalId) idKey,
) => {
  'type': c.type,
  if (c.properties.isNotEmpty)
    'properties': {
      for (final e in c.properties.entries)
        e.key: encodePropertyValue(e.value, idKey),
    },
};

Map<String, dynamic> _encodeInstance(
  PrefabInstanceSpec p,
  String Function(LocalId) idKey,
) => {
  'source': p.source.key,
  if (p.load != LoadPolicy.eager) 'load': p.load.name,
  if (p.overrides.isNotEmpty)
    'overrides': [
      for (final o in p.overrides)
        {
          'target': idKey(o.target),
          'path': o.path,
          'value': encodePropertyValue(o.value, idKey),
        },
    ],
  if (p.addedNodes.isNotEmpty)
    'addedNodes': {
      for (final n in p.addedNodes) idKey(n.id): _encodeNode(n, idKey),
    },
  if (p.removedNodes.isNotEmpty)
    'removedNodes': [for (final id in p.removedNodes) idKey(id)],
  if (p.addedComponents.isNotEmpty)
    'addedComponents': [
      for (final c in p.addedComponents) _encodeComponent(c, idKey),
    ],
  if (p.removedComponentTypes.isNotEmpty)
    'removedComponentTypes': p.removedComponentTypes,
};

Map<String, dynamic> _encodeSkin(SkinSpec s, String Function(LocalId) idKey) =>
    {
      'joints': [for (final j in s.joints) idKey(j)],
      'inverseBindMatrices': idKey(s.inverseBindMatrices),
      if (s.skeleton != null) 'skeleton': idKey(s.skeleton!),
    };

Map<String, dynamic> _encodeAnimation(
  AnimationSpec a,
  String Function(LocalId) idKey,
) => {
  if (a.name.isNotEmpty) 'name': a.name,
  'channels': [
    for (final ch in a.channels)
      {
        'target': idKey(ch.target),
        if (ch.targetName != null) 'targetName': ch.targetName,
        'property': ch.property.name,
        'timeline': idKey(ch.timeline),
        'keyframes': idKey(ch.keyframes),
      },
  ],
};

Map<String, dynamic> _encodePayload(PayloadSpec p) => {
  'encoding': p.encoding.name,
  if (p.layout != null) 'layout': p.layout,
  if (p.format != null) 'format': p.format,
  if (p.width != null) 'width': p.width,
  if (p.height != null) 'height': p.height,
  if (p.length != null) 'length': p.length,
};

//-----------------------------------------------------------------------------
// Decode
//-----------------------------------------------------------------------------

/// Decodes a [SceneDocument] from a raw JSON tree (already migrated to the
/// current version). Throws on an unsupported required feature.
SceneDocument decodeDocument(Map<String, dynamic> json) {
  final version = json['fscene'] as int? ?? currentFsceneVersion;
  if (version != currentFsceneVersion) {
    throw FsceneVersionException(
      'Document is version $version; expected $currentFsceneVersion '
      '(run migrateFscene first)',
    );
  }

  final required =
      (json['featuresRequired'] as List?)?.cast<String>() ?? const <String>[];
  for (final feature in required) {
    if (!supportedFeatures.contains(feature)) {
      throw FsceneUnsupportedFeatureException(feature);
    }
  }

  final documentId = DocumentId.parse(json['documentId'] as String);

  final nodes = _decodeIdMap(json['nodes'], _decodeNode);
  final resources = _decodeIdMap(json['resources'], _decodeResource);
  final skins = _decodeIdMap(json['skins'], _decodeSkin);
  final animations = _decodeIdMap(json['animations'], _decodeAnimation);
  final payloads = _decodeIdMap(json['payloads'], _decodePayload);
  final roots = [
    for (final id in (json['roots'] as List? ?? const []))
      LocalId.parse(id as String),
  ];

  // Mint future ids with a fresh session that avoids every session already
  // present in the document, so new edits cannot collide with loaded ids.
  final usedSessions = <int>{};
  void collect(LocalId id) => usedSessions.add(id.session);
  nodes.keys.forEach(collect);
  resources.keys.forEach(collect);
  skins.keys.forEach(collect);
  animations.keys.forEach(collect);
  payloads.keys.forEach(collect);

  final doc = SceneDocument(
    documentId: documentId,
    allocator: IdAllocator(excludedSessions: usedSessions),
    stage: _decodeStage(json['stage'] as Map<String, dynamic>),
  );
  doc.formatVersion = version;
  doc.generator = json['generator'] as String?;
  doc.featuresUsed.addAll(
    (json['featuresUsed'] as List?)?.cast<String>() ?? const [],
  );
  doc.featuresRequired.addAll(required);
  doc.nodes.addAll(nodes);
  doc.roots.addAll(roots);
  doc.resources.addAll(resources);
  doc.skins.addAll(skins);
  doc.animations.addAll(animations);
  doc.payloads.addAll(payloads);
  return doc;
}

Map<LocalId, V> _decodeIdMap<V>(
  Object? json,
  V Function(LocalId id, Map<String, dynamic> value) decode,
) {
  if (json == null) return {};
  final out = <LocalId, V>{};
  for (final e in (json as Map).entries) {
    final id = LocalId.parse(e.key as String);
    out[id] = decode(id, Map<String, dynamic>.from(e.value as Map));
  }
  return out;
}

NodeSpec _decodeNode(LocalId id, Map<String, dynamic> json) => NodeSpec(
  id: id,
  name: json['name'] as String? ?? '',
  transform: _decodeTransform(json['transform'] as Map<String, dynamic>),
  children: [
    for (final c in (json['children'] as List? ?? const []))
      LocalId.parse(c as String),
  ],
  components: [
    for (final c in (json['components'] as List? ?? const []))
      _decodeComponent(Map<String, dynamic>.from(c as Map)),
  ],
  layers: json['layers'] as int? ?? 1,
  skin: json['skin'] != null ? LocalId.parse(json['skin'] as String) : null,
  instance: json['instance'] != null
      ? _decodeInstance(Map<String, dynamic>.from(json['instance'] as Map))
      : null,
  excludeFromWindingParity: json['excludeWindingParity'] as bool? ?? false,
);

TransformSpec _decodeTransform(Map<String, dynamic> json) {
  final matrix = json['matrix'];
  if (matrix != null) {
    return MatrixTransform(
      Matrix4.fromList([for (final e in matrix as List) _d(e)]),
    );
  }
  final trs = json['trs'] as Map<String, dynamic>;
  final t = trs['t'] as List;
  final r = trs['r'] as List;
  final s = trs['s'] as List;
  return TrsTransform(
    translation: Vector3(_d(t[0]), _d(t[1]), _d(t[2])),
    rotation: Quaternion(_d(r[0]), _d(r[1]), _d(r[2]), _d(r[3])),
    scale: Vector3(_d(s[0]), _d(s[1]), _d(s[2])),
  );
}

ComponentSpec _decodeComponent(Map<String, dynamic> json) => ComponentSpec(
  json['type'] as String,
  properties: _decodeProperties(json['properties']),
);

Map<String, PropertyValue> _decodeProperties(Object? json) => {
  if (json != null)
    for (final e in (json as Map).entries)
      e.key as String: decodePropertyValue(e.value),
};

PrefabInstanceSpec _decodeInstance(Map<String, dynamic> json) =>
    PrefabInstanceSpec(
      source: AssetRef(json['source'] as String),
      load: json['load'] == 'lazy' ? LoadPolicy.lazy : LoadPolicy.eager,
      overrides: [
        for (final o in (json['overrides'] as List? ?? const []))
          _decodeOverride(Map<String, dynamic>.from(o as Map)),
      ],
      addedNodes: [
        for (final e in (json['addedNodes'] as Map? ?? const {}).entries)
          _decodeNode(
            LocalId.parse(e.key as String),
            Map<String, dynamic>.from(e.value as Map),
          ),
      ],
      removedNodes: [
        for (final id in (json['removedNodes'] as List? ?? const []))
          LocalId.parse(id as String),
      ],
      addedComponents: [
        for (final c in (json['addedComponents'] as List? ?? const []))
          _decodeComponent(Map<String, dynamic>.from(c as Map)),
      ],
      removedComponentTypes:
          (json['removedComponentTypes'] as List?)?.cast<String>() ?? const [],
    );

PropertyOverride _decodeOverride(Map<String, dynamic> json) => PropertyOverride(
  target: LocalId.parse(json['target'] as String),
  path: json['path'] as String,
  value: decodePropertyValue(json['value']),
);

ResourceSpec _decodeResource(LocalId id, Map<String, dynamic> json) {
  final kind = json['kind'] as String;
  switch (kind) {
    case 'geometry':
      return GeometryResource(
        id,
        vertices: json['vertices'] != null
            ? LocalId.parse(json['vertices'] as String)
            : null,
        indices: json['indices'] != null
            ? LocalId.parse(json['indices'] as String)
            : null,
        procedural: json['procedural'] != null
            ? _decodeProcedural(
                Map<String, dynamic>.from(json['procedural'] as Map),
              )
            : null,
        bounds: _decodeBounds(json['bounds']),
      );
    case 'texture':
      return TextureResource(
        id,
        payload: json['payload'] != null
            ? LocalId.parse(json['payload'] as String)
            : null,
        asset: json['ref'] != null ? AssetRef(json['ref'] as String) : null,
      );
    case 'material':
      return MaterialResource(
        id,
        type: json['type'] as String,
        asset: json['ref'] != null ? AssetRef(json['ref'] as String) : null,
        properties: _decodeProperties(json['properties']),
      );
    default:
      throw FsceneFormatException('Unknown resource kind: $kind');
  }
}

Map<String, dynamic> _encodeProcedural(ProceduralGeometry p) => switch (p) {
  CuboidGeometrySpec(:final extents, :final debugColors) => {
    'shape': 'cuboid',
    'extents': [extents.x, extents.y, extents.z],
    if (debugColors) 'debugColors': true,
  },
  PlaneGeometrySpec(
    :final width,
    :final depth,
    :final segmentsX,
    :final segmentsZ,
  ) =>
    {
      'shape': 'plane',
      'width': width,
      'depth': depth,
      'segmentsX': segmentsX,
      'segmentsZ': segmentsZ,
    },
  SphereGeometrySpec(:final radius, :final segments, :final rings) => {
    'shape': 'sphere',
    'radius': radius,
    'segments': segments,
    'rings': rings,
  },
};

ProceduralGeometry _decodeProcedural(Map<String, dynamic> json) {
  final shape = json['shape'] as String;
  switch (shape) {
    case 'cuboid':
      final e = json['extents'] as List;
      return CuboidGeometrySpec(
        extents: Vector3(_d(e[0]), _d(e[1]), _d(e[2])),
        debugColors: json['debugColors'] as bool? ?? false,
      );
    case 'plane':
      return PlaneGeometrySpec(
        width: _d(json['width'] ?? 1.0),
        depth: _d(json['depth'] ?? 1.0),
        segmentsX: json['segmentsX'] as int? ?? 1,
        segmentsZ: json['segmentsZ'] as int? ?? 1,
      );
    case 'sphere':
      return SphereGeometrySpec(
        radius: _d(json['radius'] ?? 0.5),
        segments: json['segments'] as int? ?? 32,
        rings: json['rings'] as int? ?? 16,
      );
    default:
      throw FsceneFormatException('Unknown procedural geometry shape: $shape');
  }
}

BoundsSpec? _decodeBounds(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  final min = m['min'] as List;
  final max = m['max'] as List;
  return BoundsSpec(
    min: Vector3(_d(min[0]), _d(min[1]), _d(min[2])),
    max: Vector3(_d(max[0]), _d(max[1]), _d(max[2])),
  );
}

SkinSpec _decodeSkin(LocalId id, Map<String, dynamic> json) => SkinSpec(
  id,
  joints: [
    for (final j in (json['joints'] as List? ?? const []))
      LocalId.parse(j as String),
  ],
  inverseBindMatrices: LocalId.parse(json['inverseBindMatrices'] as String),
  skeleton: json['skeleton'] != null
      ? LocalId.parse(json['skeleton'] as String)
      : null,
);

AnimationSpec _decodeAnimation(LocalId id, Map<String, dynamic> json) =>
    AnimationSpec(
      id,
      name: json['name'] as String? ?? '',
      channels: [
        for (final ch in (json['channels'] as List? ?? const []))
          _decodeChannel(Map<String, dynamic>.from(ch as Map)),
      ],
    );

AnimationChannelSpec _decodeChannel(Map<String, dynamic> json) =>
    AnimationChannelSpec(
      target: LocalId.parse(json['target'] as String),
      targetName: json['targetName'] as String?,
      property: AnimationProperty.values.byName(json['property'] as String),
      timeline: LocalId.parse(json['timeline'] as String),
      keyframes: LocalId.parse(json['keyframes'] as String),
    );

PayloadSpec _decodePayload(LocalId id, Map<String, dynamic> json) =>
    PayloadSpec(
      id,
      encoding: PayloadEncoding.values.byName(json['encoding'] as String),
      layout: json['layout'] as String?,
      format: json['format'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      length: json['length'] as int?,
    );

StageMetadata _decodeStage(Map<String, dynamic> json) => StageMetadata(
  upAxis: UpAxis.values.byName(json['upAxis'] as String? ?? 'y'),
  handedness: Handedness.values.byName(
    json['handedness'] as String? ?? 'right',
  ),
  unitsPerMeter: _d(json['unitsPerMeter'] ?? 1.0),
  environment: _decodeEnvironment(json['environment']),
  environmentIntensity: _d(json['environmentIntensity'] ?? 1.0),
  exposure: _d(json['exposure'] ?? 1.0),
  toneMapping: json['toneMapping'] as String? ?? 'pbrNeutral',
  skybox: _decodeSkybox(json['skybox']),
  skyEnvironment: _decodeSkyEnvironment(json['skyEnvironment']),
);

SkyboxSpec? _decodeSkybox(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  final source = _decodeSkySource(m['source']);
  if (source == null) return null;
  return SkyboxSpec(source, intensity: _d(m['intensity'] ?? 1.0));
}

SkyEnvironmentSpec? _decodeSkyEnvironment(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  final source = _decodeSkySource(m['source']);
  if (source == null) return null;
  return SkyEnvironmentSpec(
    source,
    refresh: m['refresh'] as String? ?? 'manual',
    intervalSeconds: _d(m['intervalSeconds'] ?? 1.0),
    faceResolution: (m['faceResolution'] as num?)?.toInt() ?? 128,
    equirectWidth: (m['equirectWidth'] as num?)?.toInt() ?? 512,
  );
}

SkySourceSpec? _decodeSkySource(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  switch (m['type']) {
    case 'environment':
      return EnvironmentSkySpec(blurriness: _d(m['blurriness'] ?? 0.0));
    case 'fmat':
      return FmatSkySpec(
        AssetRef(m['ref'] as String),
        properties: {
          for (final e in ((m['properties'] as Map?) ?? const {}).entries)
            e.key as String: decodePropertyValue(e.value),
        },
      );
    case 'gradient':
      final s = GradientSkySpec();
      _setVec3(m['zenithColor'], (v) => s.zenithColor = v);
      _setVec3(m['horizonColor'], (v) => s.horizonColor = v);
      _setVec3(m['groundColor'], (v) => s.groundColor = v);
      _setVec3(m['sunDirection'], (v) => s.sunDirection = v);
      _setVec3(m['sunColor'], (v) => s.sunColor = v);
      if (m['sunSharpness'] != null) s.sunSharpness = _d(m['sunSharpness']);
      return s;
    case 'physical':
      final s = PhysicalSkySpec();
      _setVec3(m['sunDirection'], (v) => s.sunDirection = v);
      if (m['sunAngularRadius'] != null) {
        s.sunAngularRadius = _d(m['sunAngularRadius']);
      }
      if (m['rayleighCoefficient'] != null) {
        s.rayleighCoefficient = _d(m['rayleighCoefficient']);
      }
      _setVec3(m['rayleighColor'], (v) => s.rayleighColor = v);
      if (m['mieCoefficient'] != null) {
        s.mieCoefficient = _d(m['mieCoefficient']);
      }
      if (m['mieEccentricity'] != null) {
        s.mieEccentricity = _d(m['mieEccentricity']);
      }
      _setVec3(m['mieColor'], (v) => s.mieColor = v);
      if (m['turbidity'] != null) s.turbidity = _d(m['turbidity']);
      _setVec3(m['groundColor'], (v) => s.groundColor = v);
      if (m['energy'] != null) s.energy = _d(m['energy']);
      return s;
    default:
      return null;
  }
}

void _setVec3(Object? json, void Function(Vector3) assign) {
  if (json is! List || json.length < 3) return;
  assign(Vector3(_d(json[0]), _d(json[1]), _d(json[2])));
}

EnvironmentSpec _decodeEnvironment(Object? json) {
  if (json == null) return const StudioEnvironment();
  final m = json as Map;
  switch (m['type']) {
    case 'asset':
      return AssetEnvironment(AssetRef(m['ref'] as String));
    case 'empty':
      return const EmptyEnvironment();
    case 'studio':
    default:
      return const StudioEnvironment();
  }
}

double _d(Object? v) => (v as num).toDouble();
