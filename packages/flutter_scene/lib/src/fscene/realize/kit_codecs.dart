/// Codecs for the gameplay components in `package:flutter_scene/kit.dart`.
///
/// These are ordinary [Component]s that were only ever assembled in code, so
/// the editor could not list, inspect, or save one. Runtime state that input
/// or gameplay owns (a route being walked, the tiles placed so far) is not
/// declared here: it is the product of play, not of authoring.
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:scene/visual_script.dart';
import 'package:scene/grid.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/animation.dart' show AnimationMask;
import 'package:flutter_scene/src/animation/animator.dart';
import 'package:flutter_scene/src/animation/animator_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/ref_read.dart';
import 'package:flutter_scene/src/visual_script/visual_script_component.dart';
import 'package:flutter_scene/src/kit/environment/buoyancy_component.dart';
import 'package:flutter_scene/src/kit/environment/lightning_component.dart';
import 'package:flutter_scene/src/kit/environment/water_component.dart';
import 'package:flutter_scene/src/kit/environment/wind_component.dart';
import 'package:flutter_scene/src/kit/grid/grid_tiles.dart';
import 'package:flutter_scene/src/kit/interaction/path_follower_component.dart';
import 'package:flutter_scene/src/kit/scatter/scatter_layer.dart';

/// Registers the kit component codecs into [registry].
void registerKitComponentCodecs(FsceneComponentRegistry registry) {
  registry
    ..register(PathFollowerCodec())
    ..register(GridTileLayerCodec())
    ..register(AnimatorCodec())
    ..register(ScatterLayerCodec())
    ..register(WaterCodec())
    ..register(BuoyancyCodec())
    ..register(WindCodec())
    ..register(LightningCodec())
    ..register(VisualScriptCodec());
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

// --- Animator ---

const _conditionFields = [
  ComponentPropertyDef(
    'parameter',
    ComponentPropertyKind.string,
    doc: 'The parameter read.',
  ),
  ComponentPropertyDef(
    'comparison',
    ComponentPropertyKind.string,
    defaultValue: StringValue('isTrue'),
    options: ['greater', 'less', 'isTrue', 'isFalse', 'triggered'],
    doc: 'How the parameter is compared.',
  ),
  ComponentPropertyDef(
    'threshold',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'The value compared against, for greater and less.',
  ),
];

const _stopFields = [
  ComponentPropertyDef(
    'at',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'The parameter value this clip is pinned to, on a 1D blend.',
  ),
  ComponentPropertyDef(
    'position',
    ComponentPropertyKind.vec2,
    doc: 'Where this clip sits on the plane, on a 2D blend.',
  ),
  ComponentPropertyDef(
    'clip',
    ComponentPropertyKind.string,
    doc: "The animation's name on the model.",
  ),
];

const _stateFields = [
  ComponentPropertyDef(
    'name',
    ComponentPropertyKind.string,
    doc: 'The state name transitions refer to.',
  ),
  ComponentPropertyDef(
    'clip',
    ComponentPropertyKind.string,
    doc: 'The single clip this state plays; omit when it blends.',
  ),
  ComponentPropertyDef(
    'blendParameter',
    ComponentPropertyKind.string,
    doc: 'The parameter driving the blend; omit for a single clip.',
  ),
  ComponentPropertyDef(
    'blendParameterY',
    ComponentPropertyKind.string,
    doc: 'The second blend parameter; its presence makes the blend 2D.',
  ),
  ComponentPropertyDef(
    'stops',
    ComponentPropertyKind.list,
    itemDef: ComponentPropertyDef(
      'stop',
      ComponentPropertyKind.object,
      objectFields: _stopFields,
    ),
    doc: 'The clips blended across, for a blend state.',
  ),
  ComponentPropertyDef(
    'loop',
    ComponentPropertyKind.boolean,
    defaultValue: BoolValue(true),
    doc: 'Whether the state\'s clips loop.',
  ),
  ComponentPropertyDef(
    'speed',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1),
    doc: 'Playback rate applied to the state\'s clips.',
  ),
  ComponentPropertyDef(
    'position',
    ComponentPropertyKind.vec2,
    doc:
        'Where the state sits on an editor\'s canvas. The runtime ignores it '
        'entirely; it is here so a machine laid out by hand comes back laid '
        'out the same way.',
  ),
];

const _transitionFields = [
  ComponentPropertyDef(
    'from',
    ComponentPropertyKind.string,
    doc: 'The state left, or absent to apply in any state.',
  ),
  ComponentPropertyDef(
    'to',
    ComponentPropertyKind.string,
    doc: 'The state entered.',
  ),
  ComponentPropertyDef(
    'duration',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.2),
    doc: 'Cross-fade length in seconds. Zero is a cut.',
  ),
  ComponentPropertyDef(
    'conditions',
    ComponentPropertyKind.list,
    itemDef: ComponentPropertyDef(
      'condition',
      ComponentPropertyKind.object,
      objectFields: _conditionFields,
    ),
    doc: 'Every condition must hold. Empty holds immediately.',
  ),
];

String _string(PropertyValue? value, [String fallback = '']) =>
    value is StringValue ? value.value : fallback;

