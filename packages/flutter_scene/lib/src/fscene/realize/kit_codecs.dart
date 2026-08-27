/// Codecs for the gameplay components in `package:flutter_scene/kit.dart`.
///
/// These are ordinary [Component]s that were only ever assembled in code, so
/// the editor could not list, inspect, or save one. Runtime state that input
/// or gameplay owns (a route being walked, the tiles placed so far) is not
/// declared here: it is the product of play, not of authoring.
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:scene/grid.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/ref_read.dart';
import 'package:flutter_scene/src/kit/grid/grid_tiles.dart';
import 'package:flutter_scene/src/kit/interaction/path_follower_component.dart';

/// Registers the kit component codecs into [registry].
void registerKitComponentCodecs(FsceneComponentRegistry registry) {
  registry
    ..register(PathFollowerCodec())
    ..register(GridTileLayerCodec());
}

/// Codec for [PathFollowerComponent], which walks a node along a route from
/// either pathfinder.
///
/// The route itself is not a property: it arrives from a nav mesh query or a
/// grid search at runtime, and a half-walked path is not something anyone
/// authors. What is authored is how the mover behaves once it has one.
class PathFollowerCodec
    extends DeclarativeComponentCodec<PathFollowerComponent> {
  @override
  String get type => 'pathFollower';

  @override
  String? get category => 'Navigation';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'path',
    properties: propertySchema,
  );

  @override
  List<ComponentField<PathFollowerComponent>> get fields => [
    ComponentField.number(
      'speed',
      defaultValue: 4.0,
      doc: 'Travel rate, in world units per second.',
      constraints: const [Range.nonNegative(), SoftRange(0, 20)],
      get: (c) => c.speed,
      set: (c, v) => c.speed = v,
    ),
    ComponentField.number(
      'turnSpeed',
      defaultValue: 10.0,
      doc:
          'How fast the node turns to face its travel direction, in radians '
          'per second.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.turnSpeed,
      set: (c, v) => c.turnSpeed = v,
    ),
    ComponentField.number(
      'arriveRadius',
      defaultValue: 0.15,
      doc: 'How close counts as reaching a waypoint, in world units.',
      constraints: const [Range(0.0001, null), SoftRange(0.01, 2)],
      get: (c) => c.arriveRadius,
      set: (c, v) => c.arriveRadius = v,
    ),
    ComponentField.number(
      'slowRadius',
      defaultValue: 0.0,
      doc:
          'Distance from the final waypoint at which the mover eases off. '
          'Zero stops dead on arrival.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.slowRadius,
      set: (c, v) => c.slowRadius = v,
    ),
    ComponentField.boolean(
      'facesTravel',
      defaultValue: true,
      doc: 'Whether the node turns to face where it is going.',
      get: (c) => c.facesTravel,
      set: (c, v) => c.facesTravel = v,
    ),
  ];

  @override
  PathFollowerComponent create(PropertyReader props) => PathFollowerComponent(
    speed: props.number('speed'),
    turnSpeed: props.number('turnSpeed'),
    arriveRadius: props.number('arriveRadius'),
    slowRadius: props.number('slowRadius'),
    facesTravel: props.boolean('facesTravel'),
  );
}

// --- Grid tiles ---

const _gridFields = [
  ComponentPropertyDef(
    'shape',
    ComponentPropertyKind.string,
    defaultValue: StringValue('square'),
    options: ['square', 'hex'],
    doc: 'The tiling this layer places cells on.',
  ),
  ComponentPropertyDef(
    'cellSize',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1),
    doc: 'Edge length of a square cell, or the circumradius of a hexagon.',
  ),
  ComponentPropertyDef(
    'origin',
    ComponentPropertyKind.vec2,
    doc: 'World XZ position that cell (0, 0) is centred on.',
  ),
  ComponentPropertyDef(
    'elevation',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Height of the grid plane, in world units.',
  ),
  ComponentPropertyDef(
    'allowDiagonals',
    ComponentPropertyKind.boolean,
    defaultValue: BoolValue(false),
    doc: 'Square grids only: whether the four diagonals count as neighbours.',
  ),
  ComponentPropertyDef(
    'orientation',
    ComponentPropertyKind.string,
    defaultValue: StringValue('pointyTop'),
    options: ['pointyTop', 'flatTop'],
    doc: 'Hex grids only: which way the hexagons point.',
  ),
];

