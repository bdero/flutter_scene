/// Events, as opposed to state.
///
/// Replicated properties carry things that are continuously true — where a
/// player is, how much health it has — and they are the wrong tool for things
/// that merely *happen*. A shot fired, a door opened, a round won: those occur
/// once, and a property that flickered to record one would be a property whose
/// change you might miss between two snapshots.
///
/// So this is the other half. A [NetworkEvent] is a named message an object
/// can send, with a target saying who runs it — the server, the owning client,
/// everyone else, or everybody. A remote call, in other words, with the
/// direction named on the declaration rather than implied by which of two
/// kinds it is.
///
/// **The direction is the security boundary.** An event targeted at the server
/// is a client asking for something, and the server decides. That is the whole
/// reason a client cannot simply write its own health: the request goes one
/// way, the authority goes the other, and a client that could shortcut it is a
/// client that never dies.
library;

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/fscene.dart';

/// One event an object can send.
class NetworkEvent {
  const NetworkEvent(
    this.name, {
    this.to = RpcTarget.server,
    this.delivery = Delivery.reliable,
    this.requireOwner = true,
  });

  /// The event's name, matched across the two ends.
  final String name;

  /// Who runs it when it is sent.
  ///
  /// [RpcTarget.notOwner] is the one worth knowing about: everyone except the
  /// object's owner. The client that fired has already drawn its own muzzle
  /// flash, and sending it back is wasted at best and a second flash a frame
  /// later at worst. Distinct from [RpcTarget.others], which excludes the
  /// *server* rather than the owner.
  final RpcTarget to;

  /// Whether it is guaranteed to arrive.
  ///
  /// Reliable by default. An event is a thing that happened once, so losing
  /// one loses it for good — unlike a property, where the next snapshot
  /// carries the truth again. Unreliable is for the events where being late
  /// is worse than being missed: a footstep, a hit spark.
  final Delivery delivery;

  /// For events aimed at the server, whether only the owning client may send.
  ///
  /// On by default, and it is the check that stops one client acting for
  /// another: without it, "fire my weapon" is a message anybody can send about
  /// anybody.
  final bool requireOwner;
}

/// The document form of a declared event.
const List<ComponentPropertyDef> networkEventFields = [
  ComponentPropertyDef(
    'name',
    ComponentPropertyKind.string,
    defaultValue: StringValue(''),
    doc: 'What the event is called. Both ends match on this.',
  ),
  ComponentPropertyDef(
    'to',
    ComponentPropertyKind.string,
    defaultValue: StringValue('server'),
    options: ['server', 'owner', 'others', 'all', 'notOwner'],
    doc:
        'Who runs it. Server is a client asking the server for something; the '
        'rest are the server telling clients that something happened. '
        'notOwner is everyone but the object\'s owner, for an event its '
        'owner has already acted on locally.',
  ),
  ComponentPropertyDef(
    'delivery',
    ComponentPropertyKind.string,
    defaultValue: StringValue('reliable'),
    options: ['reliable', 'unreliable'],
    doc:
        'Reliable unless being late is worse than being missed. An event '
        'happens once, so a lost one is lost for good.',
  ),
  ComponentPropertyDef(
    'requireOwner',
    ComponentPropertyKind.boolean,
    defaultValue: BoolValue(true),
    doc:
        'For server events, whether only the owning client may send it. Off '
        'means anyone may send it about anyone.',
  ),
];

/// Encodes [event] as the document holds it.
MapValue encodeNetworkEvent(NetworkEvent event) => MapValue({
  'name': StringValue(event.name),
  'to': StringValue(event.to.name),
  'delivery': StringValue(event.delivery.name),
  'requireOwner': BoolValue(event.requireOwner),
});

/// Decodes one event, or null when it names nothing.
///
/// A row with no name is a half-filled row in the inspector, which is what one
/// looks like the moment it is added. Dropping it beats refusing to load the
/// scene around it.
NetworkEvent? decodeNetworkEvent(PropertyValue? value) {
  if (value is! MapValue) return null;
  final map = value.values;
  String string(String key, String fallback) =>
      map[key] is StringValue ? (map[key]! as StringValue).value : fallback;
  final name = string('name', '');
  if (name.isEmpty) return null;
  return NetworkEvent(
    name,
    to:
        RpcTarget.values
            .where((target) => target.name == string('to', ''))
            .firstOrNull ??
        RpcTarget.server,
    delivery: string('delivery', 'reliable') == 'unreliable'
        ? Delivery.unreliable
        : Delivery.reliable,
    requireOwner: switch (map['requireOwner']) {
      BoolValue(value: final v) => v,
      _ => true,
    },
  );
}

/// What one end does when an event arrives.
typedef NetworkEventHandler = void Function(int fromPeerId, String payload);

/// Two events declared with the same name.
class DuplicateNetworkEvent implements Exception {
  DuplicateNetworkEvent(this.name);

  final String name;

  @override
  String toString() =>
      'flutter_scene_net: two events are declared as "$name". Events are '
      'matched by name across the two ends, so a name has to mean one thing.';
}

/// An event nobody declared.
class UnknownNetworkEvent implements Exception {
  UnknownNetworkEvent(this.name, this.declared);

  final String name;
  final List<String> declared;

  @override
  String toString() =>
      'flutter_scene_net: no event called "$name" is declared on this object. '
      'It declares: ${declared.isEmpty ? '(none)' : declared.join(', ')}.';
}