/// Codec for [AnimatorComponent]: the states, what each plays, and the
/// transitions between them.
///
/// The machine is constructor-only. An [Animator]'s states and transitions do
/// not change once it is built — a running machine moves between them, it does
/// not rewrite them — so the whole graph is read back out and rebuilt on load
/// rather than written property by property.
class AnimatorCodec extends ComponentCodec {
  @override
  String get type => 'animator';

  @override
  String? get category => 'Animation';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'animator',
    properties: propertySchema,
  );

  @override
  List<ComponentPropertyDef> get propertySchema => const [
    ComponentPropertyDef(
      'initial',
      ComponentPropertyKind.string,
      doc: 'The state the machine starts in.',
    ),
    ComponentPropertyDef(
      'states',
      ComponentPropertyKind.list,
      itemDef: ComponentPropertyDef(
        'state',
        ComponentPropertyKind.object,
        objectFields: _stateFields,
      ),
      doc: 'Every state, with what it plays.',
    ),
    ComponentPropertyDef(
      'transitions',
      ComponentPropertyKind.list,
      itemDef: ComponentPropertyDef(
        'transition',
        ComponentPropertyKind.object,
        objectFields: _transitionFields,
      ),
      doc: 'The transitions, in the order they are tried.',
    ),
    ComponentPropertyDef(
      'layers',
      ComponentPropertyKind.list,
      itemDef: ComponentPropertyDef(
        'layer',
        ComponentPropertyKind.object,
        objectFields: _layerFields,
      ),
      doc:
          'Machines running at once, base first, each over the part of the '
          'skeleton its mask names. Absent for the usual single-layer '
          'machine, which is written as states and transitions directly.',
    ),
  ];

  @override
  Type get componentType => AnimatorComponent;

  @override
  bool claims(Component component) => component is AnimatorComponent;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    // A layered machine is written as layers; a single-layer one is written
    // flat, which is also what every document written before layers existed
    // looks like.
    final rawLayers = spec.properties['layers'];
    if (rawLayers is ListValue && rawLayers.values.isNotEmpty) {
      final layers = <AnimatorLayer>[];
      for (final entry in rawLayers.values) {
        final layer = _decodeLayer(entry);
        if (layer != null) layers.add(layer);
      }
      if (layers.isEmpty) {
        debugPrint('fscene: animator skipped (no layer declares a state)');
        return null;
      }
      return AnimatorComponent(Animator.layered(layers));
    }

    final states = <AnimatorState>[];
    final rawStates = spec.properties['states'];
    if (rawStates is ListValue) {
      for (final entry in rawStates.values) {
        final state = _decodeState(entry);
        if (state != null) states.add(state);
      }
    }
    if (states.isEmpty) {
      debugPrint('fscene: animator skipped (it declares no usable state)');
      return null;
    }

    final transitions = <AnimatorTransition>[];
    final rawTransitions = spec.properties['transitions'];
    if (rawTransitions is ListValue) {
      for (final entry in rawTransitions.values) {
        final transition = _decodeTransition(entry);
        if (transition != null) transitions.add(transition);
      }
    }

    final initial = _string(spec.properties['initial']);
    return AnimatorComponent(
      Animator(
        states: states,
        transitions: transitions,
        initial: initial.isEmpty ? null : initial,
      ),
    );
  }

  AnimatorLayer? _decodeLayer(PropertyValue? value) {
    if (value is! MapValue) return null;
    final states = <AnimatorState>[];
    final rawStates = value.values['states'];
    if (rawStates is ListValue) {
      for (final entry in rawStates.values) {
        final state = _decodeState(entry);
        if (state != null) states.add(state);
      }
    }
    // A layer with nothing to play would freeze whatever it masks, which is
    // worse than not existing.
    if (states.isEmpty) return null;

    final transitions = <AnimatorTransition>[];
    final rawTransitions = value.values['transitions'];
    if (rawTransitions is ListValue) {
      for (final entry in rawTransitions.values) {
        final transition = _decodeTransition(entry);
        if (transition != null) transitions.add(transition);
      }
    }

    final initial = _string(value.values['initial']);
    final name = _string(value.values['name']);
    return AnimatorLayer(
      name: name.isEmpty ? Animator.defaultLayerName : name,
      states: states,
      transitions: transitions,
      initial: initial.isEmpty ? null : initial,
      weight: _num(value.values['weight'], 1),
      mask: _decodeMask(value.values['mask']),
    );
  }

  AnimationMask? _decodeMask(PropertyValue? value) {
    if (value is! MapValue) return null;
    final raw = value.values['nodes'];
    final names = <String>[
      if (raw is ListValue)
        for (final entry in raw.values)
          if (entry is StringValue && entry.value.isNotEmpty) entry.value,
    ];
    if (names.isEmpty) return null;
    return AnimationMask(
      names,
      includeDescendants: switch (value.values['includeDescendants']) {
        BoolValue(value: final v) => v,
        _ => true,
      },
      weight: _num(value.values['weight'], 1),
      outsideWeight: _num(value.values['outsideWeight'], 0),
    );
  }

  AnimatorState? _decodeState(PropertyValue? value) {
    if (value is! MapValue) return null;
    final name = _string(value.values['name']);
    if (name.isEmpty) return null;

    final blendParameter = _string(value.values['blendParameter']);
    final blendParameterY = _string(value.values['blendParameterY']);
    final rawStops = value.values['stops'];
    final entries = <MapValue>[
      if (rawStops is ListValue)
        for (final entry in rawStops.values)
          if (entry is MapValue && _string(entry.values['clip']).isNotEmpty)
            entry,
    ];

    final AnimatorMotion motion;
    if (blendParameter.isNotEmpty &&
        blendParameterY.isNotEmpty &&
        entries.isNotEmpty) {
      motion = BlendMotion2D(blendParameter, blendParameterY, [
        for (final entry in entries)
          (
            x: switch (entry.values['position']) {
              Vec2Value(value: final v) => v.x,
              _ => 0.0,
            },
            y: switch (entry.values['position']) {
              Vec2Value(value: final v) => v.y,
              _ => 0.0,
            },
            clip: _string(entry.values['clip']),
          ),
      ]);
    } else if (blendParameter.isNotEmpty && entries.isNotEmpty) {
      motion = BlendMotion(blendParameter, [
        for (final entry in entries)
          (
            at: _num(entry.values['at'], 0),
            clip: _string(entry.values['clip']),
          ),
      ]);
    } else {
      final clip = _string(value.values['clip']);
      // A state that names neither a clip nor a blend has nothing to play,
      // and a machine that can enter it would freeze there.
      if (clip.isEmpty) return null;
      motion = ClipMotion(clip);
    }

    return AnimatorState(
      name,
      motion,
      loop: switch (value.values['loop']) {
        BoolValue(value: final v) => v,
        _ => true,
      },
      speed: _num(value.values['speed'], 1),
    );
  }

  AnimatorTransition? _decodeTransition(PropertyValue? value) {
    if (value is! MapValue) return null;
    final to = _string(value.values['to']);
    if (to.isEmpty) return null;
    final from = _string(value.values['from']);
    final rawConditions = value.values['conditions'];
    return AnimatorTransition(
      to: to,
      from: from.isEmpty ? null : from,
      duration: _num(value.values['duration'], 0.2),
      conditions: [
        if (rawConditions is ListValue)
          for (final entry in rawConditions.values)
            if (entry is MapValue &&
                _string(entry.values['parameter']).isNotEmpty)
              AnimatorCondition(
                _string(entry.values['parameter']),
                _comparison(_string(entry.values['comparison'], 'isTrue')),
                threshold: _num(entry.values['threshold'], 0),
              ),
      ],
    );
  }

  static AnimatorComparison _comparison(String name) {
    for (final value in AnimatorComparison.values) {
      if (value.name == name) return value;
    }
    debugPrint('fscene: unknown animator comparison "$name"; using isTrue');
    return AnimatorComparison.isTrue;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! AnimatorComponent) return null;
    final animator = component.animator;
    final base = animator.base;
    // The flat form when there is nothing a layer says that the flat form
    // cannot: one layer, full weight, no mask. That keeps the common machine
    // reading the way it always did in a file people diff.
    final isPlain =
        animator.layers.length == 1 &&
        base.mask == null &&
        base.weight == 1.0 &&
        base.name == Animator.defaultLayerName;
    if (!isPlain) {
      return ComponentSpec(
        type,
        properties: {
          'layers': ListValue([
            for (final layer in animator.layers) _encodeLayer(layer),
          ]),
        },
      );
    }
    return ComponentSpec(
      type,
      properties: {
        'initial': StringValue(animator.initialState),
        'states': ListValue([
          for (final state in animator.states) _encodeState(state),
        ]),
        if (animator.transitions.isNotEmpty)
          'transitions': ListValue([
            for (final transition in animator.transitions)
              _encodeTransition(transition),
          ]),
      },
    );
  }

  MapValue _encodeLayer(AnimatorLayer layer) => MapValue({
    'name': StringValue(layer.name),
    'initial': StringValue(layer.initialState),
    'states': ListValue([
      for (final state in layer.states) _encodeState(state),
    ]),
    if (layer.transitions.isNotEmpty)
      'transitions': ListValue([
        for (final transition in layer.transitions)
          _encodeTransition(transition),
      ]),
    if (layer.weight != 1.0) 'weight': DoubleValue(layer.weight),
    if (layer.mask case final mask?) 'mask': _encodeMask(mask),
  });

  MapValue _encodeMask(AnimationMask mask) => MapValue({
    'nodes': ListValue([for (final name in mask.nodeNames) StringValue(name)]),
    if (!mask.includeDescendants) 'includeDescendants': const BoolValue(false),
    if (mask.weight != 1.0) 'weight': DoubleValue(mask.weight),
    if (mask.outsideWeight != 0.0)
      'outsideWeight': DoubleValue(mask.outsideWeight),
  });

  MapValue _encodeState(AnimatorState state) {
    final motion = state.motion;
    return MapValue({
      'name': StringValue(state.name),
      if (motion is ClipMotion) 'clip': StringValue(motion.clip),
      if (motion is BlendMotion) ...{
        'blendParameter': StringValue(motion.parameter),
        'stops': ListValue([
          for (final stop in motion.stops)
            MapValue({
              'at': DoubleValue(stop.at),
              'clip': StringValue(stop.clip),
            }),
        ]),
      },
      if (motion is BlendMotion2D) ...{
        'blendParameter': StringValue(motion.parameterX),
        'blendParameterY': StringValue(motion.parameterY),
        'stops': ListValue([
          for (final stop in motion.stops)
            MapValue({
              'position': Vec2Value(Vector2(stop.x, stop.y)),
              'clip': StringValue(stop.clip),
            }),
        ]),
      },
      if (!state.loop) 'loop': const BoolValue(false),
      if (state.speed != 1) 'speed': DoubleValue(state.speed),
    });
  }

  MapValue _encodeTransition(AnimatorTransition transition) => MapValue({
    if (transition.from case final from?) 'from': StringValue(from),
    'to': StringValue(transition.to),
    if (transition.duration != 0.2)
      'duration': DoubleValue(transition.duration),
    if (transition.conditions.isNotEmpty)
      'conditions': ListValue([
        for (final condition in transition.conditions)
          MapValue({
            'parameter': StringValue(condition.parameter),
            'comparison': StringValue(condition.comparison.name),
            if (condition.threshold != 0)
              'threshold': DoubleValue(condition.threshold),
          }),
      ]),
  });
}

