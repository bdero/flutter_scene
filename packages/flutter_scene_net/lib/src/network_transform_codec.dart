import 'package:flutter/foundation.dart';
import 'package:flutter_scene/fscene.dart';

import 'package:flutter_scene/scene.dart';

import 'network_identity.dart';

import 'network_transform.dart';

/// Registers this package's component codecs into [registry] (the process
/// default when omitted).
void registerNetComponentCodecs([FsceneComponentRegistry? registry]) {
  (registry ?? defaultComponentRegistry())
    ..register(NetworkTransformCodec())
    ..register(NetworkIdentityCodec());
}

/// Codec for [NetworkTransformComponent] (`networkTransform`).
///
/// The replica is a live network handle the app provides in code, so the
/// component cannot realize from a document alone; loading a scene carrying
/// one skips it with a debug note, while serialization keeps the configured
/// delay. TODO(replica-slots): realize through an app-registered
/// replica-slot convention, the widget-slot pattern applied to networking.
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
    debugPrint(
      'flutter_scene_net: a networkTransform component needs a replica '
      'provided in code; skipped',
    );
    return null;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! NetworkTransformComponent) return null;
    return ComponentSpec(
      type,
      properties: {
        if (component.delay.inMilliseconds != 100)
          'delayMilliseconds': IntValue(component.delay.inMilliseconds),
      },
    );
  }
}
