/// Naming a replica in a document.
///
/// A replicated component needs a live network handle, and a document cannot
/// hold one: a replica belongs to a running session, not to a file. So a
/// scene carrying a `networkTransform` used to be unloadable — the component
/// was skipped with a note, and the only way to get one was to build it in
/// code after the scene had loaded.
///
/// A slot closes that gap the way widget slots close the same one elsewhere:
/// the document names a slot, the app says what each name resolves to, and
/// the codec asks. The document stays a description of the scene and the app
/// keeps the part only it can know.
///
/// ```dart
/// ReplicaSlots.resolveWith((slot) => switch (slot) {
///   'player' => session.localPlayerReplica,
///   _ => spawned[slot],
/// });
/// ```
library;

import 'package:dashwire_replication/dashwire_replication.dart';

/// Resolves the slot name a document carries to a live replica.
///
/// Returning null means "not right now", which is a normal answer: a scene
/// can be loaded before the session that fills it exists.
typedef ReplicaSlotResolver = TransformReplica? Function(String slot);

/// Where an app says what a document's slot names mean.
///
/// Process-wide, like the component registry it works alongside. A slot name
/// is a contract between one document and one app, and an app that loads two
/// scenes wants the same resolver for both.
abstract final class ReplicaSlots {
  static ReplicaSlotResolver? _resolver;

  /// Whether anything has been registered.
  static bool get hasResolver => _resolver != null;

  /// Registers [resolver] as the answer for every slot.
  static void resolveWith(ReplicaSlotResolver resolver) => _resolver = resolver;

  /// Forgets the registered resolver.
  ///
  /// For a session ending, and for tests: a resolver left over from one test
  /// answering another test's lookups is the kind of failure that only
  /// appears when the suite runs in a particular order.
  static void clear() => _resolver = null;

  /// The replica for [slot], or null when nothing supplies one.
  ///
  /// An empty slot name resolves to nothing without asking: it means the
  /// document did not name one, which is different from naming one nobody
  /// supplies, and only the second is worth reporting.
  static TransformReplica? resolve(String slot) {
    if (slot.isEmpty) return null;
    return _resolver?.call(slot);
  }
}
