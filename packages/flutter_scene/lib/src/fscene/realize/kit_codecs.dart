/// Codecs for the gameplay components in `package:flutter_scene/kit.dart`.
///
/// These are ordinary [Component]s that were only ever assembled in code, so
/// the editor could not list, inspect, or save one. Runtime state that input
/// or gameplay owns (a route being walked, the tiles placed so far) is not
/// declared here: it is the product of play, not of authoring.
library;

import 'package:scene/schema.dart';

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/kit/interaction/path_follower_component.dart';

/// Registers the kit component codecs into [registry].
void registerKitComponentCodecs(FsceneComponentRegistry registry) {
  registry.register(PathFollowerCodec());
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
  ComponentSchema get schema =>
      ComponentSchema(type, icon: 'path', properties: propertySchema);

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