const _maskFields = [
  ComponentPropertyDef(
    'nodes',
    ComponentPropertyKind.list,
    itemDef: ComponentPropertyDef('node', ComponentPropertyKind.string),
    doc: 'The joints the mask is anchored on.',
  ),
  ComponentPropertyDef(
    'includeDescendants',
    ComponentPropertyKind.boolean,
    defaultValue: BoolValue(true),
    doc:
        'Whether everything under a named joint is covered too, which is how '
        'one spine name means the whole upper body.',
  ),
  ComponentPropertyDef(
    'weight',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1),
    doc: 'Strength inside the mask.',
    constraints: [Range(0, 1)],
  ),
  ComponentPropertyDef(
    'outsideWeight',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Strength outside it. Above zero is a partial blend, not a cut.',
    constraints: [Range(0, 1)],
  ),
];

const _layerFields = [
  ComponentPropertyDef(
    'name',
    ComponentPropertyKind.string,
    doc:
        'The layer\'s name, which also keeps its clips apart from another '
        'layer\'s playing the same animation.',
  ),
  ComponentPropertyDef(
    'initial',
    ComponentPropertyKind.string,
    doc: 'The state this layer starts in.',
  ),
  ComponentPropertyDef(
    'weight',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1),
    doc: 'How strongly the layer contributes. Zero skips it entirely.',
    constraints: [Range(0, 1)],
  ),
  ComponentPropertyDef(
    'mask',
    ComponentPropertyKind.object,
    objectFields: _maskFields,
    doc: 'Which joints the layer may move. Absent means all of them.',
  ),
  ComponentPropertyDef(
    'states',
    ComponentPropertyKind.list,
    itemDef: ComponentPropertyDef(
      'state',
      ComponentPropertyKind.object,
      objectFields: _stateFields,
    ),
    doc: 'Every state on this layer.',
  ),
  ComponentPropertyDef(
    'transitions',
    ComponentPropertyKind.list,
    itemDef: ComponentPropertyDef(
      'transition',
      ComponentPropertyKind.object,
      objectFields: _transitionFields,
    ),
    doc: 'This layer\'s transitions, in the order they are tried.',
  ),
];