const _tileFields = [
  ComponentPropertyDef(
    'cell',
    ComponentPropertyKind.vec2,
    doc: 'The cell, as column/row or axial q/r.',
  ),
  ComponentPropertyDef(
    'height',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Lift above the grid plane.',
  ),
  ComponentPropertyDef(
    'yaw',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Rotation about the tile\'s own vertical axis, in radians.',
  ),
  ComponentPropertyDef(
    'scale',
    ComponentPropertyKind.vec3,
    doc: 'Per-tile scale, absent for none.',
  ),
  ComponentPropertyDef(
    'color',
    ComponentPropertyKind.color,
    doc: "Per-tile tint, absent for the material's own colour.",
  ),
];

double _num(Object? value, double fallback) => switch (value) {
  DoubleValue(value: final v) => v,
  IntValue(value: final v) => v.toDouble(),
  _ => fallback,
};

Grid _decodeGrid(PropertyValue? value) {
  final map = value is MapValue
      ? value.values
      : const <String, PropertyValue>{};
  final cellSize = _num(map['cellSize'], 1.0);
  final origin = switch (map['origin']) {
    Vec2Value(value: final v) => (x: v.x, z: v.y),
    _ => (x: 0.0, z: 0.0),
  };
  final elevation = _num(map['elevation'], 0.0);
  final hex = switch (map['shape']) {
    StringValue(value: 'hex') => true,
    _ => false,
  };
  if (!hex) {
    return SquareGrid(
      cellSize: cellSize <= 0 ? 1.0 : cellSize,
      allowDiagonals: switch (map['allowDiagonals']) {
        BoolValue(value: final v) => v,
        _ => false,
      },
      origin: origin,
      elevation: elevation,
    );
  }
  return HexGrid(
    cellSize: cellSize <= 0 ? 1.0 : cellSize,
    orientation: switch (map['orientation']) {
      StringValue(value: 'flatTop') => HexOrientation.flatTop,
      _ => HexOrientation.pointyTop,
    },
    origin: origin,
    elevation: elevation,
  );
}

MapValue _encodeGrid(Grid grid) => MapValue({
  'shape': StringValue(grid is HexGrid ? 'hex' : 'square'),
  'cellSize': DoubleValue(grid.cellSize),
  'origin': Vec2Value(Vector2(grid.origin.x, grid.origin.z)),
  'elevation': DoubleValue(grid.elevation),
  if (grid is SquareGrid && grid.allowDiagonals)
    'allowDiagonals': const BoolValue(true),
  if (grid is HexGrid && grid.orientation == HexOrientation.flatTop)
    'orientation': const StringValue('flatTop'),
});

/// Codec for [GridTileLayer]: the tiling, the instanced tile it draws, and
/// every placed tile.
///
/// Hand-written rather than declarative because the geometry and material are
/// resource references, so realizing one can fail: without a resource
/// realizer there is nothing to draw and the component is skipped, the way a
/// mesh component is.
class GridTileLayerCodec extends ComponentCodec {
  @override
  String get type => 'gridTileLayer';

