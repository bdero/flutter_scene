/// The queries every session answers.
///
/// Enough to write an out-of-tree tool against: read a subtree in one call,
/// find the nodes to act on, read a resource and the bytes behind it, and
/// learn the command and query surface at runtime.
library;

import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'command.dart';
import 'queries.dart';

/// Registers every built-in query on [registry].
void registerBuiltinQueries(QueryRegistry registry) {
  for (final entry in builtinQueries) {
    registry.register(entry);
  }
}

/// The built-in query set.
final List<QueryEntry> builtinQueries = [
  documentSummary,
  nodeSubtree,
  findNodes,
  listResources,
  getResource,
  readPayload,
  getSelection,
  listCommands,
  listQueries,
];

/// What the document holds, without reading any of it.
final documentSummary = QueryEntry(
  name: 'documentSummary',
  doc: 'Counts, roots, and undo state for the open document.',
  category: 'Document',
  read: (ctx, params) => QueryResult({
    'nodeCount': ctx.document.nodes.length,
    'resourceCount': ctx.document.resources.length,
    'payloadCount': ctx.document.payloads.length,
    'skinCount': ctx.document.skins.length,
    'animationCount': ctx.document.animations.length,
    'roots': [for (final id in ctx.document.roots) id.toToken()],
    'payloadBytes': ctx.document.payloads.values.fold<int>(
      0,
      (sum, payload) => sum + (payload.bytes?.lengthInBytes ?? 0),
    ),
    'history': {
      'canUndo': ctx.history.canUndo,
      'canRedo': ctx.history.canRedo,
      'undoLabel': ctx.history.undoLabel,
      'redoLabel': ctx.history.redoLabel,
      'depth': ctx.history.transactions.length,
    },
  }),
);

/// A whole subtree in one call, which is the point of having queries at all.
final nodeSubtree = QueryEntry(
  name: 'nodeSubtree',
  doc:
      'Read a node subtree in one call. Omit nodeId for the scene roots. '
      'depth 0 is the node itself, -1 (the default) is everything under it.',
  category: 'Scene',
  paramSchema: const [
    ParamSpec(
      name: 'nodeId',
      type: ParamType.nodeRef,
      label: 'Node',
      description: 'The subtree root; omit for the scene roots',
      required: false,
    ),
    ParamSpec(
      name: 'depth',
      type: ParamType.integer,
      label: 'Depth',
      description: 'How many levels below the root to include',
      required: false,
      defaultValue: -1,
    ),
    ParamSpec(
      name: 'components',
      type: ParamType.boolean,
      label: 'Components',
      description: 'Include each node\'s component properties',
      required: false,
      defaultValue: false,
    ),
  ],
  read: (ctx, params) {
    final depth = _optionalInt(params, 'depth') ?? -1;
    final withComponents = _optionalBool(params, 'components') ?? false;
    final rootToken = params['nodeId'];
    final roots = <NodeSpec>[];
    if (rootToken == null) {
      roots.addAll(ctx.query.roots);
    } else {
      roots.add(_requireNode(ctx, rootToken));
    }
    return QueryResult({
      'nodes': [
        for (final root in roots)
          _nodeJson(ctx, root, depth, withComponents: withComponents),
      ],
    });
  },
);