// --- Scattered instances ---

const _placementFields = [
  ComponentPropertyDef(
    'position',
    ComponentPropertyKind.vec3,
    doc: 'Where the instance stands.',
  ),
  ComponentPropertyDef(
    'yaw',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Its turn about the vertical axis, in radians.',
  ),
  ComponentPropertyDef(
    'scale',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1),
    doc: 'A uniform scale.',
  ),
];

/// Codec for [ScatterLayer]: the instanced geometry and every placement.
///
/// Hand-written for the same reason the tile layer's is: the geometry and
/// material are resource references, so realizing one can fail.
///
/// Placements are written out one by one rather than as a seed and a density.
/// A painted set is not a formula — the whole point is that individual trees
/// were moved, removed, and put back — so it is stored as what it is.
class ScatterLayerCodec extends ComponentCodec {
  @override
  String get type => 'scatterLayer';

  @override
  String? get category => 'Mesh';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'scatter',
    properties: propertySchema,
  );

  @override
  List<ComponentPropertyDef> get propertySchema => const [
    ComponentPropertyDef(
      'geometry',
      ComponentPropertyKind.resourceRef,
      doc: 'The geometry drawn once per instance.',
      resourceKind: 'geometry',
    ),
    ComponentPropertyDef(
      'material',
      ComponentPropertyKind.resourceRef,
      doc: 'The material the instances are drawn with.',
      resourceKind: 'material',
    ),
    ComponentPropertyDef(
      'cullInstances',
      ComponentPropertyKind.boolean,
      defaultValue: BoolValue(true),
      doc: 'Test each instance against the view separately.',
    ),
    ComponentPropertyDef(
      'placements',
      ComponentPropertyKind.list,
      itemDef: ComponentPropertyDef(
        'placement',
        ComponentPropertyKind.object,
        objectFields: _placementFields,
      ),
      doc: 'Every scattered instance.',
    ),
  ];

  @override
  Type get componentType => ScatterLayer;

  @override
  bool claims(Component component) => component is ScatterLayer;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final realizer = context.resources;
    if (realizer == null) {
      debugPrint('fscene: scatterLayer skipped (no resource realizer)');
      return null;
    }
    final geometryRef = spec.properties['geometry'];
    final materialRef = spec.properties['material'];
    if (geometryRef is! ResourceRefValue || materialRef is! ResourceRefValue) {
      debugPrint(
        'fscene: scatterLayer skipped (it needs both a geometry and a '
        'material reference)',
      );
      return null;
    }

    final layer = ScatterLayer(
      geometry: realizer.geometry(geometryRef.id),
      material: realizer.material(materialRef.id),
      cullInstances: switch (spec.properties['cullInstances']) {
        BoolValue(value: final v) => v,
        _ => true,
      },
    );

    final placements = spec.properties['placements'];
    if (placements is ListValue) {
      for (final entry in placements.values) {
        if (entry is! MapValue) continue;
        final position = entry.values['position'];
        // A placement with nowhere to stand is dropped rather than piled at
        // the origin, where it would look like a bug in the brush.
        if (position is! Vec3Value) continue;
        layer.add(
          ScatterPlacement(
            position: position.value.clone(),
            yaw: _num(entry.values['yaw'], 0),
            scale: _num(entry.values['scale'], 1),
          ),
        );
      }
    }
    return layer;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! ScatterLayer) return null;
    final geometry = resourceRefOf(component.mesh.geometry, context);
    final material = resourceRefOf(component.mesh.material, context);
    if (geometry == null || material == null) {
      debugPrint(
        'fscene: scatterLayer not saved (its geometry or material was built '
        'in code and has no source resource to reference)',
      );
      return null;
    }
    return ComponentSpec(
      type,
      properties: {
        'geometry': geometry,
        'material': material,
        if (!component.mesh.cullInstances)
          'cullInstances': const BoolValue(false),
        if (!component.isEmpty)
          'placements': ListValue([
            for (final placement in component.placements)
              MapValue({
                'position': Vec3Value(placement.position.clone()),
                if (placement.yaw != 0) 'yaw': DoubleValue(placement.yaw),
                if (placement.scale != 1) 'scale': DoubleValue(placement.scale),
              }),
          ]),
      },
    );
  }
}

