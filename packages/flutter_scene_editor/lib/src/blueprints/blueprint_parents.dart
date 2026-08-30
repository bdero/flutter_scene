/// What a blueprint can extend, and how the picker lists it.
///
/// Unreal asks this before it makes a Blueprint Class, and the question is a
/// real one: the parent decides what the blueprint *is* — what it can be
/// placed as, what events its graphs receive, what a graph may assume exists.
///
/// The list is this engine's own rather than a copy of Unreal's. Actor and
/// Pawn mean nothing here; a node placed in a scene and a component added to
/// one mean everything. Below the common few, All Classes is the component
/// registry — every type this build knows, a project's own included — because
/// that genuinely is the set of things a blueprint could extend, and it grows
/// when the project does.
library;

import 'package:scene/schema.dart';

/// One thing a blueprint can extend.
class BlueprintParent {
  const BlueprintParent({
    required this.key,
    required this.label,
    required this.doc,
  });

  /// The stable key stored in the blueprint.
  final String key;

  /// What the picker calls it.
  final String label;

  /// One line on what extending it gets you.
  final String doc;
}

/// A blueprint that produces an object you place in a scene.
const BlueprintParent nodeParent = BlueprintParent(
  key: 'node',
  label: 'Node',
  doc: 'An object that can be placed in a scene or spawned into one.',
);

/// A blueprint that produces behaviour you add to a node.
const BlueprintParent componentParent = BlueprintParent(
  key: 'component',
  label: 'Component',
  doc: 'Reusable behaviour that can be added to any node.',
);

/// The parents offered first, above the full class list.
///
/// Short on purpose. A list of common choices that is not short is a second
/// full list, and the reason this one exists is that almost every blueprint is
/// one of the first two.
const List<BlueprintParent> commonBlueprintParents = [
  nodeParent,
  componentParent,
  BlueprintParent(
    key: 'visualScript',
    label: 'Visual Script Component',
    doc: 'A component that is itself a graph, added to a node like any other.',
  ),
  BlueprintParent(
    key: 'camera',
    label: 'Camera',
    doc: 'A node that renders the scene, for a shot driven by a graph.',
  ),
  BlueprintParent(
    key: 'rigidBody',
    label: 'Rigid Body',
    doc: 'A node the physics solver moves, for something a graph pushes.',
  ),
];

/// Every parent a blueprint could extend, given the registered
/// [componentTypes] and the schemas describing them.
///
/// Node and Component first, because they are what the two questions are, then
/// every component type sorted by name. A type already in the common list is
/// not repeated: the same class appearing twice in one picker reads as two
/// different classes.
List<BlueprintParent> allBlueprintParents(
  List<String> componentTypes, {
  ComponentSchema? Function(String type)? schemaFor,
}) {
  final seen = <String>{nodeParent.key, componentParent.key};
  final parents = <BlueprintParent>[nodeParent, componentParent];
  final sorted = List.of(componentTypes)..sort();
  for (final type in sorted) {
    if (!seen.add(type)) continue;
    final category = schemaFor?.call(type)?.category;
    parents.add(
      BlueprintParent(
        key: type,
        label: blueprintClassLabel(type),
        doc: category == null || category.isEmpty
            ? 'A $type component.'
            : '$category component.',
      ),
    );
  }
  return parents;
}

/// Whether [parent] matches the search [query].
///
/// Against the label and the key both, so "rigid body" and "rigidBody" find
/// the same thing: people type what they see and what they remember, and those
/// are different strings.
bool blueprintParentMatches(BlueprintParent parent, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return parent.label.toLowerCase().contains(needle) ||
      parent.key.toLowerCase().contains(needle);
}

/// The label to show for a stored parent key.
///
/// A key this build does not know still gets a readable name rather than a
/// blank: opening a teammate's blueprint without their components should say
/// what it extends, not imply it extends nothing.
String blueprintParentLabel(String key, List<BlueprintParent> known) =>
    known.where((parent) => parent.key == key).firstOrNull?.label ??
    blueprintClassLabel(key);

/// `rigidBody` as `Rigid Body`, which is how a class should read in a picker.
String blueprintClassLabel(String key) {
  if (key.isEmpty) return key;
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final upper = char.toUpperCase();
    if (i == 0) {
      buffer.write(upper);
      continue;
    }
    if (char == upper && char != char.toLowerCase()) buffer.write(' ');
    buffer.write(char);
  }
  return buffer.toString();
}
