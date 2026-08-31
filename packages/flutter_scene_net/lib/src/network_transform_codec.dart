import 'package:flutter/foundation.dart';
import 'package:flutter_scene/fscene.dart';

import 'package:flutter_scene/scene.dart';

import 'network_identity.dart';

import 'network_transform.dart';
import 'replica_slots.dart';

/// Registers this package's component codecs into [registry] (the process
/// default when omitted).
void registerNetComponentCodecs([FsceneComponentRegistry? registry]) {
  (registry ?? defaultComponentRegistry())
    ..register(NetworkTransformCodec())
    ..register(NetworkIdentityCodec());
}

/// Codec for [NetworkTransformComponent] (`networkTransform`).
///
/// The replica is a live network handle that belongs to a running session
/// rather than to a file, so the document names a *slot* and the app says
/// what each name resolves to (see [ReplicaSlots]). A document that names no
/// slot, or one nobody supplies, realizes to nothing -- a scene can be loaded
/// before the session that fills it exists, and that is not an error.
class NetworkTransformCodec extends ComponentCodec {
  @override
  String get type => 'networkTransform';

  @override
  Type get componentType => NetworkTransformComponent;

  @override
  ComponentSchema get schema => const ComponentSchema(
    'networkTransform',
    doc: 'Drives the node pose from a replicated transform.',
    properties: propertyDefs,
  );

  /// Extracted so [propertySchema] and [schema] share one list.
  static const List<ComponentPropertyDef> propertyDefs = [
    ComponentPropertyDef(
      'slot',
      ComponentPropertyKind.string,
      defaultValue: StringValue(''),
      doc:
          'The replica this node is driven by, by name. The app resolves it '
          'through ReplicaSlots; a name nothing supplies leaves the node '
          'undriven rather than failing the load.',
    ),
    ComponentPropertyDef(
      'delayMilliseconds',
      ComponentPropertyKind.integer,
      defaultValue: IntValue(100),
      doc: 'How far in the past remote poses render (snapshot interpolation).',
      constraints: [IntRange(0, null), SoftRange(0, 500)],
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => propertyDefs;

  @override
  bool claims(Component component) => component is NetworkTransformComponent;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final slot = switch (spec.properties['slot']) {
      StringValue(value: final name) => name,
      _ => '',
    };
    final replica = ReplicaSlots.resolve(slot);
    if (replica == null) {
      // Two different situations, and only one of them is worth a note. A
      // document naming no slot is a scene that has not been wired up yet; a
      // document naming one nobody supplies is probably a typo or a session
      // that has not started, and saying which name went unanswered is the
      // only way to tell those apart.
      if (slot.isNotEmpty) {
        debugPrint(
          'flutter_scene_net: no replica is registered for slot "\$slot", so '
          'that node is not driven. Register one with ReplicaSlots.',
        );
      }
      return null;
    }
    final delay = switch (spec.properties['delayMilliseconds']) {
      IntValue(value: final ms) => Duration(milliseconds: ms),
      _ => const Duration(milliseconds: 100),
    };
    return NetworkTransformComponent(replica, slot: slot, delay: delay);
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! NetworkTransformComponent) return null;
    return ComponentSpec(
      type,
      properties: {
        if (component.slot.isNotEmpty) 'slot': StringValue(component.slot),
        if (component.delay.inMilliseconds != 100)
          'delayMilliseconds': IntValue(component.delay.inMilliseconds),
      },
    );
  }
}