/// Codec for [WaterComponent].
///
/// The surface's mesh and material are not properties: the component builds
/// both from the style, and an authored override of either would be undone
/// the next time the style changed. What is authored is the shape of the body
/// of water, how it looks, and whether anything can cross it.
class WaterCodec extends DeclarativeComponentCodec<WaterComponent> {
  @override
  String get type => 'water';

  @override
  String? get category => 'Environment';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'water',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      // The footprint, drawn as the square the surface actually covers, so
      // its extent is visible before the water is deep enough to see. Bound
      // to size, so dragging the field redraws the outline.
      GizmoWireRect(
        width: GizmoScalar.bind('size'),
        height: GizmoScalar.bind('size'),
        axis: [0, 1, 0],
        color: GizmoColor(0.30, 0.68, 0.85),
      ),
    ]),
  );

  @override
  List<ComponentField<WaterComponent>> get fields => [
    ComponentField.number(
      'size',
      defaultValue: 40.0,
      doc: 'Extent across X and Z, in world units, centred on the node.',
      constraints: const [Range.nonNegative(), SoftRange(1, 500)],
      get: (c) => c.size,
    ),
    ComponentField.integer(
      'resolution',
      defaultValue: 48,
      doc:
          'Quads per side. The surface is displaced on the CPU each frame, so '
          'the cost of this is quadratic; lower it before anything else when '
          'the frame budget is tight.',
      constraints: const [IntRange(2, 512)],
      get: (c) => c.resolution,
    ),
    ComponentField.enumString(
      'style',
      values: WaterStyle.values,
      defaultValue: WaterStyle.realistic,
      doc: 'Which look to build: faceted, lit, or sunlit.',
      get: (c) => c.style,
      set: (c, v) => c.style = v,
    ),
    ComponentField.enumString(
      'traversal',
      values: WaterTraversal.values,
      defaultValue: WaterTraversal.swimmable,
      doc:
          'How agents may cross the surface. The nav bake reads this: '
          'walkable bakes as ground, swimmable as costly ground a path routes '
          'around, blocked as a hole.',
      get: (c) => c.traversal,
      set: (c, v) => c.traversal = v,
    ),
    ComponentField.vec4(
      'shallowColor',
      defaultValue: () => Vector4(0.13, 0.52, 0.62, 0.86),
      doc: 'Linear RGBA at the surface.',
      get: (c) => c.shallowColor,
      set: (c, v) => c.shallowColor.setFrom(v),
    ),
    ComponentField.vec4(
      'deepColor',
      defaultValue: () => Vector4(0.02, 0.13, 0.22, 1.0),
      doc: 'Linear RGBA light attenuates toward with depth.',
      get: (c) => c.deepColor,
      set: (c, v) => c.deepColor.setFrom(v),
    ),
    ComponentField.number(
      'choppiness',
      defaultValue: 1.0,
      doc:
          'How hard the water is running: 0 glassy, 1 the waves as authored, '
          'above that a sea getting up. Weather drives it.',
      constraints: const [Range.nonNegative(), SoftRange(0, 2.5)],
      get: (c) => c.choppiness,
      set: (c, v) => c.choppiness = v,
    ),
    ComponentField.boolean(
      'animate',
      defaultValue: true,
      doc: 'Whether the waves advance with time.',
      get: (c) => c.animate,
      set: (c, v) => c.animate = v,
    ),
  ];

  @override
  WaterComponent create(PropertyReader props) => WaterComponent(
    size: props.number('size'),
    resolution: props.integer('resolution'),
    style: props.enumValue('style', WaterStyle.values),
    traversal: props.enumValue('traversal', WaterTraversal.values),
    choppiness: props.number('choppiness'),
    shallowColor: props.vec4('shallowColor'),
    deepColor: props.vec4('deepColor'),
    animate: props.boolean('animate'),
  );
}