  @override
  String? get category => 'Mesh';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'grid',
    properties: propertySchema,
  );

  @override
  List<ComponentPropertyDef> get propertySchema => const [
    ComponentPropertyDef(
      'geometry',
      ComponentPropertyKind.resourceRef,
      doc: 'The geometry drawn once per tile.',
      resourceKind: 'geometry',
    ),
    ComponentPropertyDef(
      'material',
      ComponentPropertyKind.resourceRef,
      doc: 'The material the tiles are drawn with.',
      resourceKind: 'material',
    ),
    ComponentPropertyDef(
      'cullTiles',
      ComponentPropertyKind.boolean,
      defaultValue: BoolValue(true),
      doc:
          'Test each tile against the view separately. Leave off for a small '
          'map, where one test against the whole batch is cheaper.',
    ),
    ComponentPropertyDef(
      'grid',
      ComponentPropertyKind.object,
      objectFields: _gridFields,
      doc: 'The tiling cells are placed on.',
    ),
    ComponentPropertyDef(
      'tiles',
      ComponentPropertyKind.list,
      itemDef: ComponentPropertyDef(
        'tile',
        ComponentPropertyKind.object,
        objectFields: _tileFields,
      ),
      doc: 'Every placed tile, with the appearance it was placed with.',
    ),
  ];

  @override
  Type get componentType => GridTileLayer;

  @override
  bool claims(Component component) => component is GridTileLayer;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final realizer = context.resources;
    if (realizer == null) {
      debugPrint('fscene: gridTileLayer skipped (no resource realizer)');
      return null;
    }
    final geometryRef = spec.properties['geometry'];
    final materialRef = spec.properties['material'];
    if (geometryRef is! ResourceRefValue || materialRef is! ResourceRefValue) {
      debugPrint(
        'fscene: gridTileLayer skipped (it needs both a geometry and a '
        'material reference)',
      );
      return null;
    }

    final layer = GridTileLayer(
      grid: _decodeGrid(spec.properties['grid']),
      geometry: realizer.geometry(geometryRef.id),
      material: realizer.material(materialRef.id),
      cullTiles: switch (spec.properties['cullTiles']) {
        BoolValue(value: final v) => v,
        _ => true,
      },
    );

    final tiles = spec.properties['tiles'];
    if (tiles is ListValue) {
      for (final entry in tiles.values) {
        if (entry is! MapValue) continue;
        final cell = entry.values['cell'];
        if (cell is! Vec2Value) continue;
        layer.set(
          GridCoord(cell.value.x.round(), cell.value.y.round()),
          height: _num(entry.values['height'], 0.0),
          yaw: _num(entry.values['yaw'], 0.0),
          scale: switch (entry.values['scale']) {
            Vec3Value(value: final v) => v.clone(),
            _ => null,
          },
          color: switch (entry.values['color']) {
            ColorValue(:final r, :final g, :final b, :final a) => Vector4(
              r,
              g,
              b,
              a,
            ),
            _ => null,
          },
        );
      }
    }
    return layer;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! GridTileLayer) return null;
    final geometry = resourceRefOf(component.mesh.geometry, context);
    final material = resourceRefOf(component.mesh.material, context);
    if (geometry == null || material == null) {
      debugPrint(
        'fscene: gridTileLayer not saved (its geometry or material was built '
        'in code and has no source resource to reference)',
      );
      return null;
    }
    return ComponentSpec(
      type,
      properties: {
        'geometry': geometry,
        'material': material,
        if (!component.mesh.cullInstances) 'cullTiles': const BoolValue(false),
        'grid': _encodeGrid(component.grid),
        if (!component.isEmpty)
          'tiles': ListValue([
            for (final tile in component.tiles)
              MapValue({
                'cell': Vec2Value(
                  Vector2(tile.cell.x.toDouble(), tile.cell.y.toDouble()),
                ),
                if (tile.look.height != 0)
                  'height': DoubleValue(tile.look.height),
                if (tile.look.yaw != 0) 'yaw': DoubleValue(tile.look.yaw),
                if (tile.look.scale case final scale?)
                  'scale': Vec3Value(scale.clone()),
                if (tile.look.color case final color?)
                  'color': ColorValue(color.x, color.y, color.z, color.w),
              }),
          ]),
      },
    );
  }
}
