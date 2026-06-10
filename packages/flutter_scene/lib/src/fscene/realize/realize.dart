import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/builtin_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/lazy_subtree.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/fscene/realize/skin_animation.dart';
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
/// Mesh components are realized from procedural or payload-backed geometry and
/// parameter materials; embedded `rgba8` textures realize here too. External
/// image assets, encoded image payloads, and `fmat` materials need
/// [realizeSceneAsync] (which preloads them); the synchronous path falls back
/// to placeholders. See [ResourceRealizer].
Node realizeScene(SceneDocument document, {FsceneComponentRegistry? registry}) {
  return _realizeWith(
    document,
    registry ?? defaultComponentRegistry(),
    ResourceRealizer(document),
  );
}

/// Realizes [document] into a live [Node] graph, first asynchronously loading
/// any external image assets, encoded image payloads, and `fmat` materials it
/// references (from [bundle], default `rootBundle`).
///
/// Use this (over [realizeScene]) when a document may reference such
/// resources; the `.fscene` / `.fsceneb` asset loaders do.
///
/// Pass [resources] to share realized GPU resources (geometry, materials,
/// textures) across multiple realizations of the same document, instancing
/// a scene cheaply. It must wrap [document] and already be preloaded; the
/// realizer is constructed and preloaded here only when [resources] is null.
Future<Node> realizeSceneAsync(
  SceneDocument document, {
  FsceneComponentRegistry? registry,
  AssetBundle? bundle,
  ResourceRealizer? resources,
}) async {
  assert(
    resources == null || identical(resources.document, document),
    'A shared ResourceRealizer must wrap the realized document',
  );
  var realizer = resources;
  if (realizer == null) {
    realizer = ResourceRealizer(document, bundle: bundle);
    await realizer.preload();
  }
  return _realizeWith(
    document,
    registry ?? defaultComponentRegistry(),
    realizer,
  );
}

Node _realizeWith(
  SceneDocument document,
  FsceneComponentRegistry reg,
  ResourceRealizer resources,
) {
  final context = RealizeContext(document, resources: resources);

  // First pass: a bare node per spec (no children, no components yet).
  final nodes = <LocalId, Node>{};
  for (final spec in document.nodes.values) {
    final node = tagNodeId(
      Node(name: spec.name, localTransform: spec.transform.toMatrix4())
        ..layers = spec.layers
        ..excludeFromWindingParity = spec.excludeFromWindingParity,
      spec.id,
    );
    final instance = spec.instance;
    if (instance != null) {
      if (instance.load == LoadPolicy.lazy) {
        // A streamed placeholder: its prefab content loads later via
        // loadSubtree.
        tagLazyInstance(node, instance);
      } else {
        debugPrint(
          'fscene: node ${spec.id} is an unexpanded eager prefab instance; '
          'run composeScene (or load via loadScene) before realizing',
        );
      }
    }
    nodes[spec.id] = node;
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

  // Bind skins and attach animations now that every node exists under the
  // root (animations resolve their targets by node name within the tree).
  realizeSkinsAndAnimations(document, root, nodes);

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
    excludeFromWindingParity: node.excludeFromWindingParity,
  );
  document.addNode(spec);

  for (final child in node.children) {
    final childSpec = _serializeNode(child, document, registry, context);
    spec.children.add(childSpec.id);
  }
  return spec;
}