/// Codec for [BuoyancyComponent].
///
/// The water is not a property: the component finds the surface it is over on
/// mount, and an authored reference to a live object has nowhere to point in
/// a document. What is authored is how the thing floats.
class BuoyancyCodec extends DeclarativeComponentCodec<BuoyancyComponent> {
  @override
  String get type => 'buoyancy';

  @override
  String? get category => 'Environment';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'buoyancy',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      // The hull footprint, which is where the probes go, so the spread is
      // visible against the thing it is meant to hold up.
      GizmoWireRect(
        width: GizmoScalar.bind('hullSize'),
        height: GizmoScalar.bind('hullSize'),
        axis: [0, 1, 0],
        color: GizmoColor(0.30, 0.68, 0.85),
      ),
    ]),
  );

  @override
  List<ComponentField<BuoyancyComponent>> get fields => [
    ComponentField.number(
      'hullSize',
      defaultValue: 1.0,
      doc:
          'How wide the floating thing is. The probes spread over a square '
          'this size, so a long boat pitches where a small crate does not.',
      constraints: const [Range.nonNegative(), SoftRange(0.1, 20)],
      get: (c) => c.hullSize,
      set: (c, v) => c.hullSize = v,
    ),
    ComponentField.number(
      'draft',
      defaultValue: 0.0,
      doc:
          'How far the resting waterline sits below the node origin. A hull '
          'modelled from its deck wants its own depth here.',
      constraints: const [SoftRange(-5, 5)],
      get: (c) => c.draft,
      set: (c, v) => c.draft = v,
    ),
    ComponentField.integer(
      'probeCount',
      defaultValue: 4,
      doc:
          'Probes around the hull: 1 bobs without tilting, 4 is a hull, 8 is '
          'a long boat that feels a wave pass down its length. One wave-field '
          'sample each, per frame.',
      constraints: const [IntRange(1, 8)],
      get: (c) => c.probeCount,
      set: (c, v) => c.probeCount = v == 1 || v == 8 ? v : 4,
    ),
    ComponentField.number(
      'strength',
      defaultValue: 12.0,
      doc:
          'How hard the water pushes back per unit of submersion. Near '
          'gravity floats a thing at its waterline; higher rides high and '
          'lively.',
      constraints: const [Range.nonNegative(), SoftRange(0, 40)],
      get: (c) => c.strength,
      set: (c, v) => c.strength = v,
    ),
    ComponentField.number(
      'linearDamping',
      defaultValue: 1.4,
      doc:
          'Velocity bled off per second while submerged. Water is not a '
          'spring; without this a float oscillates forever.',
      constraints: const [Range.nonNegative(), SoftRange(0, 8)],
      get: (c) => c.linearDamping,
      set: (c, v) => c.linearDamping = v,
    ),
    ComponentField.number(
      'angularDamping',
      defaultValue: 2.2,
      doc: 'Angular velocity bled off per second while submerged.',
      constraints: const [Range.nonNegative(), SoftRange(0, 8)],
      get: (c) => c.angularDamping,
      set: (c, v) => c.angularDamping = v,
    ),
    ComponentField.boolean(
      'alignToSurface',
      defaultValue: true,
      doc:
          'Whether the node tilts to the surface it is riding. Ignored when '
          'the node has a rigid body, which gets its tilt from the forces.',
      get: (c) => c.alignToSurface,
      set: (c, v) => c.alignToSurface = v,
    ),
    ComponentField.number(
      'alignResponse',
      defaultValue: 6.0,
      doc: 'How fast that tilt catches up. Low is a barge, high is a leaf.',
      constraints: const [Range.nonNegative(), SoftRange(0, 20)],
      get: (c) => c.alignResponse,
      set: (c, v) => c.alignResponse = v,
    ),
  ];

  @override
  BuoyancyComponent create(PropertyReader props) => BuoyancyComponent(
    hullSize: props.number('hullSize'),
    draft: props.number('draft'),
    probeCount: props.integer('probeCount'),
    strength: props.number('strength'),
    linearDamping: props.number('linearDamping'),
    angularDamping: props.number('angularDamping'),
    alignToSurface: props.boolean('alignToSurface'),
    alignResponse: props.number('alignResponse'),
  );
}

