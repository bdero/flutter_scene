import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/animation.dart' as engine;

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
import 'package:flutter_scene/src/skin.dart';

/// Applies [spec] to [node]'s local transform. A TRS spec keeps its
/// authored decomposition; recovering it from the composed matrix puts a
/// mirrored axis's negative scale on X, which breaks animation blending
/// on mirrored bones. Also used by scene hot reload.
void applyTransformSpec(Node node, TransformSpec spec) {
  switch (spec) {
    case TrsTransform(:final translation, :final rotation, :final scale):
      node.setLocalTransformTrs(
        engine.DecomposedTransform(
          translation: translation.clone(),
          rotation: rotation.clone(),
          scale: scale.clone(),
        ),
      );
    case MatrixTransform(:final matrix):
      node.localTransform = matrix.clone();
  }
}

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
      Node(name: spec.name)
        ..layers = spec.layers
        ..excludeFromWindingParity = spec.excludeFromWindingParity
        ..visible = spec.visible,
      spec.id,
    );
    applyTransformSpec(node, spec.transform);
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
/// children become the document's root nodes. Nodes realized from a document
/// keep their identity-tag ids, so a load/edit/save cycle is rename-proof and
/// diff-friendly; untagged (hand-built) nodes mint fresh ids. Skins, the
/// root's parsed animations, and lazy prefab placeholders serialize too; a
/// loaded lazy subtree serializes as its placeholder (the streamed content
/// belongs to the referenced prefab, not this document). Components are
/// serialized through [registry] (the built-ins by default); a component no
/// codec claims is skipped with a debug warning.
SceneDocument serializeScene(Node root, {FsceneComponentRegistry? registry}) {
  final reg = registry ?? defaultComponentRegistry();
  final document = SceneDocument();
  document.stage.handedness = root.localTransform.determinant() < 0
      ? Handedness.right
      : Handedness.left;
  final context = SerializeContext(document);

  // First pass: assign every node its id, reusing realize-time identity tags
  // where present (skipping duplicates from app-side clones). Newly assigned
  // ids are tagged back onto the nodes so follow-up passes (`serializeViews`
  // referencing camera nodes) and future saves see stable ids.
  final ids = <Node, LocalId>{};
  final used = <LocalId>{};
  void assign(Node node) {
    final tagged = nodeFsceneId(node);
    final id = tagged != null && used.add(tagged) ? tagged : document.newId();
    ids[node] = id;
    if (id != tagged) {
      used.add(id);
      tagNodeId(node, id);
    }
    for (final child in node.children) {
      assign(child);
    }
  }

  for (final child in root.children) {
    assign(child);
  }

  for (final child in root.children) {
    final spec = _serializeNode(child, document, reg, context, ids);
    document.addNode(spec, root: true);
  }
  _serializeAnimations(root, document, ids);
  return document;
}

NodeSpec _serializeNode(
  Node node,
  SceneDocument document,
  FsceneComponentRegistry registry,
  SerializeContext context,
  Map<Node, LocalId> ids,
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

  final lazyInstance = lazyInstanceOf(node);
  final trs = node.localTransformTrs;
  final spec = NodeSpec(
    id: ids[node]!,
    name: node.name,
    transform: trs != null
        ? TrsTransform(
            translation: trs.translation.clone(),
            rotation: trs.rotation.clone(),
            scale: trs.scale.clone(),
          )
        : MatrixTransform(node.localTransform.clone()),
    components: components,
    layers: node.layers,
    skin: _serializeSkin(node.skin, document, context, ids),
    instance: lazyInstance,
    excludeFromWindingParity: node.excludeFromWindingParity,
    visible: node.visible,
  );
  document.addNode(spec);

  // A loaded lazy subtree's children are the streamed prefab content; the
  // placeholder's instance reference stands in for them.
  if (lazyInstance == null) {
    for (final child in node.children) {
      final childSpec = _serializeNode(child, document, registry, context, ids);
      spec.children.add(childSpec.id);
    }
  }
  return spec;
}

LocalId? _serializeSkin(
  Skin? skin,
  SceneDocument document,
  SerializeContext context,
  Map<Node, LocalId> ids,
) {
  if (skin == null) return null;
  final cached = context.serializedResources[skin];
  if (cached != null) return cached;

  final matrices = Float32List(skin.inverseBindMatrices.length * 16);
  for (var i = 0; i < skin.inverseBindMatrices.length; i++) {
    matrices.setAll(i * 16, skin.inverseBindMatrices[i].storage);
  }
  final payload = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.matrices,
      length: matrices.lengthInBytes,
      bytes: matrices.buffer.asUint8List(),
    ),
  );
  final spec = document.addSkin(
    SkinSpec(
      document.newId(),
      // A joint outside the serialized tree (or a null joint) gets a fresh
      // dangling id, which realizes back to a null (identity) joint.
      joints: [
        for (final joint in skin.joints)
          (joint == null ? null : ids[joint]) ?? document.newId(),
      ],
      inverseBindMatrices: payload.id,
    ),
  );
  context.serializedResources[skin] = spec.id;
  return spec.id;
}

void _serializeAnimations(
  Node root,
  SceneDocument document,
  Map<Node, LocalId> ids,
) {
  for (final animation in root.parsedAnimations) {
    final channels = <AnimationChannelSpec>[];
    for (final channel in animation.channels) {
      final resolver = channel.resolver;
      final AnimationProperty property;
      final List<double> times;
      final Float32List keyframes;
      switch (resolver) {
        case engine.TranslationTimelineResolver():
          property = AnimationProperty.translation;
          times = resolver.times;
          keyframes = _packVec3(resolver.values);
        case engine.RotationTimelineResolver():
          property = AnimationProperty.rotation;
          times = resolver.times;
          keyframes = _packQuaternions(resolver.values);
        case engine.ScaleTimelineResolver():
          property = AnimationProperty.scale;
          times = resolver.times;
          keyframes = _packVec3(resolver.values);
        default:
          debugPrint(
            'fscene: animation "${animation.name}" channel with a custom '
            'resolver (${resolver.runtimeType}) is not serializable; skipped',
          );
          continue;
      }
      final nodeName = channel.bindTarget.nodeName;
      final target = nodeName == root.name
          ? root
          : root.getChildByName(nodeName);
      channels.add(
        AnimationChannelSpec(
          // An unresolved target keeps a dangling id; the name fallback
          // re-binds it at realization.
          target: (target != null ? ids[target] : null) ?? document.newId(),
          targetName: nodeName,
          property: property,
          timeline: _floatsPayload(document, Float32List.fromList(times)),
          keyframes: _floatsPayload(document, keyframes),
        ),
      );
    }
    if (channels.isEmpty) continue;
    document.addAnimation(
      AnimationSpec(document.newId(), name: animation.name, channels: channels),
    );
  }
}

Float32List _packVec3(List<Vector3> values) {
  final out = Float32List(values.length * 3);
  for (var i = 0; i < values.length; i++) {
    out.setAll(i * 3, values[i].storage);
  }
  return out;
}

Float32List _packQuaternions(List<Quaternion> values) {
  final out = Float32List(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setAll(i * 4, values[i].storage);
  }
  return out;
}

LocalId _floatsPayload(SceneDocument document, Float32List floats) => document
    .addPayload(
      PayloadSpec(
        document.newId(),
        encoding: PayloadEncoding.floats,
        length: floats.lengthInBytes,
        bytes: floats.buffer.asUint8List(
          floats.offsetInBytes,
          floats.lengthInBytes,
        ),
      ),
    )
    .id;