/// The nodes a tool wants to act on, without walking the tree client side.
final findNodes = QueryEntry(
  name: 'findNodes',
  doc:
      'Find nodes by name substring, exact name, or component type. '
      'Returns ids and paths, not whole nodes.',
  category: 'Scene',
  paramSchema: const [
    ParamSpec(
      name: 'name',
      type: ParamType.string,
      label: 'Name contains',
      required: false,
    ),
    ParamSpec(
      name: 'exactName',
      type: ParamType.string,
      label: 'Name equals',
      required: false,
    ),
    ParamSpec(
      name: 'componentType',
      type: ParamType.string,
      label: 'Has component',
      required: false,
    ),
    ParamSpec(
      name: 'limit',
      type: ParamType.integer,
      label: 'Limit',
      required: false,
      defaultValue: 500,
    ),
  ],
  read: (ctx, params) {
    final contains = _optionalString(params, 'name')?.toLowerCase();
    final exact = _optionalString(params, 'exactName');
    final componentType = _optionalString(params, 'componentType');
    final limit = _optionalInt(params, 'limit') ?? 500;
    if (limit <= 0) throw const QueryException('limit must be positive');
    final matches = <Map<String, Object?>>[];
    var total = 0;
    for (final node in ctx.document.nodes.values) {
      if (exact != null && node.name != exact) continue;
      if (contains != null && !node.name.toLowerCase().contains(contains)) {
        continue;
      }
      if (componentType != null &&
          !node.components.any((c) => c.type == componentType)) {
        continue;
      }
      total++;
      if (matches.length >= limit) continue;
      matches.add({
        'id': node.id.toToken(),
        'name': node.name,
        'path': ctx.query.namePathOf(node.id),
      });
    }
    return QueryResult({
      'nodes': matches,
      'total': total,
      'truncated': total > matches.length,
    });
  },
);

/// The resource pool, optionally narrowed to one kind.
final listResources = QueryEntry(
  name: 'listResources',
  doc:
      'List resources, optionally of one kind (geometry, texture, '
      'material, renderTexture, environment).',
  category: 'Resources',
  paramSchema: const [
    ParamSpec(
      name: 'kind',
      type: ParamType.string,
      label: 'Kind',
      required: false,
    ),
  ],
  read: (ctx, params) {
    final kind = _optionalString(params, 'kind');
    final out = <Map<String, Object?>>[];
    for (final resource in ctx.document.resources.values) {
      final resourceKind = resourceKindOf(resource);
      if (kind != null && resourceKind != kind) continue;
      out.add({'id': resource.id.toToken(), 'kind': resourceKind});
    }
    return QueryResult({'resources': out});
  },
);

/// One resource in full, including the payload ids behind it.
final getResource = QueryEntry(
  name: 'getResource',
  doc: 'Read one resource, including the payload ids it references.',
  category: 'Resources',
  paramSchema: const [
    ParamSpec(
      name: 'resourceId',
      type: ParamType.resourceRef,
      label: 'Resource',
    ),
  ],
  read: (ctx, params) {
    final resource = _requireResource(ctx, params['resourceId']);
    return QueryResult(_resourceJson(resource));
  },
);

/// The bytes behind a geometry (or any other payload), which is what an
/// out-of-tree mesh operation needs and no amount of JSON can stand in for.
final readPayload = QueryEntry(
  name: 'readPayload',
  doc:
      'Read a payload chunk\'s bytes. Use offset and length to read part of '
      'a large chunk.',
  category: 'Resources',
  paramSchema: const [
    ParamSpec(name: 'payloadId', type: ParamType.resourceRef, label: 'Payload'),
    ParamSpec(
      name: 'offset',
      type: ParamType.integer,
      label: 'Offset',
      required: false,
      defaultValue: 0,
    ),
    ParamSpec(
      name: 'length',
      type: ParamType.integer,
      label: 'Length',
      description: 'Bytes to read; omit for the rest of the chunk',
      required: false,
    ),
  ],
  read: (ctx, params) {
    final token = params['payloadId'];
    if (token is! String || token.isEmpty) {
      throw const QueryException('readPayload needs a "payloadId"');
    }
    final id = _parseId(token);
    final payload = ctx.document.payloads[id];
    if (payload == null) {
      throw QueryException('No payload "$token" in this document');
    }
    final bytes = payload.bytes;
    if (bytes == null) {
      throw QueryException(
        'Payload "$token" has no bytes loaded; its descriptor says '
        '${payload.length ?? 0} bytes live in the sidecar',
      );
    }
    final offset = _optionalInt(params, 'offset') ?? 0;
    if (offset < 0 || offset > bytes.lengthInBytes) {
      throw QueryException(
        'offset $offset is outside the chunk (${bytes.lengthInBytes} bytes)',
      );
    }
    final remaining = bytes.lengthInBytes - offset;
    final length = _optionalInt(params, 'length') ?? remaining;
    if (length < 0) throw const QueryException('length cannot be negative');
    final taken = length < remaining ? length : remaining;
    return QueryResult(
      {
        'payloadId': token,
        'encoding': payload.encoding.name,
        if (payload.layout != null) 'layout': payload.layout,
        if (payload.format != null) 'format': payload.format,
        'totalBytes': bytes.lengthInBytes,
        'offset': offset,
        'byteCount': taken,
        'blob': 'payload',
      },
      blobs: [
        QueryBlob(
          id: 'payload',
          bytes: Uint8List.sublistView(bytes, offset, offset + taken),
        ),
      ],
    );
  },
);