/// Codec for [WindComponent].
///
/// The wind itself is not a property tree of its own. A scene has one wind,
/// the component drives it, and everything downwind reads it -- so what is
/// authored is the weather, and the object it is written into is shared
/// rather than owned.
class WindCodec extends DeclarativeComponentCodec<WindComponent> {
  @override
  String get type => 'wind';

  @override
  String? get category => 'Environment';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'wind',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      // Which way it blows, drawn at the node, because a wind vector is the
      // one weather setting with a direction and no other way to see it.
      GizmoArrow(
        axis: [1, 0, 0],
        length: GizmoScalar(2),
        color: GizmoColor(0.62, 0.80, 0.92),
      ),
    ]),
  );

  @override
  List<ComponentField<WindComponent>> get fields => [
    ComponentField.vec2(
      'direction',
      defaultValue: () => Vector2(1, 0.25),
      doc: 'Where the wind is going, on the ground plane.',
      get: (c) => c.wind.direction,
      set: (c, v) => c.wind.setDirection(v),
    ),
    ComponentField.number(
      'speed',
      defaultValue: 3.0,
      doc: 'Steady speed in world units per second.',
      constraints: const [Range.nonNegative(), SoftRange(0, 30)],
      get: (c) => c.wind.speed,
      set: (c, v) => c.wind.speed = v,
    ),
    ComponentField.number(
      'gustAmplitude',
      defaultValue: 0.35,
      doc:
          'How far the gust swings the speed, as a fraction of it. Zero is a '
          'fan; one is a squall that stills and doubles.',
      constraints: const [Range(0, 2), SoftRange(0, 1)],
      get: (c) => c.wind.gustAmplitude,
      set: (c, v) => c.wind.gustAmplitude = v,
    ),
    ComponentField.number(
      'gustFrequency',
      defaultValue: 0.15,
      doc: 'How often the gust cycles, in hertz.',
      constraints: const [Range.nonNegative(), SoftRange(0, 2)],
      get: (c) => c.wind.gustFrequency,
      set: (c, v) => c.wind.gustFrequency = v,
    ),
    ComponentField.boolean(
      'driveSky',
      defaultValue: true,
      doc:
          'Whether the scene\'s weather sky scrolls with this. Clouds that '
          'ignore the wind are the most visible way for weather to look '
          'wrong.',
      get: (c) => c.driveSky,
      set: (c, v) => c.driveSky = v,
    ),
    ComponentField.number(
      'skyScale',
      defaultValue: 0.02,
      doc:
          'How fast the cloud layer scrolls per unit of wind speed. Clouds '
          'are far away, so this is a look rather than a physical quantity.',
      constraints: const [Range.nonNegative(), SoftRange(0, 0.2)],
      get: (c) => c.skyScale,
      set: (c, v) => c.skyScale = v,
    ),
  ];

  @override
  WindComponent create(PropertyReader props) {
    // Drives the scene's ambient wind, which is what a WindModule with no
    // wind of its own reads. Two wind components in one scene drive the same
    // object, and the last one to tick wins -- which is the honest outcome of
    // a scene that says the wind is two things at once.
    final component = WindComponent(driveSky: props.boolean('driveSky'))
      ..skyScale = props.number('skyScale');
    component.wind
      ..speed = props.number('speed')
      ..gustAmplitude = props.number('gustAmplitude')
      ..gustFrequency = props.number('gustFrequency')
      ..setDirection(props.vec2('direction'));
    return component;
  }
}

/// Codec for [LightningComponent].
///
/// The sky and the light it drives are not properties: the component finds
/// the scene's own weather sky on mount, and an authored reference to a live
/// object has nowhere to point in a document. What is authored is the storm's
/// shape: how often it strikes, how far away, and how dark it holds the sky.
class LightningCodec extends DeclarativeComponentCodec<LightningComponent> {
  @override
  String get type => 'lightning';

