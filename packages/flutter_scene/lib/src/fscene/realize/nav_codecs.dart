/// The codec for [NavMeshSurfaceComponent]: bake settings, and the bake.
///
/// The settings alone would not be enough. A nav mesh takes seconds to build
/// on a real level and the numbers that produced it are not the mesh: a
/// scene that stored only its settings would have to rebake on every load,
/// on the device, before anything could path. So the baked mesh travels with
/// the document as a payload, and the settings travel beside it as the record
/// of what to rebake from.
library;

import 'dart:typed_data';

import 'package:scene/navigation.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/navigation/nav_mesh_surface_component.dart';

/// Registers the navigation component codecs into [registry].
void registerNavComponentCodecs(FsceneComponentRegistry registry) {
  registry.register(NavMeshSurfaceCodec());
}

/// Which payload of which document a component's bake currently occupies.
///
/// A baked world is megabytes. Minting a fresh payload on every serialize
/// would grow the document by a whole mesh per save and leave the previous
/// one behind unreferenced, since nothing collects orphaned payloads. So each
/// component remembers its payload and a re-save overwrites it in place.
///
/// Stamped on the component rather than on the mesh, because a rebake
/// replaces the mesh and the payload it should overwrite is the same one.
/// Held in an [Expando], the same way realized resources carry their origin,
/// so a runtime component gains no document-shaped field it would otherwise
/// have no use for.
class _BakeOrigin {
  _BakeOrigin(this.document, this.payloadId);

  final SceneDocument document;
  final LocalId payloadId;
}

final Expando<_BakeOrigin> _bakeOrigins = Expando<_BakeOrigin>(
  'fscene.navBakeOrigin',
);

/// Writes [bytes] into [document] as an opaque payload and returns the token
/// that names it, reusing the payload this component already occupies there.
StringValue _writeBakePayload(
  NavMeshSurfaceComponent component,
  SceneDocument document,
  Uint8List bytes,
) {
  final origin = _bakeOrigins[component];
  if (origin != null && identical(origin.document, document)) {
    final existing = document.payload(origin.payloadId);
    if (existing != null) {
      existing.bytes = bytes;
      return StringValue(origin.payloadId.toToken());
    }
  }
  final payload = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.bytes,
      format: 'navMesh',
      length: bytes.length,
      bytes: bytes,
    ),
  );
  _bakeOrigins[component] = _BakeOrigin(document, payload.id);
  return StringValue(payload.id.toToken());
}

/// The bytes named by [token], recording where they came from so a later
/// save overwrites that payload rather than adding another.
Uint8List? _readBakePayload(
  NavMeshSurfaceComponent component,
  SceneDocument document,
  PropertyValue? token,
) {
  if (token is! StringValue || token.value.isEmpty) return null;
  final LocalId id;
  try {
    id = LocalId.parse(token.value);
  } on FormatException {
    return null;
  }
  final bytes = document.payload(id)?.bytes;
  if (bytes != null) _bakeOrigins[component] = _BakeOrigin(document, id);
  return bytes;
}