/// What is selected, in the order the selection holds it.
final getSelection = QueryEntry(
  name: 'getSelection',
  doc: 'The selected node ids and paths, primary last.',
  category: 'Scene',
  read: (ctx, params) => QueryResult({
    'nodeIds': [for (final id in ctx.selection.ids) id.toToken()],
    'paths': [for (final id in ctx.selection.ids) ctx.query.namePathOf(id)],
    'primary': ctx.selection.primary?.toToken(),
  }),
);

/// The command surface, so a client discovers it at runtime instead of
/// being compiled against a snapshot of it.
final listCommands = QueryEntry(
  name: 'listCommands',
  doc: 'Every command with its kind and parameter schema.',
  category: 'Schema',
  paramSchema: const [
    ParamSpec(
      name: 'category',
      type: ParamType.string,
      label: 'Category',
      required: false,
    ),
  ],
  read: (ctx, params) {
    final category = _optionalString(params, 'category');
    return QueryResult({
      'commands': [
        for (final entry in ctx.commands.all)
          if (category == null || entry.category == category)
            {
              ...mcpToolSchema(entry),
              'kind': entry.kind.name,
              if (entry.category.isNotEmpty) 'category': entry.category,
            },
      ],
    });
  },
);

/// The query surface, the same way.
final listQueries = QueryEntry(
  name: 'listQueries',
  doc: 'Every query with its parameter schema.',
  category: 'Schema',
  read: (ctx, params) => QueryResult({
    'queries': [for (final entry in ctx.queries.all) querySchema(entry)],
  }),
);

Map<String, Object?> _nodeJson(
  QueryContext ctx,
  NodeSpec node,
  int depth, {
  required bool withComponents,
}) => {
  'id': node.id.toToken(),
  'name': node.name,
  'path': ctx.query.namePathOf(node.id),
  // Stated even at their defaults, since a client should not have to know
  // what the format omits.
  'visible': node.visible,
  'layers': node.layers,
  'shadowCastingMode': node.shadowCastingMode,
  'transform': _transformJson(node.transform),
  if (node.skin != null) 'skin': node.skin!.toToken(),
  // The instance delta is deep (overrides, attachments, removals, member
  // components), so the format's own encoder writes it rather than a second
  // one here that would forget a field at a time.
  if (node.instance != null)
    'instance': encodeNode(node, (id) => id.toToken())['instance'],
  if (node.unknown.isNotEmpty) 'unknown': node.unknown,
  'components': [
    for (final component in node.components)
      if (withComponents)
        {
          'type': component.type,
          'properties': {
            for (final entry in component.properties.entries)
              entry.key: propertyValueToJson(entry.value),
          },
        }
      else
        {'type': component.type},
  ],
  'childCount': node.children.length,
  if (depth != 0)
    'children': [
      for (final child in ctx.query.childrenOf(node.id))
        _nodeJson(ctx, child, depth - 1, withComponents: withComponents),
    ],
};

Map<String, Object?> _transformJson(TransformSpec transform) =>
    switch (transform) {
      TrsTransform trs => {
        'kind': 'trs',
        'translation': _vec3Json(trs.translation),
        'rotation': {
          'x': trs.rotation.x,
          'y': trs.rotation.y,
          'z': trs.rotation.z,
          'w': trs.rotation.w,
        },
        'scale': _vec3Json(trs.scale),
      },
      MatrixTransform matrix => {
        'kind': 'matrix',
        'matrix': matrix.matrix.storage.toList(),
      },
    };

