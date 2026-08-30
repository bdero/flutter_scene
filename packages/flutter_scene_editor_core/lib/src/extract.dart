/// Lifting a node subtree out of a scene as a document of its own.
///
/// This is what "make a reusable asset out of that" means underneath: a crate
/// in a level is a node, its children, the geometry and materials they point
/// at, and the skins and animations that drive them. Saving it as its own
/// `.fscene` means gathering all of that, because a prefab that references a
/// resource left behind in the level it came from is a prefab that loads as
/// half a crate anywhere else.
///
/// [captureSubtree] already lifts the nodes. What this adds is everything they
/// point at, followed transitively — a mesh names a geometry, which names the
/// payload holding its vertices — and an honest account of the references that
/// could not come along.
library;

import 'package:scene/scene.dart';

import 'clone.dart';

/// A subtree lifted out as a standalone document, and what did not survive.
class ExtractedPrefab {
  const ExtractedPrefab({
    required this.document,
    required this.droppedNodeReferences,
  });

  /// The subtree as a document of its own, with the subtree's root as its
  /// only root.
  final SceneDocument document;

  /// Node references that pointed outside the subtree and were cleared.
  ///
  /// A prefab cannot carry a reference to a node in the level it was made
  /// from: the level is not there when the prefab is loaded somewhere else.
  /// Clearing them keeps the prefab self-consistent, and naming them here is
  /// what lets a caller say which ones went rather than leaving somebody to
  /// find out from a thing that quietly stopped working.
  final List<String> droppedNodeReferences;

  /// Whether everything came across intact.
  bool get isComplete => droppedNodeReferences.isEmpty;
}

/// Lifts the subtree rooted at [rootId] out of [document] as its own document.
///
/// Ids are kept: they only have to be unique within the result, and keeping
/// them makes the extraction readable beside the scene it came from.
ExtractedPrefab extractPrefab(SceneDocument document, LocalId rootId) {
  final subtree = captureSubtree(document, rootId);
  final inside = subtree.nodes.keys.toSet();
  final dropped = <String>[];

  // Resources, skins, animations and payloads reachable from the subtree.
  final resources = <LocalId>{};
  final payloads = <LocalId>{};

  void collectValue(PropertyValue value, String where) {
    switch (value) {
      case ResourceRefValue(:final id):
        resources.add(id);
      case NodeRefValue(:final id):
        if (!inside.contains(id)) dropped.add(where);
      case ListValue(:final values):
        for (final entry in values) {
          collectValue(entry, where);
        }
      case MapValue(:final values):
        for (final entry in values.entries) {
          collectValue(entry.value, '$where.${entry.key}');
        }
      default:
        break;
    }
  }

  for (final node in subtree.nodes.values) {
    for (final component in node.components) {
      for (final entry in component.properties.entries) {
        collectValue(
          entry.value,
          '${node.name}/${component.type}.${entry.key}',
        );
      }
    }
  }

  // A resource can name another: a material names a texture, a geometry names
  // the payloads holding its vertices. Followed until nothing new turns up.
  final seen = <LocalId>{};
  final queue = List.of(resources);
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    if (!seen.add(id)) continue;
    final resource = document.resources[id];
    if (resource == null) continue;
    switch (resource) {
      case GeometryResource(:final vertices, :final indices):
        if (vertices != null) payloads.add(vertices);
        if (indices != null) payloads.add(indices);
      case TextureResource(:final payload):
        if (payload != null) payloads.add(payload);
      case MaterialResource(:final properties):
        for (final value in properties.values) {
          _collectResourceRefs(value, (ref) {
            resources.add(ref);
            queue.add(ref);
          });
        }
      default:
        break;
    }
  }

  // A skin comes along only when every joint it moves is inside: half a
  // skeleton deforms a mesh into a shape nobody authored.
  final skins = <SkinSpec>[];
  for (final node in subtree.nodes.values) {
    final skinId = node.skin;
    if (skinId == null) continue;
    final skin = document.skins[skinId];
    if (skin == null) continue;
    final complete =
        skin.joints.every(inside.contains) &&
        (skin.skeleton == null || inside.contains(skin.skeleton));
    if (!complete) {
      dropped.add('${node.name}/skin');
      continue;
    }
    skins.add(skin);
    payloads.add(skin.inverseBindMatrices);
  }
  final keptSkins = {for (final skin in skins) skin.id};

  // An animation comes along when every channel it drives targets a node
  // inside. One that half-targets the level would animate nothing.
  final animations = <AnimationSpec>[];
  for (final animation in document.animations.values) {
    if (animation.channels.isEmpty) continue;
    if (!animation.channels.every(
      (channel) => inside.contains(channel.target),
    )) {
      continue;
    }
    animations.add(animation);
    for (final channel in animation.channels) {
      payloads
        ..add(channel.timeline)
        ..add(channel.keyframes);
      // A cubic channel's tangents are payloads of their own; leaving them
      // out would extract a channel whose tangent ids point at nothing.
      final inTangents = channel.inTangents;
      final outTangents = channel.outTangents;
      if (inTangents != null) payloads.add(inTangents);
      if (outTangents != null) payloads.add(outTangents);
    }
  }

  final extracted = SceneDocument();
  for (final id in payloads) {
    final payload = document.payloads[id];
    if (payload != null) extracted.addPayload(payload);
  }
  for (final id in seen) {
    final resource = document.resources[id];
    if (resource != null) extracted.addResource(resource);
  }
  for (final skin in skins) {
    extracted.addSkin(skin);
  }
  for (final animation in animations) {
    extracted.addAnimation(animation);
  }

  for (final node in subtree.nodes.values) {
    extracted.addNode(
      _withoutOutsideReferences(node, inside, keptSkins),
      root: node.id == rootId,
    );
  }

  return ExtractedPrefab(document: extracted, droppedNodeReferences: dropped);
}

/// A copy of [node] with every reference that leaves the subtree cleared.
NodeSpec _withoutOutsideReferences(
  NodeSpec node,
  Set<LocalId> inside,
  Set<LocalId> keptSkins,
) => NodeSpec(
  id: node.id,
  name: node.name,
  transform: node.transform,
  children: [
    for (final child in node.children)
      if (inside.contains(child)) child,
  ],
  components: [
    for (final component in node.components)
      ComponentSpec(
        component.type,
        properties: {
          for (final entry in component.properties.entries)
            entry.key: _clearOutsideNodeRefs(entry.value, inside),
        },
      ),
  ],
  layers: node.layers,
  skin: keptSkins.contains(node.skin) ? node.skin : null,
  instance: node.instance,
  visible: node.visible,
);

/// [value] with node references outside [inside] replaced by nothing.
PropertyValue _clearOutsideNodeRefs(PropertyValue value, Set<LocalId> inside) =>
    switch (value) {
      NodeRefValue(:final id) when !inside.contains(id) => const StringValue(
        '',
      ),
      ListValue(:final values) => ListValue([
        for (final entry in values) _clearOutsideNodeRefs(entry, inside),
      ]),
      MapValue(:final values) => MapValue({
        for (final entry in values.entries)
          entry.key: _clearOutsideNodeRefs(entry.value, inside),
      }),
      _ => value,
    };

/// Calls [found] for every resource reference in [value], however nested.
void _collectResourceRefs(PropertyValue value, void Function(LocalId) found) {
  switch (value) {
    case ResourceRefValue(:final id):
      found(id);
    case ListValue(:final values):
      for (final entry in values) {
        _collectResourceRefs(entry, found);
      }
    case MapValue(:final values):
      for (final entry in values.values) {
        _collectResourceRefs(entry, found);
      }
    default:
      break;
  }
}