/// Codec for [NavMeshSurfaceComponent].
///
/// The bake rides in one payload whichever shape it took: a single mesh and a
/// tile set are told apart by their own magic when it is read back, so the
/// document does not carry a second flag that could disagree with the bytes.
class NavMeshSurfaceCodec
    extends DeclarativeComponentCodec<NavMeshSurfaceComponent> {
  @override
  String get type => 'navMeshSurface';

  @override
  String? get category => 'Navigation';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'navigation',
    properties: propertySchema,
  );

  @override
  List<ComponentField<NavMeshSurfaceComponent>> get fields => [
    // --- The agent the mesh is baked for ---
    ComponentField.number(
      'agentRadius',
      defaultValue: 0.6,
      group: 'Agent',
      doc: 'How close the agent\'s centre may get to a wall.',
      constraints: const [Range.nonNegative(), SoftRange(0.05, 3)],
      get: (c) => c.config.agentRadius,
      set: (c, v) => c.config = c.config.copyWith(agentRadius: v),
    ),
    ComponentField.number(
      'agentHeight',
      defaultValue: 2.0,
      group: 'Agent',
      doc: 'Clearance needed, so it never paths under a low beam.',
      constraints: const [Range(0.01, null), SoftRange(0.3, 5)],
      get: (c) => c.config.agentHeight,
      set: (c, v) => c.config = c.config.copyWith(agentHeight: v),
    ),
    ComponentField.number(
      'agentMaxClimb',
      defaultValue: 0.9,
      group: 'Agent',
      doc: 'The tallest step it walks up without jumping.',
      constraints: const [Range.nonNegative(), SoftRange(0, 2)],
      get: (c) => c.config.agentMaxClimb,
      set: (c, v) => c.config = c.config.copyWith(agentMaxClimb: v),
    ),
    ComponentField.number(
      'agentMaxSlopeDegrees',
      defaultValue: 45.0,
      group: 'Agent',
      doc: 'Steeper than this is a wall, not a ramp.',
      constraints: const [Range(1, 89), SoftRange(1, 89)],
      get: (c) => c.config.agentMaxSlopeDegrees,
      set: (c, v) => c.config = c.config.copyWith(agentMaxSlopeDegrees: v),
    ),

    // --- Voxel resolution ---
    ComponentField.number(
      'cellSize',
      defaultValue: 0.3,
      group: 'Resolution',
      doc:
          'The smallest gap the bake can resolve. Halving it quadruples the '
          'work.',
      constraints: const [Range(0.01, null), SoftRange(0.02, 1)],
      get: (c) => c.config.cellSize,
      set: (c, v) => c.config = c.config.copyWith(cellSize: v),
    ),
    ComponentField.number(
      'cellHeight',
      defaultValue: 0.2,
      group: 'Resolution',
      doc: 'How precisely a step or a ledge is placed.',
      constraints: const [Range(0.01, null), SoftRange(0.02, 1)],
      get: (c) => c.config.cellHeight,
      set: (c, v) => c.config = c.config.copyWith(cellHeight: v),
    ),

    // --- Region and contour tuning ---
    ComponentField.number(
      'minRegionArea',
      defaultValue: 8.0,
      group: 'Regions',
      doc: 'Smaller patches are discarded as unreachable specks.',
      constraints: const [Range.nonNegative(), SoftRange(0, 100)],
      get: (c) => c.config.minRegionArea,
      set: (c, v) => c.config = c.config.copyWith(minRegionArea: v),
    ),
    ComponentField.number(
      'mergeRegionArea',
      defaultValue: 20.0,
      group: 'Regions',
      doc: 'Regions under this are merged into a neighbour.',
      constraints: const [Range.nonNegative(), SoftRange(0, 200)],
      get: (c) => c.config.mergeRegionArea,
      set: (c, v) => c.config = c.config.copyWith(mergeRegionArea: v),
    ),
    ComponentField.number(
      'maxEdgeLength',
      defaultValue: 12.0,
      group: 'Regions',
      doc: 'Long contour edges are split at this.',
      constraints: const [Range.nonNegative(), SoftRange(0, 60)],
      get: (c) => c.config.maxEdgeLength,
      set: (c, v) => c.config = c.config.copyWith(maxEdgeLength: v),
    ),
    ComponentField.number(
      'maxSimplificationError',
      defaultValue: 1.3,
      group: 'Regions',
      doc:
          'How far a simplified contour may stray from the voxel outline, in '
          'voxels.',
      constraints: const [Range.nonNegative(), SoftRange(0.1, 6)],
      get: (c) => c.config.maxSimplificationError,
      set: (c, v) => c.config = c.config.copyWith(maxSimplificationError: v),
    ),
    ComponentField.integer(
      'maxVertsPerPolygon',
      defaultValue: 6,
      group: 'Regions',
      doc: 'The most vertices one nav polygon may have.',
      constraints: const [IntRange(3, 12)],
      get: (c) => c.config.maxVertsPerPolygon,
      set: (c, v) => c.config = c.config.copyWith(maxVertsPerPolygon: v),
    ),

    // --- What the bake collects ---
    ComponentField.string(
      'includePattern',
      defaultValue: '',
      group: 'Collect',
      doc:
          'Only nodes whose name contains this contribute. Empty takes '
          'everything, which also takes the characters.',
      get: (c) => c.includePattern,
      set: (c, v) => c.includePattern = v,
    ),
    ComponentField.boolean(
      'includeInstances',
      defaultValue: true,
      group: 'Collect',
      doc: 'Whether instanced meshes contribute one copy per instance.',
      get: (c) => c.includeInstances,
      set: (c, v) => c.includeInstances = v,
    ),
    ComponentField.boolean(
      'includeWaterVolumes',
      defaultValue: true,
      group: 'Collect',
      doc: 'Whether blocked water carves the ground under it.',
      get: (c) => c.includeWaterVolumes,
      set: (c, v) => c.includeWaterVolumes = v,
    ),
    ComponentField.number(
      'blockedWaterDepth',
      defaultValue: 50.0,
      group: 'Collect',
      doc:
          'How far below a blocked water surface its carve reaches. It has to '
          'clear the bed underneath or an agent paths along the bottom.',
      constraints: const [Range.nonNegative(), SoftRange(1, 200)],
      get: (c) => c.blockedWaterDepth,
      set: (c, v) => c.blockedWaterDepth = v,
    ),

    // --- Tiling ---
    ComponentField.integer(
      'tileCells',
      defaultValue: 0,
      group: 'Tiling',
      doc:
          'Voxels per tile side, or 0 to bake the world in one piece. Tiling '
          'bounds memory, bakes tiles in parallel, and makes an edit a rebake '
          'of one tile; below a few hundred units a side it is not worth it.',
      constraints: const [IntRange(0, 512)],
      get: (c) => c.tiling?.tileCells ?? 0,
      set: (c, v) => c.tiling = v < 8
          ? null
          : NavTileConfig(tileCells: v, borderCells: c.tiling?.borderCells),
    ),
    ComponentField.integer(
      'tileBorderCells',
      defaultValue: 0,
      group: 'Tiling',
      doc:
          'Voxels of margin each tile bakes and throws away, or 0 to derive it '
          'from the agent. Too small and tiles disagree at their seams.',
      constraints: const [IntRange(0, 64)],
      get: (c) => c.tiling?.borderCells ?? 0,
      set: (c, v) {
        final tiling = c.tiling;
        if (tiling == null) return;
        c.tiling = NavTileConfig(
          tileCells: tiling.tileCells,
          borderCells: v <= 0 ? null : v,
        );
      },
    ),

    // --- The bake itself ---
    ComponentField(
      ComponentPropertyDef(
        'baked',
        ComponentPropertyKind.string,
        defaultValue: const StringValue(''),
        group: 'Baked',
        doc:
            'The baked mesh, as a payload token. Written by a bake and read '
            'at load, so a shipped scene paths without rebaking on the device.',
        constraints: const [ReadOnly()],
      ),
      read: (c, context) {
        final tiles = c.tileSet;
        if (tiles != null && tiles.tileCount > 0) {
          return _writeBakePayload(
            c,
            context.document,
            encodeNavTileSet(tiles),
          );
        }
        final mesh = c.mesh;
        if (mesh == null) return const StringValue('');
        return _writeBakePayload(c, context.document, encodeNavMesh(mesh));
      },
      write: (c, value, context) {
        final bytes = _readBakePayload(c, context.document, value);
        if (bytes == null || bytes.length < 8) return;
        // The two forms are told apart by their own magic rather than by a
        // flag beside them, so a payload can never claim to be something the
        // bytes are not.
        final magic = ByteData.view(
          bytes.buffer,
          bytes.offsetInBytes,
          4,
        ).getUint32(0, Endian.little);
        try {
          if (magic == navTileSetMagic) {
            c.tileSet = decodeNavTileSet(bytes);
          } else {
            c.mesh = decodeNavMesh(bytes);
          }
        } on FormatException {
          // A bake from an older build. The settings survived, so the scene
          // opens and can be rebaked; refusing to realize the node over it
          // would lose the level instead.
          c.mesh = null;
          c.tileSet = null;
        }
      },
    ),
  ];

  @override
  NavMeshSurfaceComponent create(PropertyReader props) {
    final tileCells = props.integer('tileCells');
    final border = props.integer('tileBorderCells');
    return NavMeshSurfaceComponent(
      config: NavMeshConfig(
        cellSize: props.number('cellSize'),
        cellHeight: props.number('cellHeight'),
        agentRadius: props.number('agentRadius'),
        agentHeight: props.number('agentHeight'),
        agentMaxClimb: props.number('agentMaxClimb'),
        agentMaxSlopeDegrees: props.number('agentMaxSlopeDegrees'),
        minRegionArea: props.number('minRegionArea'),
        mergeRegionArea: props.number('mergeRegionArea'),
        maxEdgeLength: props.number('maxEdgeLength'),
        maxSimplificationError: props.number('maxSimplificationError'),
        maxVertsPerPolygon: props.integer('maxVertsPerPolygon'),
      ),
      includePattern: props.string('includePattern'),
      includeInstances: props.boolean('includeInstances'),
      includeWaterVolumes: props.boolean('includeWaterVolumes'),
      blockedWaterDepth: props.number('blockedWaterDepth'),
      tiling: tileCells < 8
          ? null
          : NavTileConfig(
              tileCells: tileCells,
              borderCells: border <= 0 ? null : border,
            ),
    );
  }
}