Map<String, Object?> _vec3Json(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};

/// The JSON form of a property value, the one encoder every read shares so a
/// tool and a query cannot describe the same value differently.
Object? propertyValueToJson(PropertyValue value) => switch (value) {
  // A kind this build does not know, shown as it was stored.
  UnknownValue v => v.json,
  BoolValue v => v.value,
  IntValue v => v.value,
  DoubleValue v => v.value,
  StringValue v => v.value,
  Vec2Value v => {'x': v.value.x, 'y': v.value.y},
  Vec3Value v => _vec3Json(v.value),
  Vec4Value v => {
    'x': v.value.x,
    'y': v.value.y,
    'z': v.value.z,
    'w': v.value.w,
  },
  QuaternionValue v => {
    r'$quat': {'x': v.value.x, 'y': v.value.y, 'z': v.value.z, 'w': v.value.w},
  },
  Matrix4Value v => v.value.storage.toList(),
  ColorValue v => {'r': v.r, 'g': v.g, 'b': v.b, 'a': v.a},
  ResourceRefValue v => {r'$resource': v.id.toToken()},
  NodeRefValue v => {r'$node': v.id.toToken()},
  ListValue v => [for (final e in v.values) propertyValueToJson(e)],
  MapValue v => {
    for (final entry in v.values.entries)
      entry.key: propertyValueToJson(entry.value),
  },
};

/// The wire name for a resource's kind, shared for the same reason.
String resourceKindOf(ResourceSpec resource) => switch (resource) {
  GeometryResource() => 'geometry',
  TextureResource() => 'texture',
  MaterialResource() => 'material',
  RenderTextureResource() => 'renderTexture',
  EnvironmentResource() => 'environment',
};

/// One resource in the document's own encoding, plus the kind name so a
/// client can switch without inspecting the shape.
///
/// The format's encoder does the work rather than a second one written here,
/// so every authored field arrives, including the procedural descriptors,
/// bounds, winding, texture content, render-target policy, morph metadata,
/// and the whole environment block that a hand-written encoder would forget
/// one at a time.
Map<String, Object?> _resourceJson(ResourceSpec resource) {
  final encoded = encodeResource(resource, (id) => id.toToken());
  return {
    'id': resource.id.toToken(),
    'kind': resourceKindOf(resource),
    if (encoded is Map<String, Object?>)
      ...encoded
    else
      // A kind the format encodes as something other than an object; handed
      // over as it stands rather than guessed at.
      'encoded': encoded,
  };
}

NodeSpec _requireNode(QueryContext ctx, Object? token) {
  if (token is! String || token.isEmpty) {
    throw const QueryException('Expected a node id token');
  }
  final node = ctx.document.node(_parseId(token));
  if (node == null) throw QueryException('No node "$token" in this document');
  return node;
}

ResourceSpec _requireResource(QueryContext ctx, Object? token) {
  if (token is! String || token.isEmpty) {
    throw const QueryException('Expected a resource id token');
  }
  final resource = ctx.document.resources[_parseId(token)];
  if (resource == null) {
    throw QueryException('No resource "$token" in this document');
  }
  return resource;
}

LocalId _parseId(String token) {
  try {
    return LocalId.parse(token);
  } on FormatException {
    throw QueryException('"$token" is not an id token');
  }
}

String? _optionalString(Map<String, Object?> params, String name) {
  final value = params[name];
  if (value == null) return null;
  if (value is! String) throw QueryException('"$name" must be a string');
  return value.isEmpty ? null : value;
}

int? _optionalInt(Map<String, Object?> params, String name) {
  final value = params[name];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw QueryException('"$name" must be an integer');
}

bool? _optionalBool(Map<String, Object?> params, String name) {
  final value = params[name];
  if (value == null) return null;
  if (value is! bool) throw QueryException('"$name" must be a boolean');
  return value;
}