  @override
  String? get category => 'Environment';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'lightning',
    properties: propertySchema,
  );

  @override
  List<ComponentField<LightningComponent>> get fields => [
    ComponentField.number(
      'minInterval',
      defaultValue: 4.0,
      doc: 'Shortest gap between strikes, in seconds.',
      constraints: const [Range.nonNegative(), SoftRange(0.5, 60)],
      get: (c) => c.minInterval,
      set: (c, v) => c.minInterval = v,
    ),
    ComponentField.number(
      'maxInterval',
      defaultValue: 14.0,
      doc: 'Longest gap between strikes, in seconds.',
      constraints: const [Range.nonNegative(), SoftRange(0.5, 120)],
      get: (c) => c.maxInterval,
      set: (c, v) => c.maxInterval = v,
    ),
    ComponentField.number(
      'minDistance',
      defaultValue: 300.0,
      doc:
          'Nearest a bolt can strike, in world units. Distance sets both how '
          'bright the flash is and how long the thunder takes to arrive.',
      constraints: const [Range.nonNegative(), SoftRange(10, 5000)],
      get: (c) => c.minDistance,
      set: (c, v) => c.minDistance = v,
    ),
    ComponentField.number(
      'maxDistance',
      defaultValue: 4000.0,
      doc: 'Furthest a bolt can strike, in world units.',
      constraints: const [Range.nonNegative(), SoftRange(10, 20000)],
      get: (c) => c.maxDistance,
      set: (c, v) => c.maxDistance = v,
    ),
    ComponentField.number(
      'speedOfSound',
      defaultValue: 343.0,
      doc:
          'World units per second sound travels, which is what delays the '
          'thunder. Scale it with the world\'s units.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.speedOfSound,
      set: (c, v) => c.speedOfSound = v,
    ),
    ComponentField.number(
      'flashDuration',
      defaultValue: 0.42,
      doc: 'How long a flash lasts, in seconds.',
      constraints: const [Range.nonNegative(), SoftRange(0.05, 2)],
      get: (c) => c.flashDuration,
      set: (c, v) => c.flashDuration = v,
    ),
    ComponentField.number(
      'lightIntensity',
      defaultValue: 12.0,
      doc: 'Peak intensity added to the driven light at the top of a strike.',
      constraints: const [Range.nonNegative(), SoftRange(0, 60)],
      get: (c) => c.lightIntensity,
      set: (c, v) => c.lightIntensity = v,
    ),
    ComponentField.number(
      'stormDarkening',
      defaultValue: 0.7,
      doc: 'How overcast the sky is held while the storm runs.',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.stormDarkening,
      set: (c, v) => c.stormDarkening = v,
    ),
  ];

  @override
  LightningComponent create(PropertyReader props) => LightningComponent(
    minInterval: props.number('minInterval'),
    maxInterval: props.number('maxInterval'),
    minDistance: props.number('minDistance'),
    maxDistance: props.number('maxDistance'),
    speedOfSound: props.number('speedOfSound'),
    flashDuration: props.number('flashDuration'),
    lightIntensity: props.number('lightIntensity'),
    stormDarkening: props.number('stormDarkening'),
  );
}

/// Codec for [VisualScriptComponent].
///
/// The graph travels as its own JSON text rather than as a nest of typed
/// properties. A graph is source: people diff it, merge it, and occasionally
/// fix one by hand, and a wire list flattened into the component schema would
/// be unreadable in all three. The property is one string, and the format is
/// documented by `writeVisualScript`.
class VisualScriptCodec
    extends DeclarativeComponentCodec<VisualScriptComponent> {
  @override
  String get type => visualScriptComponentType;

  @override
  String? get category => 'Scripting';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'visualScript',
    properties: propertySchema,
  );

  @override
  List<ComponentField<VisualScriptComponent>> get fields => [
    ComponentField.string(
      'graph',
      defaultValue: '',
      doc:
          'The blueprint, as the JSON writeBlueprint produces. Edited on the '
          'Visual Scripter canvas rather than here. A document written before '
          'blueprints holds a single graph here, which reads as a blueprint '
          'with that one event graph in it.',
      get: (c) =>
          _blueprintIsEmpty(c.blueprint) ? '' : writeBlueprint(c.blueprint),
      set: (c, v) {
        if (v.isEmpty) return;
        final blueprint = _readBlueprintOrNull(v);
        if (blueprint != null) c.blueprint = blueprint;
      },
    ),
    ComponentField.boolean(
      'running',
      defaultValue: true,
      doc:
          'Whether the graph ticks. Turning it off leaves its state intact, '
          'so it pauses rather than restarts.',
      get: (c) => c.running,
      set: (c, v) => c.running = v,
    ),
  ];

  @override
  VisualScriptComponent create(PropertyReader props) {
    final source = props.string('graph');
    final blueprint = source.isEmpty ? null : _readBlueprintOrNull(source);
    return VisualScriptComponent(blueprint: blueprint)
      ..running = props.boolean('running');
  }
}

/// Whether [blueprint] has nothing in it worth writing.
///
/// An empty blueprint writes nothing at all, so a component somebody added
/// and has not drawn in yet does not put a wall of JSON in the document.
bool _blueprintIsEmpty(Blueprint blueprint) {
  if (blueprint.variables.isNotEmpty) return false;
  if (blueprint.graphs.length > 1) return false;
  for (final graph in blueprint.graphs) {
    if (graph.nodes.isNotEmpty || graph.variables.isNotEmpty) return false;
  }
  return true;
}

/// Reads a blueprint from [source], or null when it cannot be read.
///
/// Reports rather than throws: a document with one unreadable script in it
/// should open with that script empty, not fail to open.
Blueprint? _readBlueprintOrNull(String source) {
  try {
    return readBlueprint(source);
  } on FormatException catch (error) {
    debugPrint('fscene: a visual script failed to parse: $error');
    return null;
  }
}
