import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/builtin_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/node.dart';

/// Returns a registry preloaded with the built-in component codecs.
FsceneComponentRegistry defaultComponentRegistry() {
  final registry = FsceneComponentRegistry();
  registerBuiltinComponentCodecs(registry);
  return registry;
}

/// Realizes [document] into a live [Node] graph.
///
/// Returns a synthesized root node that carries the handedness convention
/// from the document's stage (a `scale(1, 1, -1)` mirror with winding parity
/// excluded for a right-handed document, matching the model importers); the
/// document's own root nodes are its children. Components are built through
/// [registry] (the built-ins by default); a component whose type has no codec
/// is skipped with a debug warning.
///
/// Mesh and other resource-backed components are not realized here yet (they
/// need the geometry/texture payloads); that is the renderer-facing seam the
/// loader will fill.
// TODO(fscene): realize mesh components from geometry/material/texture
// resources once payloads are loaded (P5) and a resource realizer is wired.
Node realizeScene(SceneDocument document, {FsceneComponentRegistry? registry}) {
  final reg = registry ?? defaultComponentRegistry();
  final context = RealizeContext(document);

  // First pass: a bare node per spec (no children, no components yet).
  final nodes = <LocalId, Node>{};
  for (final spec in document.nodes.values) {
    nodes[spec.id] = Node(
      name: spec.name,
      localTransform: spec.transform.toMatrix4(),
    )..layers = spec.layers;
  }

  // Second pass: wire children and realize components now that every node
  // exists.
  for (final spec in document.nodes.values) {
    final node = nodes[spec.id]!;
    for (final childId in spec.children) {
      final child = nodes[childId];
      if (child == null) {
        debugPrint('fscene: node ${spec.id} references missing child $childId');
        continue;
      }
      node.add(child);
    }
    for (final componentSpec in spec.components) {
      final component = reg.realize(componentSpec, context);
      if (component == null) {
        debugPrint(
          'fscene: no codec for component "${componentSpec.type}"; skipping',
        );
        continue;
      }
      node.addComponent(component);
    }
  }

  final root = Node(
    name: 'root',
    localTransform: _handednessTransform(document),
  )..excludeFromWindingParity = true;
  for (final rootId in document.roots) {
    final node = nodes[rootId];
    if (node == null) {
      debugPrint('fscene: missing root node $rootId');
      continue;
    }
    root.add(node);
  }
  return root;
}

Matrix4 _handednessTransform(SceneDocument document) =>
    document.stage.handedness == Handedness.right
    ? Matrix4.diagonal3Values(1.0, 1.0, -1.0)
    : Matrix4.identity();

/// Serializes the live [Node] graph rooted at [root] into a new
/// [SceneDocument].
///
/// [root] is treated as the synthesized realization root (as returned by
/// [realizeScene]): its handedness is read back into the stage, and its
/// children become the document's root nodes. Components are serialized
/// through [registry] (the built-ins by default); a component no codec claims
/// (for example a mesh) is skipped with a debug warning.
SceneDocument serializeScene(Node root, {FsceneComponentRegistry? registry}) {
  final reg = registry ?? defaultComponentRegistry();
  final document = SceneDocument();
  document.stage.handedness = root.localTransform.determinant() < 0
      ? Handedness.right
      : Handedness.left;
  final context = SerializeContext(document);

  for (final child in root.children) {
    final spec = _serializeNode(child, document, reg, context);
    document.addNode(spec, root: true);
  }
  return document;
}

NodeSpec _serializeNode(
  Node node,
  SceneDocument document,
  FsceneComponentRegistry registry,
  SerializeContext context,
) {
  final components = <ComponentSpec>[];
  for (final component in node.getComponents<Component>()) {
    final spec = registry.serialize(component, context);
    if (spec == null) {
      debugPrint(
        'fscene: no codec for ${component.runtimeType}; not serialized',
      );
      continue;
    }
    components.add(spec);
  }

  final spec = NodeSpec(
    id: document.newId(),
    name: node.name,
    transform: MatrixTransform(node.localTransform.clone()),
    components: components,
    layers: node.layers,
  );
  document.addNode(spec);

  for (final child in node.children) {
    final childSpec = _serializeNode(child, document, registry, context);
    spec.children.add(childSpec.id);
  }
  return spec;
}
