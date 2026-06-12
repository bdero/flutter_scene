import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// The in-memory `.fscene` document: a GPU-free, encoding-independent
/// description of a scene that the encoders serialize and the realizer turns
/// into a live `Node` graph.
///
/// A document owns one global [documentId] and id-keyed pools of [nodes],
/// [resources], [skins], [animations], and [payloads], plus the scene-wide
/// [stage] settings. Ids are minted from [allocator]; references between
/// entities are by [LocalId]. This type holds the data only; encoding (JSON
/// and packed binary), composition (prefab overrides), and realization live
/// in separate layers.
class SceneDocument {
  /// Creates an empty document. A new [documentId] and [allocator] (with a
  /// fresh session salt) are generated unless supplied.
  SceneDocument({
    DocumentId? documentId,
    IdAllocator? allocator,
    StageMetadata? stage,
  }) : documentId = documentId ?? DocumentId.generate(),
       allocator = allocator ?? IdAllocator(),
       stage = stage ?? StageMetadata();

  /// The coarse format version this document targets.
  int formatVersion = 1;

  /// The document's global id, minted once at creation.
  final DocumentId documentId;

  /// Features this document uses. Informational unless also in
  /// [featuresRequired].
  final Set<String> featuresUsed = {};

  /// Features a loader must support to load this document; missing one means
  /// it must refuse rather than load partially.
  final Set<String> featuresRequired = {};

  /// A human-readable producer string (for example the importer version).
  String? generator;

  /// Scene-wide, non-spatial render settings.
  StageMetadata stage;

  /// Mints ids for this editing session. Continuing a loaded document uses a
  /// new allocator with a fresh session salt.
  final IdAllocator allocator;

  /// Shared resources (geometry, materials, textures), keyed by id.
  final Map<LocalId, ResourceSpec> resources = {};

  /// Scene-graph nodes, keyed by id.
  final Map<LocalId, NodeSpec> nodes = {};

  /// The document's root node ids, in order.
  final List<LocalId> roots = [];

  /// Skins, keyed by id.
  final Map<LocalId, SkinSpec> skins = {};

  /// Animations, keyed by id.
  final Map<LocalId, AnimationSpec> animations = {};

  /// The binary chunk manifest, keyed by id.
  final Map<LocalId, PayloadSpec> payloads = {};

  /// Serialized render views, in order. Each binds a camera node to a
  /// target (a [RenderTextureResource] id, or null for the screen).
  final List<RenderViewSpec> views = [];

  /// Mints a fresh, document-unique [LocalId] from [allocator].
  LocalId newId() => allocator.mint();

  /// Registers [node] in the document, optionally as a [root], and returns
  /// it.
  NodeSpec addNode(NodeSpec node, {bool root = false}) {
    nodes[node.id] = node;
    if (root) roots.add(node.id);
    return node;
  }

  /// Creates a node with a fresh id, registers it (optionally as a [root]),
  /// and returns it.
  NodeSpec createNode({
    String name = '',
    TransformSpec? transform,
    List<ComponentSpec>? components,
    int layers = 1,
    bool root = false,
  }) {
    return addNode(
      NodeSpec(
        id: newId(),
        name: name,
        transform: transform,
        components: components,
        layers: layers,
      ),
      root: root,
    );
  }

  /// Registers a pre-built [resource] and returns it (preserving its type).
  T addResource<T extends ResourceSpec>(T resource) {
    resources[resource.id] = resource;
    return resource;
  }

  /// Registers a pre-built [skin] and returns it.
  SkinSpec addSkin(SkinSpec skin) {
    skins[skin.id] = skin;
    return skin;
  }

  /// Registers a pre-built [animation] and returns it.
  AnimationSpec addAnimation(AnimationSpec animation) {
    animations[animation.id] = animation;
    return animation;
  }

  /// Registers a pre-built [payload] and returns it.
  PayloadSpec addPayload(PayloadSpec payload) {
    payloads[payload.id] = payload;
    return payload;
  }

  /// The node with [id], or null.
  NodeSpec? node(LocalId id) => nodes[id];

  /// The resource with [id], or null.
  ResourceSpec? resource(LocalId id) => resources[id];

  /// The skin with [id], or null.
  SkinSpec? skin(LocalId id) => skins[id];

  /// The animation with [id], or null.
  AnimationSpec? animation(LocalId id) => animations[id];

  /// The payload with [id], or null.
  PayloadSpec? payload(LocalId id) => payloads[id];

  /// The root nodes, resolved from [roots] (skipping any dangling id).
  Iterable<NodeSpec> get rootNodes =>
      roots.map((id) => nodes[id]).whereType<NodeSpec>();

  /// The distinct session salts present across every id in the document.
  ///
  /// A new editing session for this document should allocate with these
  /// excluded so freshly minted ids cannot collide with existing ones.
  Set<int> usedSessions() {
    final sessions = <int>{};
    void add(LocalId id) => sessions.add(id.session);
    nodes.keys.forEach(add);
    resources.keys.forEach(add);
    skins.keys.forEach(add);
    animations.keys.forEach(add);
    payloads.keys.forEach(add);
    return sessions;
  }
}
