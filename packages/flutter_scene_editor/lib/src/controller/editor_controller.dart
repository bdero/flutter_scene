/// The bridge between the headless [EditorSession] and a live, renderable
/// [Scene].
///
/// The session owns the document (the source of truth) and the command,
/// history, selection, and query surfaces. This controller realizes that
/// document into a live `Node` graph for the viewport and keeps the two in
/// sync as edits land. It is a [ChangeNotifier], so the UI rebuilds when the
/// document, selection, or history changes.
///
/// Sync strategy. Cheap, frequent edits (transform, visibility, layers) are
/// reflected straight onto the matching live node by stable id, so a gizmo
/// drag never pays for re-realization. Environment-resource and material edits
/// take targeted fast paths too (the environment reapplies in place without a
/// re-bake; a material re-realizes just itself and swaps onto the live
/// primitives), so neither rebuilds the scene or re-bakes environments.
/// Structural edits (create, delete, reparent, component changes) re-realize
/// the document. The live node for a document id is found through the
/// realizer's own id tagging ([nodeFsceneId]).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart' hide NodeChange;
import 'package:flutter_scene/src/fmat/material_registry.dart'
    show fmatSourcePathOf;
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/placeholder_codec.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/fscene/realize/stage.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

import '../io/glb_import_options.dart';
import '../materials/fmat_library.dart';

/// Reflects an [EditorSession] into a live [Scene] and back.
class EditorController extends ChangeNotifier {
  EditorController._(
    this.session,
    this.scene,
    this.baseDirectory,
    this._componentRegistry,
  ) {
    // Component commands coerce and clamp property values against the
    // registered schemas (plus the universal properties every component
    // carries).
    session.componentSchemaLookup = (type) {
      final codec = _componentRegistry.codecFor(type);
      if (codec == null) return null;
      final schema = codec.schema;
      return ComponentSchema(
        schema.type,
        doc: schema.doc,
        icon: schema.icon,
        version: schema.version,
        formerTypes: schema.formerTypes,
        properties: [...schema.properties, ...universalComponentProperties],
      );
    };
  }

  /// The headless editing session (document, commands, history, selection).
  final EditorSession session;

  /// The live scene the viewport renders.
  final Scene scene;

  /// The directory the open scene was loaded from (or last saved to), used to
  /// resolve prefab instance references and project assets relative to the scene
  /// file. Null for a new, never-saved in-memory scene. Updated by
  /// [setBaseDirectory] after a Save As to a new location.
  String? baseDirectory;

  /// Updates [baseDirectory] after the scene is saved to a new location, so
  /// relative references and the asset browser resolve against it. Notifies
  /// listeners (the asset browser rescans).
  void setBaseDirectory(String directory) {
    if (baseDirectory == directory) return;
    baseDirectory = directory;
    notifyListeners();
  }

  /// Compiles and hot swaps `.fmat` materials referenced by the document.
  /// Sources on disk (resolved through [baseDirectory]) are compiled with the
  /// SDK's impellerc, loaded from bytes, watched, and refreshed in place on
  /// edit. The inspector reads its per-source error and parameter schema.
  late final EditorFmatLibrary fmatLibrary;

  final Map<LocalId, Node> _liveById = {};
  ResourceRealizer? _resourceRealizer;
  Node? _realizedRoot;
  // Maps every live node (including those realized from inside a prefab) to the
  // source-document node that owns it (itself for a source node, the enclosing
  // instance root for a prefab-internal node), so a viewport click on a prefab
  // selects the instance the editor can actually act on.
  final Map<Node, LocalId> _sourceIdByLive = {};

  // Cache of loaded prefab documents keyed by source.key, so the inspector
  // does not re-read the file on every rebuild.
  final Map<String, SceneDocument> _prefabCache = {};

  // The composed (prefab-expanded) document last realized, and where each
  // composed node came from. These back the outliner's display tree and the
  // in-place editing of prefab content (edits on a member become overrides on
  // its instance). Null/empty for a scene with no eager prefab instances.
  SceneDocument? _composed;
  Map<LocalId, PrefabMemberOrigin> _memberOrigins = {};

  /// The tree the outliner shows: the composed document when the scene has
  /// expanded prefab instances (so their internal nodes are visible), otherwise
  /// the source document. Plain nodes keep their source ids in both.
  SceneDocument get displayDocument => _composed ?? document;

  /// Whether [id] is a prefab-internal node (it exists only in the composed
  /// document, so its edits are recorded as overrides on its instance). The
  /// instance node itself is a real source node and is not a member.
  bool isPrefabMember(LocalId id) =>
      _memberOrigins.containsKey(id) && !document.nodes.containsKey(id);

  /// Where composed node [id] came from (its instance and prefab-local id), or
  /// null when [id] is not prefab content.
  PrefabMemberOrigin? memberOrigin(LocalId id) => _memberOrigins[id];

  /// Whether [id] can be edited as a source node or prefab member.
  bool isEditableNode(LocalId id) =>
      document.nodes.containsKey(id) || _memberOrigins.containsKey(id);

  /// The node to show for [id] in the display tree.
  NodeSpec? displayNode(LocalId id) => displayDocument.nodes[id];

  /// The root node ids of the display tree.
  List<LocalId> displayRoots() => displayDocument.roots;

  /// The child node ids of [id] in the display tree.
  List<LocalId> displayChildren(LocalId id) =>
      displayDocument.nodes[id]?.children ?? const [];

  /// The message of the most recent command failure, for the UI to surface.
  /// Set when [run] throws so a fire-and-forget edit (an inspector field, a
  /// menu action) does not fail silently. The shell shows it and resets it.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// Opens a controller over [session], realizing its document into a fresh
  /// scene. Async because realization may upload geometry and textures.
  /// [baseDirectory] resolves prefab references relative to the scene file.
  static Future<EditorController> open(
    EditorSession session, {
    String? baseDirectory,
    FsceneComponentRegistry? componentRegistry,
  }) async {
    // The global look lives in an environment resource the stage references.
    // Guarantee one exists (a studio default for an imported or legacy scene
    // that has none), so the look is always editable through the resource path.
    _ensureStageEnvironment(session.document);
    final controller = EditorController._(
      session,
      Scene(),
      baseDirectory,
      componentRegistry ?? defaultComponentRegistry(),
    );
    controller.fmatLibrary = EditorFmatLibrary(
      resolvePath: controller._resolveAssetPath,
      onReload: controller._onFmatReload,
      onError: (message) => controller.lastError.value = message,
      onStructuralChange: controller.recompose,
    );
    // Keep prefab-internal nodes selectable across source edits. Evaluated
    // per check; a tear-off would bind the nodes map captured before the
    // first compose and prune every prefab-member selection on each commit.
    session.selectionValidId = (id) =>
        controller.displayDocument.nodes.containsKey(id);
    await controller._realizeAll();
    session.selection.addListener(controller._onSelectionChanged);
    return controller;
  }

  // The live nodes currently carrying a highlight color, so the next sync can
  // clear them. Highlighting is transient view state (like selection), applied
  // straight to the live scene, not a document edit.
  final Set<Node> _highlighted = {};

  // Editor selection-highlight color (linear RGBA), a warm orange.
  static final Vector4 _highlightColor = Vector4(1.0, 0.55, 0.1, 1.0);

  void _onSelectionChanged() {
    _syncHighlights();
    notifyListeners();
  }

  // A hot-swapped `.fmat` shader repaints on its own (the shaders refreshed
  // in place), but a sky shader also drives baked sky lighting, so any bound
  // sky environment backed by an fmat re-bakes.
  void _onFmatReload() {
    void invalidate(SkyEnvironment? skyEnvironment) {
      if (skyEnvironment?.source is PreprocessedSky) {
        skyEnvironment!.invalidate();
      }
    }

    invalidate(scene.skyEnvironment);
    invalidate(scene.baseEnvironment?.skyEnvironment);
    for (final node in _liveById.values) {
      invalidate(
        node
            .getComponent<EnvironmentVolumeComponent>()
            ?.settings
            .skyEnvironment,
      );
    }
    notifyListeners();
  }

  /// Mirrors the selection onto the live scene as highlight colors, so the
  /// renderer draws a selection outline around the selected nodes.
  void _syncHighlights() {
    for (final node in _highlighted) {
      node.highlightColor = null;
    }
    _highlighted.clear();
    for (final id in selection.ids) {
      final live = _liveById[id];
      if (live != null) {
        live.highlightColor = _highlightColor;
        _highlighted.add(live);
      }
    }
  }

  // Ensures the stage references an environment resource, creating and linking
  // a studio default when it does not (an imported or legacy scene). Runs before
  // history starts, so it is part of the document's initial state.
  static void _ensureStageEnvironment(SceneDocument document) {
    final ref = document.stage.environmentRef;
    if (ref != null && document.resource(ref) is EnvironmentResource) return;
    final resource = document.addResource(
      EnvironmentResource(document.newId(), name: 'Environment'),
    );
    document.stage.environmentRef = resource.id;
  }

  /// Opens a controller over a new empty document.
  ///
  /// A new scene starts lit by a physical sky, with the sky driving the
  /// image-based lighting and casting sun shadows, a usable look-dev default
  /// rather than a black void. The skybox and the sky-lighting binding take
  /// their own sky-source instances (as the `setSkybox` command does).
  static Future<EditorController> empty({
    FsceneComponentRegistry? componentRegistry,
  }) {
    final document = SceneDocument();
    // The global look lives in an environment resource the stage references, so
    // it dedupes and shares the authoring path with volume environments.
    final environment = document.addResource(
      EnvironmentResource(
        document.newId(),
        name: 'Environment',
        skybox: SkyboxSpec(PhysicalSkySpec()),
        skyEnvironment: SkyEnvironmentSpec(
          PhysicalSkySpec(),
          sunLight: SunLightSpec(),
        ),
      ),
    );
    document.stage.environmentRef = environment.id;
    return open(EditorSession(document), componentRegistry: componentRegistry);
  }

  /// Opens a controller over a document loaded from `.fscene` [source].
  /// [baseDirectory] resolves any prefab references in the document.
  static Future<EditorController> fromFscene(
    String source, {
    String? baseDirectory,
    FsceneComponentRegistry? componentRegistry,
  }) => open(
    EditorSession.fromFscene(source),
    baseDirectory: baseDirectory,
    componentRegistry: componentRegistry,
  );

  /// Opens a controller over an already-imported [document] (from a `.glb` or
  /// multi-file `.gltf`), ready to edit and save as `.fscene`. [scale] and
  /// [upAxis] apply a non-destructive transform to the content (a group node
  /// wrapping the roots), leaving the rest of the document untouched.
  static Future<EditorController> fromImportedScene(
    SceneDocument document, {
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
    String? baseDirectory,
    FsceneComponentRegistry? componentRegistry,
  }) {
    final transform = _importTransform(scale, upAxis);
    if (transform != null) {
      wrapRootsUnderGroup(document, name: 'Imported', transform: transform);
    }
    return open(
      EditorSession(document),
      baseDirectory: baseDirectory,
      componentRegistry: componentRegistry,
    );
  }

  /// Opens a controller over a glTF binary ([glbBytes]) imported in memory.
  /// Set [compressTextures] to compress imported textures during the import.
  static Future<EditorController> fromGlb(
    Uint8List glbBytes, {
    bool compressTextures = false,
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
    String? baseDirectory,
    FsceneComponentRegistry? componentRegistry,
  }) => fromImportedScene(
    importGlbToSceneDocument(glbBytes, compressTextures: compressTextures),
    scale: scale,
    upAxis: upAxis,
    baseDirectory: baseDirectory,
    componentRegistry: componentRegistry,
  );

  /// The current selection.
  Selection get selection => session.selection;

  /// Read-only scene-graph queries.
  SceneQuery get query => session.query;

  /// The undo/redo history.
  EditHistory get history => session.history;

  /// The document being edited.
  SceneDocument get document => session.document;

  // The component registry, for reading component-type schemas (the editable
  // properties each type declares) and for realization, so codecs from
  // backend packages injected through [open] show up in the inspector and
  // realize in the viewport.
  final FsceneComponentRegistry _componentRegistry;

  /// The component type names that can be added to a node.
  List<String> componentTypes() => _componentRegistry.types.toList();

  /// The declared editable properties of component [type] (empty when the type
  /// declares none, or is unknown).
  List<ComponentPropertyDef> componentSchema(String type) =>
      _componentRegistry.codecFor(type)?.propertySchema ?? const [];

  /// The full portable schema of component [type], or null when unknown.
  ComponentSchema? componentSchemaFor(String type) =>
      _componentRegistry.codecFor(type)?.schema;

  // Claims-scan memo for [codecForLiveComponent]; entries are re-validated
  // with claims() before use, so a replaced registration cannot go stale.
  final Map<Type, ComponentCodec> _codecByRuntimeType = {};

  /// The codec whose type claims live [component], or null. Foreign
  /// components dispatch on their retained spec type; other components scan
  /// the registry in registration order (memoized by runtime type).
  ComponentCodec? codecForLiveComponent(Component component) {
    if (component is ForeignComponent) {
      return _componentRegistry.codecFor(component.spec.type);
    }
    final cached = _codecByRuntimeType[component.runtimeType];
    if (cached != null && cached.claims(component)) return cached;
    for (final type in _componentRegistry.types) {
      final codec = _componentRegistry.codecFor(type);
      if (codec != null && codec.claims(component)) {
        _codecByRuntimeType[component.runtimeType] = codec;
        return codec;
      }
    }
    return null;
  }

  /// The registered component schemas that declare gizmos, for the
  /// viewport's per-type visibility menu.
  List<ComponentSchema> gizmoComponentSchemas() => [
    for (final schema in _componentRegistry.schemas)
      if (schema.gizmo != null) schema,
  ];

  /// Where each foreign (schema-only) component type came from, keyed by
  /// type: `live` (fetched from the running app), `cache` (a prior fetch), or
  /// a package name. Types absent from this map are compiled in.
  final Map<String, String> foreignTypeProvenance = {};

  /// Absolute source file declaring each component type, from project source
  /// extraction; empty for compiled-in and package components.
  final Map<String, String> componentSourcePaths = {};

  /// Opens a source file in the user's editor. Wired by the host, which owns
  /// the editor-command setting.
  Future<void> Function(String path)? sourceFileOpener;

  /// Moves the camera to frame a node, reporting whether it had bounds to
  /// frame. Wired by the host, which owns the viewport camera.
  ///
  /// Lets a panel that is nowhere near the viewport — the outliner — ask for
  /// the same framing the F key does, rather than reaching for a camera it
  /// has no business holding.
  bool Function(LocalId id)? nodeFramer;

  /// Registers placeholder codecs for [schemas] whose types have no codec in
  /// this controller's registry, so documents carrying them realize as inert
  /// data bags, the inspector edits them from the schema, and Add Component
  /// offers them. Live-fetched schemas replace earlier placeholder versions
  /// of the same type ([provenance] `live` wins over `cache`).
  // Compiled-in codecs always win; live fetches and source extraction are
  // peers (whichever arrived last is freshest); package manifests beat the
  // cache; the cache never overwrites anything.
  static int _provenanceRank(String? provenance) => switch (provenance) {
    null => 3,
    'live' || 'source' => 2,
    'cache' => 0,
    _ => 1,
  };

  void adoptForeignSchemas(
    Iterable<ComponentSchema> schemas, {
    required String provenance,
  }) {
    var changed = false;
    final incomingRank = _provenanceRank(provenance);
    for (final schema in schemas) {
      final existing = _componentRegistry.codecFor(schema.type);
      final existingRank = existing == null
          ? -1
          : _provenanceRank(foreignTypeProvenance[schema.type]);
      if (incomingRank < existingRank) continue;
      if (existingRank == 3) continue;
      _componentRegistry.register(PlaceholderComponentCodec(schema));
      foreignTypeProvenance[schema.type] = provenance;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Forgets foreign component types whose declarations were deleted:
  /// unregisters their placeholder codecs so Add Component and the schema
  /// lookups stop knowing them. Documents still carrying one keep it as a
  /// lossless unknown-type placeholder. Compiled-in codecs are never
  /// touched.
  void retireForeignSchemas(Iterable<String> types) {
    var changed = false;
    for (final type in types) {
      if (!foreignTypeProvenance.containsKey(type)) continue;
      if (_componentRegistry.codecFor(type) is! PlaceholderComponentCodec) {
        continue;
      }
      _componentRegistry.unregister(type);
      foreignTypeProvenance.remove(type);
      componentSourcePaths.remove(type);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// The live node realized from document node [id], or null.
  Node? liveNode(LocalId id) => _liveById[id];

  /// The root the document was realized under, or null before the first
  /// realize.
  ///
  /// The scene's parsed animations hang off this node, so it is where a clip
  /// is instantiated and bound. Panels driving playback read it; nothing
  /// should mutate the graph through it, since the controller owns realizing
  /// and re-realizing it.
  Node? get realizedRoot => _realizedRoot;

  /// A counter bumped whenever the document is re-realized, so a panel
  /// holding something derived from the live graph (an animation clip bound
  /// to [realizedRoot], say) can tell its binding is stale.
  int get realizeEpoch => _realizeEpoch;
  int _realizeEpoch = 0;

  /// The live material on [id]'s first mesh primitive (the material a preview
  /// should show), or null when the node has no realized mesh.
  Material? liveMeshMaterial(LocalId id) {
    final primitives = _liveById[id]?.mesh?.primitives;
    return primitives == null || primitives.isEmpty
        ? null
        : primitives.first.material;
  }

  /// The source-document node id that owns [liveNode] (the node itself, or the
  /// enclosing prefab instance root for a node realized from inside a prefab),
  /// or null. Used to turn a viewport raycast hit into a selectable node.
  LocalId? sourceIdForLiveNode(Node liveNode) => _sourceIdByLive[liveNode];

  /// Loads and caches the prefab document referenced by [source].
  ///
  /// Resolves [source.key] relative to [baseDirectory] (or treats it as
  /// absolute when it is an absolute file path). Linked `.fscene`, `.fsceneb`,
  /// `.glb`, and `.gltf` files are supported. Results are cached keyed by
  /// [source.key] so repeated calls from the inspector rebuild cheaply. Throws
  /// a [StateError] when [baseDirectory] is null and the path is relative, and
  /// an [IOException] when the file cannot be read.
  Future<SceneDocument> loadPrefabDocument(AssetRef source) async {
    final cached = _prefabCache[source.key];
    if (cached != null) return cached;
    final doc = await _loadPrefab(source);
    _prefabCache[source.key] = doc;
    return doc;
  }

  /// Removes the cached prefab document for [key], forcing a fresh read on
  /// the next [loadPrefabDocument] call. Call this after applying overrides
  /// back to the source file so the inspector reflects the updated content.
  void clearPrefabCache(String key) => _prefabCache.remove(key);

  /// Resolves a scene asset key to an absolute local path when possible.
  String? resolveAssetPath(String key) => _resolveFilePath(key, baseDirectory);

  /// Runs the command named [name] with [params], reflects the resulting
  /// transaction onto the live scene, and notifies listeners. Returns the
  /// committed transaction (its records carry the ids of anything created, so
  /// a multi-step action can chain on them). Surfaces a [CommandException]
  /// (invalid params) to the caller for the UI to show.
  Future<Transaction> run(
    String name, [
    Map<String, Object?> params = const {},
  ]) async {
    try {
      final transaction = session.run(name, params);
      await _reflect(transaction);
      notifyListeners();
      return transaction;
    } catch (error) {
      // Surface the failure (a fire-and-forget caller would otherwise swallow
      // it) and rethrow so awaiting callers can still react.
      lastError.value = '$name, $error';
      rethrow;
    }
  }

  /// Grafts an already-imported [source] document (from a `.glb` or `.gltf`)
  /// into the current scene as a new subtree under [parentId] (or the scene
  /// roots when null or missing), as one undoable edit. The imported root
  /// nodes become the selection. [scale] and [upAxis] apply a non-destructive
  /// import transform on a wrapping group node.
  Future<void> importSceneIntoScene(
    SceneDocument source, {
    LocalId? parentId,
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
  }) async {
    final transform = _importTransform(scale, upAxis);
    if (transform != null) {
      wrapRootsUnderGroup(source, name: 'Imported', transform: transform);
    }
    final graft = graftDocumentRecords(document, source, parentId: parentId);
    if (graft.records.isEmpty) return;
    // An import is produced out of band, so it lands as one external
    // transaction on the history rather than through a registry command.
    session.commitExternal(
      Transaction(name: 'Import glTF', records: graft.records),
    );
    await _realizeAll();
    if (graft.rootIds.isNotEmpty) {
      selection.selectOnly(graft.rootIds.first);
      for (final id in graft.rootIds.skip(1)) {
        selection.add(id);
      }
    }
    notifyListeners();
  }

  /// Re-realizes the scene from the current document, picking up external
  /// changes such as a prefab/imported asset rewritten on disk (call
  /// [clearPrefabCache] first so the new bytes are read). Not an undoable edit;
  /// the document itself is unchanged.
  Future<void> recompose() async {
    await _realizeAll();
    notifyListeners();
  }

  /// Imports a glTF binary ([glbBytes]) into the current scene as a new
  /// subtree. See [importSceneIntoScene].
  Future<void> importGlbIntoScene(
    Uint8List glbBytes, {
    LocalId? parentId,
    bool compressTextures = false,
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
  }) => importSceneIntoScene(
    importGlbToSceneDocument(glbBytes, compressTextures: compressTextures),
    parentId: parentId,
    scale: scale,
    upAxis: upAxis,
  );

  // --- clipboard and selection-driven edits ------------------------------

  // Detached, deep-copied subtrees captured by the last copy. Held here (not on
  // the session) because the clipboard is transient editor state, not part of
  // the document or its history.
  List<NodeSubtree> _clipboard = [];

  /// Whether there is clipboard content to paste.
  bool get canPaste => _clipboard.isNotEmpty;

  /// The selected nodes with no selected ancestor, in document order. Copy,
  /// duplicate, and delete act on these so a parent and its descendant are not
  /// processed twice.
  List<LocalId> topLevelSelection() {
    final selected = selection.ids;
    bool hasSelectedAncestor(LocalId id) {
      var parent = query.parentOf(id);
      while (parent != null) {
        if (selected.contains(parent)) return true;
        parent = query.parentOf(parent);
      }
      return false;
    }

    final tops = {
      for (final id in selected)
        if (!hasSelectedAncestor(id)) id,
    };
    // Document order (roots first, depth-first) for stable, predictable output.
    final ordered = <LocalId>[];
    void visit(LocalId id) {
      if (tops.contains(id)) ordered.add(id);
      for (final child in query.childrenOf(id)) {
        visit(child.id);
      }
    }

    for (final root in query.roots) {
      visit(root.id);
    }
    return ordered;
  }

  /// Captures the top-level selected subtrees into the clipboard. Does nothing
  /// when the selection is empty.
  void copySelection() {
    final tops = topLevelSelection();
    if (tops.isEmpty) return;
    _clipboard = [for (final id in tops) captureSubtree(document, id)];
  }

  /// Duplicates the top-level selected subtrees in place, selecting the clones.
  Future<void> duplicateSelection() async {
    final tops = topLevelSelection();
    if (tops.isEmpty) return;
    final tx = await run('duplicateNodes', {
      'nodeIds': [for (final id in tops) id.toToken()],
    });
    final created = attachedIds(tx);
    if (created.isNotEmpty) selection.set(created);
  }

  /// Pastes the clipboard subtrees under the primary selection (the root list
  /// when nothing is selected), selecting the pasted roots. Each paste mints
  /// fresh ids, so pasting repeatedly yields distinct copies.
  Future<void> paste() async {
    if (_clipboard.isEmpty) return;
    final parent = selection.primary;
    final tx = await run('pasteNodes', {
      if (parent != null) 'parentId': parent.toToken(),
      'subtrees': _clipboard,
    });
    final created = attachedIds(tx);
    if (created.isNotEmpty) selection.set(created);
  }

  /// Deletes the selection. Prefab-internal nodes are removed through their
  /// instance's delta (removedNodes); plain and attached nodes are deleted
  /// normally in one undoable step.
  Future<void> deleteSelection() async {
    for (final id in selection.ids.where(isPrefabMember).toList()) {
      final origin = memberOrigin(id)!;
      await run('removePrefabMember', {
        'nodeId': origin.instanceId.toToken(),
        'target': origin.prefabLocalId.toToken(),
      });
    }
    // topLevelSelection walks the source tree, so it returns only plain and
    // attached nodes (prefab members are not source nodes).
    final plain = topLevelSelection();
    if (plain.isNotEmpty) {
      await run('deleteNodes', {
        'nodeIds': [for (final id in plain) id.toToken()],
      });
    }
  }

  // The prefab instance whose attachments include [id], or null when [id] is
  // not an attached node.
  LocalId? _attachmentOwner(LocalId id) {
    for (final entry in document.nodes.entries) {
      final instance = entry.value.instance;
      if (instance != null && instance.attachments.any((a) => a.node == id)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _detachIfAttached(LocalId id) async {
    final owner = _attachmentOwner(id);
    if (owner != null) {
      await run('detachFromPrefab', {
        'nodeId': owner.toToken(),
        'node': id.toToken(),
      });
    }
  }

  /// Handles a drop of [dragged] onto [target] in the outliner: attaches under
  /// [target] when it is a prefab-internal node, otherwise reparents into it.
  Future<void> dropOnNode(LocalId dragged, LocalId target) async {
    if (dragged == target) return;
    await _detachIfAttached(dragged);
    if (isPrefabMember(target)) {
      final origin = memberOrigin(target)!;
      await run('attachExistingToPrefabMember', {
        'nodeId': origin.instanceId.toToken(),
        'target': origin.prefabLocalId.toToken(),
        'node': dragged.toToken(),
      });
    } else {
      await run('reparentNode', {
        'nodeId': dragged.toToken(),
        'newParentId': target.toToken(),
      });
    }
  }

  /// Reparents [dragged] into [parent] (the root list when null) at [index],
  /// dropping any prefab attachment so it does not snap back into the prefab.
  Future<void> reparentToContainer(
    LocalId dragged,
    LocalId? parent,
    int index,
  ) async {
    await _detachIfAttached(dragged);
    await run('reparentNode', {
      'nodeId': dragged.toToken(),
      if (parent != null) 'newParentId': parent.toToken(),
      'index': index,
    });
  }

  /// Adds a new node attached under [target], which is a prefab-internal node
  /// (the new node grafts under it) or a prefab instance node (grafts at its
  /// root). Selects the new node, which edits and deletes like any other.
  Future<void> attachNodeUnder(LocalId target) async {
    final origin = memberOrigin(target);
    final LocalId instanceId;
    final LocalId? parent;
    if (origin != null) {
      instanceId = origin.instanceId;
      parent = origin.prefabLocalId;
    } else if (document.nodes[target]?.instance != null) {
      instanceId = target;
      parent = null;
    } else {
      return;
    }
    final tx = await run('attachToPrefabMember', {
      'nodeId': instanceId.toToken(),
      if (parent != null) 'parent': parent.toToken(),
    });
    final created = attachedIds(tx);
    if (created.isNotEmpty) selection.set(created);
  }

  /// The node ids newly added to a container by [transaction] (the difference
  /// of each children/roots record's new list over its old list), in order.
  /// These are the roots an add, duplicate, or paste created.
  static List<LocalId> attachedIds(Transaction transaction) {
    final out = <LocalId>[];
    for (final record in transaction.records) {
      if (record.slot != ChangeSlot.children &&
          record.slot != ChangeSlot.roots) {
        continue;
      }
      final old = (record.oldValue as IdListChange).value.toSet();
      for (final id in (record.newValue as IdListChange).value) {
        if (!old.contains(id)) out.add(id);
      }
    }
    return out;
  }

  // --- prefab-aware edit routing -----------------------------------------

  // An edit to a prefab-internal node has no source node to mutate, so it is
  // recorded as an override on the enclosing instance. A plain node edits
  // through its normal command. Component edits also route to an override for
  // the instance (merged-root) node, whose components came from the prefab.

  /// Sets node [id]'s name (an override when [id] is prefab content).
  Future<void> setNodeNameRouted(LocalId id, String name) {
    if (!isEditableNode(id)) return Future.value();
    if (isPrefabMember(id)) {
      return _override(memberOrigin(id)!, 'name', name);
    }
    return run('setNodeName', {'nodeId': id.toToken(), 'name': name});
  }

  /// Sets node [id]'s visibility (an override when [id] is prefab content).
  Future<void> setNodeVisibleRouted(LocalId id, bool visible) {
    if (!isEditableNode(id)) return Future.value();
    if (isPrefabMember(id)) {
      return _override(memberOrigin(id)!, 'visible', visible);
    }
    return run('setNodeVisible', {'nodeId': id.toToken(), 'visible': visible});
  }

  /// Sets node [id]'s transform (overrides per supplied component when [id] is
  /// prefab content).
  Future<void> setNodeTransformRouted(
    LocalId id, {
    Map<String, Object>? translation,
    Map<String, Object>? scale,
    Object? rotation,
  }) async {
    if (!isEditableNode(id)) return;
    if (isPrefabMember(id)) {
      final origin = memberOrigin(id)!;
      if (translation != null) {
        await _override(origin, 'transform.trs.t', translation);
      }
      if (scale != null) await _override(origin, 'transform.trs.s', scale);
      if (rotation != null) {
        // The override value is coerced; a quaternion is tagged so it is not
        // mistaken for a vec4.
        await _override(origin, 'transform.trs.r', {r'$quat': rotation});
      }
      return;
    }
    await run('setNodeTransform', {
      'nodeId': id.toToken(),
      if (translation != null) 'translation': translation,
      if (scale != null) 'scale': scale,
      if (rotation != null) 'rotation': rotation,
    });
  }

  /// Sets one property of component [type] on node [id]. Routes to an override
  /// when the component belongs to a prefab (an internal node, or the merged
  /// instance node whose components came from the prefab root).
  Future<void> setComponentPropertyRouted(
    LocalId id,
    String type,
    String key,
    Object value,
  ) {
    if (!isEditableNode(id)) return Future.value();
    final origin = memberOrigin(id);
    if (origin != null) {
      return _override(origin, 'components.$type.$key', value);
    }
    return run('setComponentProperties', {
      'nodeId': id.toToken(),
      'componentType': type,
      'properties': {key: value},
    });
  }

  Future<void> _override(
    PrefabMemberOrigin origin,
    String path,
    Object value,
  ) => run('setPrefabOverride', {
    'nodeId': origin.instanceId.toToken(),
    'target': origin.prefabLocalId.toToken(),
    'path': path,
    'value': value,
  });

  /// Adds component [type] to node [id], routed: a source-document node gets
  /// a plain component; a prefab member records it on the enclosing instance.
  Future<void> addComponentRouted(LocalId id, String type) {
    if (document.nodes.containsKey(id)) {
      return run('addComponent', {
        'nodeId': id.toToken(),
        'componentType': type,
      });
    }
    final origin = memberOrigin(id);
    if (origin == null) return Future.value();
    return run('addPrefabMemberComponent', {
      'nodeId': origin.instanceId.toToken(),
      'memberId': origin.prefabLocalId.toToken(),
      'componentType': type,
    });
  }

  /// Removes component [type] from node [id], routed like
  /// [addComponentRouted]. On a member this removes only an instance-added
  /// component; prefab-authored components are not removable here.
  Future<void> removeComponentRouted(LocalId id, String type) {
    if (document.nodes.containsKey(id)) {
      return run('removeComponent', {
        'nodeId': id.toToken(),
        'componentType': type,
      });
    }
    final origin = memberOrigin(id);
    if (origin == null) return Future.value();
    return run('removePrefabMemberComponent', {
      'nodeId': origin.instanceId.toToken(),
      'memberId': origin.prefabLocalId.toToken(),
      'componentType': type,
    });
  }

  /// The component types the enclosing instance has added to member [id]
  /// (empty for source-document nodes), the set removable in the inspector.
  Set<String> memberAddedComponentTypes(LocalId id) {
    final origin = memberOrigin(id);
    if (origin == null) return const {};
    final instance = document.nodes[origin.instanceId]?.instance;
    if (instance == null) return const {};
    return {
      for (final mc in instance.memberComponents)
        if (mc.member == origin.prefabLocalId) mc.component.type,
    };
  }

  /// Undoes the last edit, reflecting it onto the live scene.
  Future<void> undo() async {
    if (!history.canUndo) return;
    final transaction = history.transactions[history.cursor - 1];
    session.undo();
    await _reflect(transaction);
    notifyListeners();
  }

  /// Redoes the next edit, reflecting it onto the live scene.
  Future<void> redo() async {
    if (!history.canRedo) return;
    final transaction = history.transactions[history.cursor];
    session.redo();
    await _reflect(transaction);
    notifyListeners();
  }

  /// Bumped on every live transform preview, so every open viewport repaints
  /// its overlays (gizmos, guides) while a drag in one of them is still in
  /// progress. Cheaper than [notifyListeners], which would rebuild the whole
  /// panel set per mouse move.
  final ValueNotifier<int> previewEpoch = ValueNotifier<int>(0);

  /// Previews a transform on the live node for [id] without touching the
  /// document or the history. Used during a gizmo drag; the final value is
  /// committed once with `setNodeTransform` on release.
  void previewLocalTransform(LocalId id, Matrix4 localTransform) {
    _liveById[id]?.localTransform = localTransform;
    previewEpoch.value++;
  }

  /// Live-previews a material factor on node [id]'s realized mesh without
  /// touching the document or history, so a slider/color drag updates the
  /// viewport continuously. Commit the final value once with
  /// `setMaterialProperties` on release. [key] is a material property name
  /// (`baseColor`/`emissive`/`metallic`/`roughness`); [raw] is a double or an
  /// `{r,g,b,a}` map.
  void previewMaterialProperty(LocalId id, String key, Object raw) {
    final mesh = _liveById[id]?.mesh;
    if (mesh == null) return;
    final color = _colorVec(raw);
    for (final primitive in mesh.primitives) {
      final material = primitive.material;
      // An fmat material previews through its typed parameters, keyed by the
      // sidecar-declared parameter name.
      if (material is PreprocessedMaterial) {
        _previewFmatParameter(material, key, raw, color);
        continue;
      }
      switch (key) {
        case 'baseColor' when color != null:
          if (material is PhysicallyBasedMaterial) {
            material.baseColorFactor = color;
          } else if (material is UnlitMaterial) {
            material.baseColorFactor = color;
          }
        case 'emissive' when color != null:
          if (material is PhysicallyBasedMaterial) {
            material.emissiveFactor = color;
          }
        case 'emissiveStrength' when raw is num:
          if (material is PhysicallyBasedMaterial) {
            material.emissiveStrength = raw.toDouble();
          }
        case 'metallic' when raw is num:
          if (material is PhysicallyBasedMaterial) {
            material.metallicFactor = raw.toDouble();
          }
        case 'roughness' when raw is num:
          if (material is PhysicallyBasedMaterial) {
            material.roughnessFactor = raw.toDouble();
          }
      }
    }
    notifyListeners();
  }

  /// The effective (default-filled) value of material property [key] on node
  /// [id]'s realized mesh material, or null when not applicable/available.
  ///
  /// Inspector fields read this so a slider or color always shows the value
  /// the engine actually uses. A material resource stores only explicit
  /// overrides, so an unset factor (metallic, roughness, ...) is absent from
  /// the document; reading the realized material gives its real default
  /// instead of a UI-guessed one. Returns a `double` for a factor or an
  /// `{r,g,b,a}` map for a color.
  Object? effectiveMaterialValue(LocalId id, String key) {
    final mesh = _liveById[id]?.mesh;
    if (mesh == null || mesh.primitives.isEmpty) return null;
    final material = mesh.primitives.first.material;
    Map<String, double> rgba(Vector4 v) => {
      'r': v.r,
      'g': v.g,
      'b': v.b,
      'a': v.a,
    };
    if (material is PhysicallyBasedMaterial) {
      return switch (key) {
        'metallic' => material.metallicFactor,
        'roughness' => material.roughnessFactor,
        'alphaCutoff' => material.alphaCutoff,
        'baseColor' => rgba(material.baseColorFactor),
        'emissive' => rgba(material.emissiveFactor),
        'emissiveStrength' => material.emissiveStrength,
        _ => null,
      };
    }
    if (material is UnlitMaterial && key == 'baseColor') {
      return rgba(material.baseColorFactor);
    }
    return null;
  }

  /// Live-previews one look property of the stage's global environment
  /// resource during a slider drag (effects included), without touching the
  /// document or history; commit with `setEnvironmentProperties` on release.
  /// A non-global environment (a volume's) is ignored, its preview path
  /// would wrongly restyle the whole scene.
  void previewEnvironmentProperty(LocalId id, String key, Object value) {
    if (document.stage.environmentRef != id) return;
    final resource = document.resource(id);
    if (resource is! EnvironmentResource) return;
    _reapplyGlobalEnvironmentInPlace(
      environmentResourceWithProperties(resource, {key: value}),
    );
  }

  /// Live-previews one sun-light property of the stage's global environment
  /// during a slider drag, without touching the document or history; commit
  /// with `setEnvironmentSunLightProperties` on release. Ignores non-global
  /// environments and ones without an analytic sun.
  void previewEnvironmentSunProperty(LocalId id, String key, Object value) {
    if (document.stage.environmentRef != id) return;
    final resource = document.resource(id);
    if (resource is! EnvironmentResource) return;
    final preview = environmentResourceWithSunProperties(resource, {
      key: value,
    });
    if (preview == null) return;
    _reapplyGlobalEnvironmentInPlace(preview);
  }

  /// Live-previews scene-wide settings on the live scene without touching the
  /// document or history (for stage slider drags). Commit with
  /// `setStageProperties` on release.
  void previewStage({double? exposure, double? environmentIntensity}) {
    final settings = _previewSettings();
    if (settings != null) {
      // With volume components active, the per-frame blend recomputes the live
      // fields, so preview must write the holder the blend reads from.
      if (exposure != null) settings.exposure = exposure;
      if (environmentIntensity != null) {
        settings.environmentIntensity = environmentIntensity;
      }
    } else {
      if (exposure != null) scene.exposure = exposure;
      if (environmentIntensity != null) {
        scene.environmentIntensity = environmentIntensity;
      }
    }
    notifyListeners();
  }

  // The live environment-volume component on the node, if any.
  EnvironmentVolumeComponent? _liveVolume(LocalId nodeId) =>
      _liveById[nodeId]?.getComponent<EnvironmentVolumeComponent>();

  /// Live-previews an environment-volume component's look (the node carrying
  /// the component) by mutating its live settings, so a slider drag shows in
  /// the blend immediately. Commit with `setEnvironment*` on release.
  void previewVolumeStage(
    LocalId nodeId, {
    double? exposure,
    double? environmentIntensity,
  }) {
    final settings = _liveVolume(nodeId)?.settings;
    if (settings == null) return;
    if (exposure != null) settings.exposure = exposure;
    if (environmentIntensity != null) {
      settings.environmentIntensity = environmentIntensity;
    }
    notifyListeners();
  }

  /// Live-previews a procedural-sky parameter on an environment-volume
  /// component's look. See [previewSkyParameter].
  void previewVolumeSkyParameter(LocalId nodeId, String key, Object raw) {
    final settings = _liveVolume(nodeId)?.settings;
    if (settings == null) return;
    if (key == 'intensity' && raw is num) {
      settings.skybox?.intensity = raw.toDouble();
      notifyListeners();
      return;
    }
    _applySkyParameter(settings.skybox?.source, key, raw);
    final skyEnvironment = settings.skyEnvironment;
    if (skyEnvironment != null) {
      _applySkyParameter(skyEnvironment.source, key, raw);
      skyEnvironment.invalidate();
    }
    notifyListeners();
  }

  // The EnvironmentSettings a global preview writes: the blend base when any
  // volume component is active (the per-frame blend reads it), or null when the
  // live scene fields are authoritative (no volume blending).
  EnvironmentSettings? _previewSettings() {
    final blendActive =
        scene.environmentVolumes.isNotEmpty ||
        scene.renderScene.environmentVolumeComponents.isNotEmpty;
    return blendActive ? scene.baseEnvironment : null;
  }

  /// Live-previews a procedural-sky parameter on the live scene without
  /// touching the document or history (for sky slider/color drags). Aims or
  /// recolors the visible skybox source so the background updates immediately,
  /// and, when the scene is lit by the sky, mirrors the change onto the
  /// sky-lighting source and re-bakes it so reflections and diffuse lighting
  /// follow. [key] is a sky parameter name (`sunDirection`, `energy`,
  /// `turbidity`, color names, etc.); [raw] is a [Vector3] for a
  /// direction/color or a [num] for a scalar. Commit with `setSkyParameters`
  /// on release.
  void previewSkyParameter(String key, Object raw) {
    final settings = _previewSettings();
    final skybox = settings != null ? settings.skybox : scene.skybox;
    final skyEnvironment = settings != null
        ? settings.skyEnvironment
        : scene.skyEnvironment;
    // Intensity scales the visible skybox (it lives on the Skybox, not the
    // source), so handle it directly; it does not affect sky lighting.
    if (key == 'intensity' && raw is num) {
      skybox?.intensity = raw.toDouble();
      notifyListeners();
      return;
    }
    _applySkyParameter(skybox?.source, key, raw);
    if (skyEnvironment != null) {
      _applySkyParameter(skyEnvironment.source, key, raw);
      // The editor binds sky lighting with the manual refresh policy, so the
      // lighting only re-bakes when the binding is invalidated. The bake is
      // time-sliced, so invalidating every drag tick never spikes a frame.
      skyEnvironment.invalidate();
    }
    notifyListeners();
  }

  static void _applySkyParameter(SkySource? source, String key, Object raw) {
    switch (source) {
      case GradientSkySource g:
        switch (key) {
          case 'sunDirection' when raw is Vector3:
            g.sunDirection.setFrom(raw);
          case 'sunColor' when raw is Vector3:
            g.sunColor.setFrom(raw);
          case 'zenithColor' when raw is Vector3:
            g.zenithColor.setFrom(raw);
          case 'horizonColor' when raw is Vector3:
            g.horizonColor.setFrom(raw);
          case 'groundColor' when raw is Vector3:
            g.groundColor.setFrom(raw);
          case 'sunSharpness' when raw is num:
            g.sunSharpness = raw.toDouble();
        }
      case PhysicalSkySource p:
        switch (key) {
          case 'sunDirection' when raw is Vector3:
            p.sunDirection.setFrom(raw);
          case 'sunAngularRadius' when raw is num:
            p.sunAngularRadius = raw.toDouble();
          case 'rayleighCoefficient' when raw is num:
            p.rayleighCoefficient = raw.toDouble();
          case 'rayleighColor' when raw is Vector3:
            p.rayleighColor.setFrom(raw);
          case 'mieCoefficient' when raw is num:
            p.mieCoefficient = raw.toDouble();
          case 'mieEccentricity' when raw is num:
            p.mieEccentricity = raw.toDouble();
          case 'mieColor' when raw is Vector3:
            p.mieColor.setFrom(raw);
          case 'turbidity' when raw is num:
            p.turbidity = raw.toDouble();
          case 'groundColor' when raw is Vector3:
            p.groundColor.setFrom(raw);
          case 'energy' when raw is num:
            p.energy = raw.toDouble();
        }
      case EnvironmentSkySource e:
        if (key == 'blurriness' && raw is num) {
          e.blurriness = raw.toDouble();
        }
    }
  }

  static void _previewFmatParameter(
    PreprocessedMaterial material,
    String key,
    Object raw,
    Vector4? color,
  ) {
    try {
      if (color != null) {
        material.parameters.setColor(
          key,
          ui.Color.from(
            alpha: color.a,
            red: color.r,
            green: color.g,
            blue: color.b,
          ),
        );
      } else if (raw is num) {
        material.parameters[key] = raw;
      }
    } catch (_) {
      // An unknown or mistyped parameter is a benign preview no-op; the
      // commit path reports real failures.
    }
  }

  static Vector4? _colorVec(Object raw) {
    if (raw is Map) {
      final r = raw['r'], g = raw['g'], b = raw['b'], a = raw['a'];
      if (r is num && g is num && b is num && a is num) {
        return Vector4(r.toDouble(), g.toDouble(), b.toDouble(), a.toDouble());
      }
    }
    return null;
  }

  // --- sync ---------------------------------------------------------------

  static const _cheapSlots = {
    ChangeSlot.transform,
    ChangeSlot.visible,
    ChangeSlot.layers,
    ChangeSlot.name,
  };

  Future<void> _reflect(Transaction transaction) async {
    if (transaction.isEmpty) return;
    // A stage-only edit just re-applies scene-wide settings; no re-realize.
    if (transaction.records.every((r) => r.slot == ChangeSlot.stage)) {
      await realizeStage(
        document,
        scene,
        environmentLoader: _loadAssetEnvironment,
        fmatSkyLoader: fmatLibrary.loadSky,
      );
      return;
    }
    // Creating an unreferenced resource has no live-scene effect. Primitive
    // creation builds its geometry and material before attaching either to a
    // node, so realizing the entire existing scene here is pure waste. An fmat
    // material is the exception: compile it now (async) so the realizer has it
    // cached when a mesh later references it, instead of the synchronous
    // component realize degrading to unlit.
    if (transaction.records.every(
      (r) =>
          r.slot == ChangeSlot.poolResource &&
          r.oldValue is ResourceChange &&
          (r.oldValue as ResourceChange).value == null,
    )) {
      final fmatCreates = transaction.records
          .map((r) => r.targetId)
          .where(_isFmatMaterial)
          .toSet();
      if (fmatCreates.isEmpty) return;
      await _reflectMaterials(fmatCreates);
      return;
    }
    // An environment-resource edit re-resolves only the affected environments
    // in place, avoiding the full re-realize (which clears the scene, so a
    // committed slider would flash the old look before snapping to the new).
    if (transaction.records.every(
      (r) =>
          r.slot == ChangeSlot.poolResource &&
          document.resource(r.targetId) is EnvironmentResource,
    )) {
      await _reflectEnvironmentResources(
        transaction.records.map((r) => r.targetId).toSet(),
      );
      return;
    }
    // A material-resource edit re-realizes just the changed material(s) and
    // swaps them onto the live primitives that use them, with no scene re-build
    // and (crucially) no environment re-bake. This is what makes a material
    // tweak cheap instead of a full removeAll + realize (the half-second flash).
    if (transaction.records.every(
      (r) =>
          r.slot == ChangeSlot.poolResource &&
          document.resource(r.targetId) is MaterialResource,
    )) {
      await _reflectMaterials(
        transaction.records.map((r) => r.targetId).toSet(),
      );
      return;
    }
    if (_reflectRemovedNodes(transaction)) return;
    if (_reflectAddedNode(transaction)) return;
    if (_reflectComponents(transaction)) return;
    if (transaction.records.every((r) => r.slot == ChangeSlot.instance) &&
        _reflectInstanceDelta(transaction)) {
      return;
    }
    final cheap = transaction.records.every(
      (r) => _cheapSlots.contains(r.slot),
    );
    if (cheap) {
      _reflectCheap(transaction);
    } else {
      await _realizeAll();
    }
  }

  // Re-realizes the material resources in [ids] and re-applies their properties
  // onto the live materials in place (found by resource-origin stamp). Skips
  // environment realization (preload includeEnvironments: false), so a material
  // edit never re-bakes the prefilter cubes.
  //
  // The properties are copied onto the EXISTING live material object rather than
  // swapping in a new one: a mesh component captures its material in a render
  // item at mount and does not re-read it per frame, so swapping the reference
  // would leave the render item pointing at the old object until the next full
  // re-realize. Mutating in place keeps the render item's material live.
  Future<void> _reflectMaterials(Set<LocalId> ids) async {
    // An fmat resource whose live material was built from a different `.fmat`
    // (or never loaded and fell back to unlit) needs new shaders, which only
    // a full realize swaps in.
    if (_fmatMaterialsNeedRealize(ids)) {
      await _realizeAll();
      notifyListeners();
      return;
    }
    // The composed document holds the resource objects captured at compose
    // time, and a material edit replaces (or creates) the host document's
    // object; refresh the composed copies (host resource ids pass through
    // composition unchanged, so inserting a newly created one is safe) so
    // the realizer reloads the fresh values in place instead of a full
    // re-realize per slider commit.
    final composed = _composed;
    if (composed != null) {
      for (final id in ids) {
        final updated = document.resource(id);
        if (updated != null) composed.resources[id] = updated;
      }
    }
    final realizer = _resourceRealizer;
    if (realizer == null) {
      await _realizeAll();
      return;
    }
    final rebuilt = <LocalId, Material>{};
    for (final id in ids) {
      if (document.resource(id) is MaterialResource) {
        rebuilt[id] = await realizer.reloadMaterial(id);
      }
    }
    if (rebuilt.isEmpty) return;
    // Each live material object is shared across the primitives that use it, so
    // apply once per distinct object.
    final applied = <Material>{};
    for (final node in _liveById.values) {
      for (final mesh in node.getComponents<MeshComponent>()) {
        for (final primitive in mesh.mesh.primitives) {
          final origin = resourceOrigin(primitive.material);
          final next = origin == null ? null : rebuilt[origin.resourceId];
          if (next != null && applied.add(primitive.material)) {
            _applyMaterialInto(next, primitive.material);
          }
        }
      }
    }
    notifyListeners();
  }

  // Whether resource [id] is an fmat material (which compiles asynchronously).
  bool _isFmatMaterial(LocalId id) {
    final res = document.resource(id);
    return res is MaterialResource && res.type == 'fmat';
  }

  // Whether any changed fmat material resource cannot be reconciled onto its
  // live material in place: the live side is not a PreprocessedMaterial (an
  // earlier load failed and degraded to unlit) or was built from a different
  // `.fmat` source.
  bool _fmatMaterialsNeedRealize(Set<LocalId> ids) {
    final fmatIds = <LocalId, String?>{};
    for (final id in ids) {
      final res = document.resource(id);
      if (res is MaterialResource && res.type == 'fmat') {
        fmatIds[id] = res.asset?.key;
      }
    }
    if (fmatIds.isEmpty) return false;
    for (final node in _liveById.values) {
      for (final mesh in node.getComponents<MeshComponent>()) {
        for (final primitive in mesh.mesh.primitives) {
          final origin = resourceOrigin(primitive.material);
          if (origin == null || !fmatIds.containsKey(origin.resourceId)) {
            continue;
          }
          final material = primitive.material;
          if (material is! PreprocessedMaterial ||
              fmatSourcePathOf(material) != fmatIds[origin.resourceId]) {
            return true;
          }
        }
      }
    }
    return false;
  }

  // Adds the empty node produced by createNode directly to the retained live
  // graph. More complex structural edits still use the full realization path.
  bool _reflectAddedNode(Transaction transaction) {
    if (_composed != null || _realizedRoot == null) return false;
    if (transaction.records.any(
      (record) =>
          record.slot != ChangeSlot.poolNode &&
          record.slot != ChangeSlot.children &&
          record.slot != ChangeSlot.roots,
    )) {
      return false;
    }
    final additions = transaction.records.where(
      (record) =>
          record.slot == ChangeSlot.poolNode &&
          record.oldValue is NodeChange &&
          (record.oldValue as NodeChange).value == null &&
          document.nodes.containsKey(record.targetId),
    );
    if (additions.length != 1) return false;
    final id = additions.single.targetId;
    final spec = document.nodes[id]!;
    if (spec.components.isNotEmpty ||
        spec.children.isNotEmpty ||
        spec.skin != null ||
        spec.instance != null) {
      return false;
    }
    LocalId? parentId;
    for (final entry in document.nodes.entries) {
      if (entry.value.children.contains(id)) {
        parentId = entry.key;
        break;
      }
    }
    final parent = parentId == null ? _realizedRoot : _liveById[parentId];
    if (parent == null) return false;
    final live = tagNodeId(
      Node(name: spec.name)
        ..layers = spec.layers
        ..visible = spec.visible,
      id,
    );
    applyTransformSpec(live, spec.transform);
    parent.add(live);
    _liveById[id] = live;
    _sourceIdByLive[live] = id;
    return true;
  }

  // Removes live nodes for a structural deletion, including undoing a freshly
  // created node. The document records already identify the entire removed
  // subtree, so no unrelated node or resource needs to be rebuilt.
  bool _reflectRemovedNodes(Transaction transaction) {
    if (_composed != null || _realizedRoot == null) return false;
    if (transaction.records.any(
      (record) =>
          record.slot != ChangeSlot.poolNode &&
          record.slot != ChangeSlot.children &&
          record.slot != ChangeSlot.roots,
    )) {
      return false;
    }
    final removed = <LocalId, Node>{};
    for (final record in transaction.records) {
      if (record.slot != ChangeSlot.poolNode ||
          document.nodes.containsKey(record.targetId)) {
        continue;
      }
      final live = _liveById[record.targetId];
      if (live != null) removed[record.targetId] = live;
    }
    if (removed.isEmpty) return false;
    final removedNodes = removed.values.toSet();
    for (final live in removed.values) {
      final parent = live.parent;
      if (parent != null && !removedNodes.contains(parent)) {
        parent.remove(live);
      }
    }
    for (final entry in removed.entries) {
      _liveById.remove(entry.key);
      _sourceIdByLive.remove(entry.value);
    }
    return true;
  }

  // Replaces components only on the nodes whose component lists changed.
  // Component codecs are synchronous once the retained resource realizer has
  // loaded the document, so this avoids rebuilding unrelated nodes/resources.
  bool _reflectComponents(Transaction transaction) {
    if (_resourceRealizer == null) return false;
    if (!transaction.records.every(
      (record) => record.slot == ChangeSlot.components,
    )) {
      return false;
    }
    final ids = transaction.records.map((record) => record.targetId).toSet();
    final context = RealizeContext(document, resources: _resourceRealizer)
      ..resolveNode = (id) => _liveById[id];
    final replacements = <Node, List<Component>>{};
    for (final id in ids) {
      final spec = document.nodes[id];
      final live = _liveById[id];
      if (spec == null || live == null) return false;
      // A prefab instance's composed node merges prefab-authored components
      // with the host spec's, so realizing from the host spec alone would
      // wipe the authored ones (and the composed mirror below would bake the
      // wipe in). Instance edits take the full realize path.
      if (spec.instance != null) return false;
      final components = <Component>[];
      for (final componentSpec in spec.components) {
        final component = _componentRegistry.realize(componentSpec, context);
        if (component == null) return false;
        components.add(component);
      }
      replacements[live] = components;
    }
    for (final entry in replacements.entries) {
      for (final component in entry.key.getComponents<Component>().toList()) {
        entry.key.removeComponent(component);
      }
      for (final component in entry.value) {
        entry.key.addComponent(component);
      }
    }
    // Mirror onto the composed document (the display tree), which holds its
    // own node copies when the scene has prefab instances; without this the
    // inspector shows stale values after the in-place edit.
    if (_composed != null) {
      for (final id in ids) {
        final composedNode = _composed!.nodes[id];
        final spec = document.nodes[id];
        if (composedNode == null || spec == null || composedNode == spec) {
          continue;
        }
        composedNode.components
          ..clear()
          ..addAll(spec.components);
      }
    }
    context.runAfterRealize();
    return true;
  }

  // A prefab-instance edit that only adds or updates override values (the
  // routed member property commit) patches the composed document and the
  // affected live member in place. Anything structural (a removed override,
  // changed attachments or member components, a different source) returns
  // false for the full realize. Override objects pass through unchanged
  // rebuilds by identity, so identity comparison finds the delta.
  bool _reflectInstanceDelta(Transaction transaction) {
    final composed = _composed;
    if (composed == null || _resourceRealizer == null) return false;
    final changes = <(LocalId, PropertyOverride)>[];
    for (final record in transaction.records) {
      if (record.slot != ChangeSlot.instance) return false;
      final old = (record.oldValue as PrefabInstanceChange).value;
      final next = (record.newValue as PrefabInstanceChange).value;
      if (old == null || next == null) return false;
      if (old.source.key != next.source.key ||
          old.load != next.load ||
          !identical(old.attachments, next.attachments) ||
          !identical(old.removedNodes, next.removedNodes) ||
          !identical(old.addedComponents, next.addedComponents) ||
          !identical(old.removedComponentTypes, next.removedComponentTypes) ||
          !identical(old.memberComponents, next.memberComponents)) {
        return false;
      }
      final previous = <(LocalId, String), PropertyOverride>{
        for (final o in old.overrides) (o.target, o.path): o,
      };
      for (final o in next.overrides) {
        final before = previous.remove((o.target, o.path));
        if (before == null || !identical(before.value, o.value)) {
          changes.add((record.targetId, o));
        }
      }
      // A leftover means an override was removed; its value reverts to the
      // prefab's own, which only a recompose can recover.
      if (previous.isNotEmpty) return false;
    }
    for (final (instanceId, override) in changes) {
      final composedId = _composedMemberId(instanceId, override.target);
      if (composedId == null) return false;
      applyPrefabOverride(
        composed,
        PropertyOverride(
          target: composedId,
          path: override.path,
          value: override.value,
        ),
      );
      if (!_reapplyComposedNode(composedId, override.path)) return false;
    }
    return true;
  }

  // The composed-document node the member [prefabLocalId] of [instanceId]
  // expanded to (the instance node itself for the merged prefab root).
  LocalId? _composedMemberId(LocalId instanceId, LocalId prefabLocalId) {
    if (_memberOrigins[instanceId]?.prefabLocalId == prefabLocalId) {
      return instanceId;
    }
    for (final entry in _memberOrigins.entries) {
      if (entry.value.instanceId == instanceId &&
          entry.value.prefabLocalId == prefabLocalId) {
        return entry.key;
      }
    }
    return null;
  }

  // Refreshes the slice of live node [id] that composed-document property
  // [path] feeds: components re-realize from the composed spec for a
  // component path, the transform and flags copy directly. Unknown paths
  // return false so the caller falls back to the full realize.
  // Mirrors an override the compose layer already applied to the composed
  // spec onto the live node, dispatching on the compose layer's own path
  // classification so the grammar lives in one place.
  bool _reapplyComposedNode(LocalId id, String path) {
    final composed = _composed;
    final realizer = _resourceRealizer;
    final spec = composed?.nodes[id];
    final live = _liveById[id];
    if (composed == null || realizer == null || spec == null || live == null) {
      return false;
    }
    switch (prefabOverrideAspect(path)) {
      case PrefabOverrideAspect.name:
        return true;
      case PrefabOverrideAspect.visible:
        live.visible = spec.visible;
        return true;
      case PrefabOverrideAspect.layers:
        live.layers = spec.layers;
        return true;
      case PrefabOverrideAspect.lightChannelMask:
        live.lightChannelMask = spec.lightChannelMask;
        return true;
      case PrefabOverrideAspect.raycastable:
        live.raycastable = spec.raycastable;
        return true;
      case PrefabOverrideAspect.transform:
        live.localTransform = spec.transform.toMatrix4();
        return true;
      case PrefabOverrideAspect.unsupported:
        return false;
      case PrefabOverrideAspect.components:
        break;
    }
    final context = RealizeContext(composed, resources: realizer)
      ..resolveNode = (nodeId) => _liveById[nodeId];
    final components = <Component>[];
    for (final componentSpec in spec.components) {
      final component = _componentRegistry.realize(componentSpec, context);
      if (component == null) return false;
      components.add(component);
    }
    for (final component in live.getComponents<Component>().toList()) {
      live.removeComponent(component);
    }
    for (final component in components) {
      live.addComponent(component);
    }
    context.runAfterRealize();
    return true;
  }

  // Copies the renderable fields of the freshly realized [from] onto the live
  // [into], in place. Only same-type materials are reconciled (a material's
  // type does not change through setMaterialProperties).
  // Copies every property the realizer's _pbr reads from the document; a
  // field missed here silently never reaches the live material on commit
  // (the slider preview writes it directly, so the miss shows up as edits
  // capped at the slider's reach).
  static void _applyMaterialInto(Material from, Material into) {
    if (from is PhysicallyBasedMaterial && into is PhysicallyBasedMaterial) {
      into
        ..baseColorFactor = from.baseColorFactor
        ..emissiveFactor = from.emissiveFactor
        ..emissiveStrength = from.emissiveStrength
        ..metallicFactor = from.metallicFactor
        ..roughnessFactor = from.roughnessFactor
        ..occlusionStrength = from.occlusionStrength
        ..normalScale = from.normalScale
        ..doubleSided = from.doubleSided
        ..alphaMode = from.alphaMode
        ..alphaCutoff = from.alphaCutoff
        ..baseColorTexture = from.baseColorTexture
        ..baseColorTextureTransform = from.baseColorTextureTransform
        ..baseColorTextureTexCoord = from.baseColorTextureTexCoord
        ..metallicRoughnessTexture = from.metallicRoughnessTexture
        ..metallicRoughnessTextureTransform =
            from.metallicRoughnessTextureTransform
        ..metallicRoughnessTextureTexCoord =
            from.metallicRoughnessTextureTexCoord
        ..normalTexture = from.normalTexture
        ..normalTextureTransform = from.normalTextureTransform
        ..normalTextureTexCoord = from.normalTextureTexCoord
        ..occlusionTexture = from.occlusionTexture
        ..occlusionTextureTransform = from.occlusionTextureTransform
        ..occlusionTextureTexCoord = from.occlusionTextureTexCoord
        ..emissiveTexture = from.emissiveTexture
        ..emissiveTextureTransform = from.emissiveTextureTransform
        ..emissiveTextureTexCoord = from.emissiveTextureTexCoord;
    } else if (from is UnlitMaterial && into is UnlitMaterial) {
      into
        ..baseColorFactor = from.baseColorFactor
        ..doubleSided = from.doubleSided
        ..baseColorTexture = from.baseColorTexture;
    } else if (from is PreprocessedMaterial && into is PreprocessedMaterial) {
      // Both instances were built from the same compiled `.fmat` entry (the
      // asset-change case re-realizes instead), so the layouts agree and the
      // fresh instance's parameter state (document overrides over sidecar
      // defaults) copies over wholesale.
      into.parameters.copyStateFrom(from.parameters);
    }
  }

  // Re-resolves the environment resources in [ids] onto the live scene in
  // place (the global stage environment and the settings of any mounted volume
  // component that references one of them). A parameter-only edit reuses the live
  // sky bindings (see reapplyEnvironmentSettingsInPlace) so reflections re-bake
  // smoothly instead of from zero; a structural change falls back to a full
  // realize.
  Future<void> _reflectEnvironmentResources(Set<LocalId> ids) async {
    final globalRef = document.stage.environmentRef;
    if (globalRef != null && ids.contains(globalRef)) {
      final resource = document.resource(globalRef);
      // The in-place reapply reuses the live environment when the look's
      // structure matches, but it cannot see a reflection-resolution change
      // (the live map does not expose its built size), so detect that here and
      // force a structural rebuild at the new size.
      final sizeChanged =
          resource is EnvironmentResource &&
          _builtRadianceSize[globalRef] != resource.radianceCubeSize;
      if (!(resource is EnvironmentResource &&
          !sizeChanged &&
          _reapplyGlobalEnvironmentInPlace(resource))) {
        await realizeStage(
          document,
          scene,
          environmentLoader: _loadAssetEnvironment,
          fmatSkyLoader: fmatLibrary.loadSky,
        );
      }
      if (resource is EnvironmentResource) {
        _builtRadianceSize[globalRef] = resource.radianceCubeSize;
      }
    }
    for (final node in document.nodes.values) {
      for (final spec in node.components) {
        if (spec.type != 'environmentVolume') continue;
        final ref = spec.properties['environment'];
        if (ref is! ResourceRefValue || !ids.contains(ref.id)) continue;
        final resource = document.resource(ref.id);
        final live = _liveById[node.id]
            ?.getComponent<EnvironmentVolumeComponent>();
        if (resource is! EnvironmentResource || live == null) continue;
        final sizeChanged =
            _builtRadianceSize[ref.id] != resource.radianceCubeSize;
        if (sizeChanged || !_reapplyResourceInPlace(resource, live.settings)) {
          live.settings = await realizeEnvironmentSettings(
            environment: resource.environment,
            environmentIntensity: resource.environmentIntensity,
            exposure: resource.exposure,
            toneMapping: resource.toneMapping,
            agxWhite: resource.agxWhite,
            agxContrast: resource.agxContrast,
            environmentRotationY: resource.environmentRotationY,
            radianceCubeSize: resource.radianceCubeSize,
            skybox: resource.skybox,
            skyEnvironment: resource.skyEnvironment,
            effects: resource.effects,
            environmentLoader: _loadAssetEnvironment,
            fmatSkyLoader: fmatLibrary.loadSky,
          );
        }
        _builtRadianceSize[ref.id] = resource.radianceCubeSize;
      }
    }
    notifyListeners();
  }

  // The reflection-cube size each environment resource was last built at, so a
  // resolution change can be detected and force a rebuild (the live map does not
  // carry its size). Populated by _realizeAll and the env reflect.
  final Map<LocalId, int?> _builtRadianceSize = {};

  void _recordBuiltRadianceSizes() {
    _builtRadianceSize.clear();
    for (final resource in document.resources.values) {
      if (resource is EnvironmentResource) {
        _builtRadianceSize[resource.id] = resource.radianceCubeSize;
      }
    }
  }

  // Re-applies [resource] onto the live global look in place, returning false
  // when a structural change means the caller must realize the stage afresh.
  // With volumes active the blend reads scene.baseEnvironment, so mutate that;
  // otherwise the live scene fields are authoritative.
  bool _reapplyGlobalEnvironmentInPlace(EnvironmentResource resource) {
    final blendActive =
        scene.environmentVolumes.isNotEmpty ||
        scene.renderScene.environmentVolumeComponents.isNotEmpty;
    if (blendActive) {
      final base = scene.baseEnvironment;
      return base != null && _reapplyResourceInPlace(resource, base);
    }
    final target = EnvironmentSettings.fromScene(scene);
    if (!_reapplyResourceInPlace(resource, target)) return false;
    target.applyTo(scene);
    return true;
  }

  bool _reapplyResourceInPlace(
    EnvironmentResource resource,
    EnvironmentSettings target,
  ) => reapplyEnvironmentSettingsInPlace(
    target: target,
    environment: resource.environment,
    environmentIntensity: resource.environmentIntensity,
    exposure: resource.exposure,
    toneMapping: resource.toneMapping,
    agxWhite: resource.agxWhite,
    agxContrast: resource.agxContrast,
    environmentRotationY: resource.environmentRotationY,
    effects: resource.overridesEffects ? resource.effects : null,
    skybox: resource.skybox,
    skyEnvironment: resource.skyEnvironment,
  );

  void _reflectCheap(Transaction transaction) {
    for (final record in transaction.records) {
      final docNode = document.node(record.targetId);
      if (docNode == null) continue;
      final live = _liveById[record.targetId];
      // Mirror the change onto the composed document too, since the outliner
      // and inspector read the composed document as their display tree; without
      // this they show stale values after a cheap edit (a moved gizmo, a
      // toggled visibility) when the scene has prefab instances.
      final composedNode = _composed?.nodes[record.targetId];
      switch (record.slot) {
        case ChangeSlot.transform:
          live?.localTransform = docNode.transform.toMatrix4();
          composedNode?.transform = docNode.transform;
        case ChangeSlot.visible:
          live?.visible = docNode.visible;
          composedNode?.visible = docNode.visible;
        case ChangeSlot.layers:
          live?.layers = docNode.layers;
          composedNode?.layers = docNode.layers;
        case ChangeSlot.name:
          composedNode?.name = docNode.name;
        default:
          break;
      }
    }
  }

  Future<void> _realizeAll() async {
    // Expand prefab instances before realizing. Documents with no eager
    // instance realize unchanged, so non-prefab scenes are untouched.
    final hasEagerInstance = document.nodes.values.any(
      (n) => n.instance != null && n.instance!.load == LoadPolicy.eager,
    );
    final SceneDocument toRealize;
    if (hasEagerInstance) {
      final origins = <LocalId, PrefabMemberOrigin>{};
      toRealize = await composeSceneAsync(
        document,
        load: _loadPrefab,
        memberOrigins: origins,
      );
      _composed = toRealize;
      _memberOrigins = origins;
    } else {
      toRealize = document;
      _composed = null;
      _memberOrigins = {};
    }
    // Build the scene graph with a realizer that loads disk environments
    // through the environment's own realization (see _loadAssetEnvironment).
    final realizer = ResourceRealizer(
      toRealize,
      environmentLoader: _loadAssetEnvironment,
      textureLoader: _loadAssetTexture,
      fmatMaterialLoader: _loadFmatMaterial,
    );
    await realizer.preload();
    final root = await realizeSceneAsync(
      toRealize,
      resources: realizer,
      registry: _componentRegistry,
    );
    scene.removeAll();
    scene.add(root);
    _resourceRealizer = realizer;
    _realizedRoot = root;
    _realizeEpoch++;
    // Apply the document's scene-wide settings (environment/lighting, exposure,
    // tone mapping, anti-aliasing) to the live scene.
    await realizeStage(
      document,
      scene,
      environmentLoader: _loadAssetEnvironment,
      fmatSkyLoader: fmatLibrary.loadSky,
    );
    _recordBuiltRadianceSizes();
    _liveById.clear();
    _sourceIdByLive.clear();
    _index(root, null);
    // Re-apply selection highlights to the freshly realized live nodes.
    _syncHighlights();
  }

  // Caches built disk environments by path + reflection-cube size, so a
  // re-realize reuses an unchanged map but a resolution change rebuilds.
  final Map<String, EnvironmentMap> _diskEnvCache = {};

  // The environment-asset loader handed to the realizer and to realizeStage, so
  // an AssetEnvironment that resolves to a file on disk (an imported `.hdr`,
  // `.exr`, or LDR equirect) is decoded and prefiltered as part of the
  // environment's own
  // realization. Returns null for an asset not on disk, so the realizer falls
  // back to the asset bundle (the in-bundle example assets). The realizer sets
  // EnvironmentMap.radianceCubeSize around this call, so the built cube honors
  // the reflection-resolution setting; the cache is keyed by it.
  Future<EnvironmentMap?> _loadAssetEnvironment(AssetRef asset) async {
    final path = _resolveAssetPath(asset.key);
    if (path == null || !File(path).existsSync()) return null;
    final cacheKey = '$path|${EnvironmentMap.radianceCubeSize}';
    final cached = _diskEnvCache[cacheKey];
    if (cached != null) return cached;
    try {
      final bytes = await File(path).readAsBytes();
      // Detects Radiance HDR, OpenEXR, or an LDR image from the bytes and
      // decodes off the UI isolate. The width cap keeps a 16K source from
      // uploading ~1 GB; a realtime environment does not need more.
      final env = await EnvironmentMap.fromEquirectImageBytes(
        bytes: bytes,
        maxWidth: 4096,
      );
      _diskEnvCache[cacheKey] = env;
      return env;
    } catch (e) {
      lastError.value = 'Failed to load environment "$path": $e';
      return null;
    }
  }

  final Map<String, ui.Image> _diskTextureCache = {};
  final Map<String, Future<FmatMaterialRegistry>> _diskFmatRegistryCache = {};

  // The texture loader handed to the realizers, so a TextureResource.asset that
  // resolves to a file on disk (an editor-imported image under imported/) is
  // decoded from disk rather than the asset bundle. Returns null for an asset
  // not on disk, so the realizer falls back to the asset bundle (the in-bundle
  // example assets). Decoded images are cached by path so a node-structural
  // re-realize does not re-decode every imported texture.
  Future<ui.Image?> _loadAssetTexture(AssetRef asset) async {
    final path = _resolveAssetPath(asset.key);
    if (path == null || !File(path).existsSync()) return null;
    final cached = _diskTextureCache[path];
    if (cached != null) return cached;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _diskTextureCache[path] = frame.image;
      return frame.image;
    } catch (e) {
      lastError.value = 'Failed to load texture "$path": $e';
      return null;
    }
  }

  String? _resolveAssetPath(String key) => _resolveFilePath(key, baseDirectory);

  // Loads an fmat material for the realizer: compiles the `.fmat` source on
  // demand (engaging the watcher for live hot swaps), falling back to cooked
  // build output when the toolchain or source is unavailable.
  Future<PreprocessedMaterial> _loadFmatMaterial(AssetRef asset) async {
    final compiled = await fmatLibrary.loadMaterial(asset);
    if (compiled != null) return compiled;
    return _loadDiskFmatMaterial(asset);
  }

  Future<PreprocessedMaterial> _loadDiskFmatMaterial(AssetRef asset) async {
    final outputDirectory = _findMaterialOutputDirectory();
    if (outputDirectory == null) {
      // TODO(fmat-editor): Compile source materials when cooked output is absent.
      throw StateError(
        'No compiled material output for "${asset.key}"; no '
        'build/shaderbundles exists at or above "$baseDirectory"',
      );
    }
    final indexFiles =
        outputDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.index.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final indexFile in indexFiles) {
      final indexJson = (jsonDecode(await indexFile.readAsString()) as Map)
          .cast<String, Object?>();
      final materials = (indexJson['materials'] as Map).values;
      final matches = materials.any(
        (entry) => (entry as Map)['source'] == asset.key,
      );
      if (!matches) continue;
      final package = indexJson['package'] as String;
      final bundleName = indexJson['bundleName'] as String;
      final shaderKey = indexJson['shaderBundleAssetKey'] as String;
      final sidecarKey = indexJson['sidecarAssetKey'] as String;
      final indexKey =
          'packages/$package/flutter_scene/fmat/$bundleName/'
          '$bundleName.index.json';
      final registry = await _diskFmatRegistryCache.putIfAbsent(
        indexFile.path,
        () => FmatMaterialRegistry.load(
          bundle: _DiskAssetBundle({
            indexKey: indexFile,
            shaderKey: File(
              '${outputDirectory.path}${Platform.pathSeparator}'
              '$bundleName.shaderbundle',
            ),
            sidecarKey: File(
              '${outputDirectory.path}${Platform.pathSeparator}'
              '$bundleName.fmat.json',
            ),
          }),
          assetKeys: [indexKey],
        ),
      );
      return registry.loadMaterial(asset.key);
    }
    throw StateError('No compiled material entry exists for "${asset.key}"');
  }

  // The nearest cooked material output at or above the scene. Searching for
  // the output itself rather than for where the asset key resolves, since a
  // "../" key resolves against the scene's own directory and would stop the
  // walk there.
  Directory? _findMaterialOutputDirectory() {
    var directory = baseDirectory == null
        ? null
        : Directory(baseDirectory!).absolute;
    while (directory != null) {
      final candidate = Directory(
        '${directory.path}${Platform.pathSeparator}build'
        '${Platform.pathSeparator}shaderbundles',
      );
      if (candidate.existsSync()) return candidate;
      final parent = directory.parent;
      directory = parent.path == directory.path ? null : parent;
    }
    return null;
  }

  Future<SceneDocument> _loadPrefab(AssetRef ref) async {
    final key = ref.key;
    final path = _resolveFilePath(key, baseDirectory);
    if (path == null) {
      throw StateError(
        'Cannot resolve relative prefab "$key" without a base directory',
      );
    }
    final lowerPath = path.toLowerCase();
    final SceneDocument prefab;
    if (lowerPath.endsWith('.fsceneb')) {
      prefab = readFsceneb(await File(path).readAsBytes());
    } else if (lowerPath.endsWith('.glb')) {
      prefab = importGlbToSceneDocument(await File(path).readAsBytes());
    } else if (lowerPath.endsWith('.gltf')) {
      final directory = File(path).parent.path;
      prefab = importGltfToSceneDocument(
        await File(path).readAsBytes(),
        resolveUri: (uri) {
          final file = File('$directory${Platform.pathSeparator}$uri');
          return file.existsSync() ? file.readAsBytesSync() : null;
        },
      );
    } else {
      prefab = readFscene(await File(path).readAsString());
    }
    _resolveDocumentFileAssets(prefab, File(path).parent.path);
    return prefab;
  }

  // A linked scene owns its relative prefab and image paths. Composition loses
  // that file boundary, so resolve those paths before returning the document.
  void _resolveDocumentFileAssets(SceneDocument prefab, String directory) {
    for (final node in prefab.nodes.values) {
      final instance = node.instance;
      if (instance == null) continue;
      final path = _resolveFilePath(instance.source.key, directory)!;
      node.instance = instance.copyWith(source: AssetRef(path));
    }
    for (final entry in prefab.resources.entries.toList()) {
      final resource = entry.value;
      if (resource is TextureResource && resource.asset != null) {
        prefab.resources[entry.key] = TextureResource(
          resource.id,
          asset: AssetRef(_resolveFilePath(resource.asset!.key, directory)!),
          content: resource.content,
        );
      } else if (resource is EnvironmentResource &&
          resource.environment is AssetEnvironment) {
        final environment = resource.environment as AssetEnvironment;
        resource.environment = AssetEnvironment(
          AssetRef(_resolveFilePath(environment.asset.key, directory)!),
        );
      }
    }
  }

  String? _resolveFilePath(String key, String? directory) {
    if (_isAbsoluteFilePath(key)) return key;
    if (directory == null) return null;
    return File(
      '$directory${Platform.pathSeparator}$key',
    ).absolute.uri.normalizePath().toFilePath();
  }

  bool _isAbsoluteFilePath(String path) =>
      path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

  void _index(Node node, LocalId? sourceAncestor) {
    final id = nodeFsceneId(node);
    final source = (id != null && document.nodes.containsKey(id))
        ? id
        : sourceAncestor;
    if (id != null) _liveById[id] = node;
    if (source != null) _sourceIdByLive[node] = source;
    for (final child in node.children) {
      _index(child, source);
    }
  }

  @override
  void dispose() {
    session.selection.removeListener(_onSelectionChanged);
    fmatLibrary.dispose();
    lastError.dispose();
    previewEpoch.dispose();
    scene.removeAll();
    super.dispose();
  }
}

final class _DiskAssetBundle extends CachingAssetBundle {
  _DiskAssetBundle(this.files);

  final Map<String, File> files;

  @override
  Future<ByteData> load(String key) async {
    final file = files[key];
    if (file == null) throw FlutterError('Unknown disk asset "$key"');
    return ByteData.sublistView(await file.readAsBytes());
  }
}

// The transform an import applies to its content, or null when scale is 1 and
// the up axis is the glTF-native Y so no wrapping group is warranted. Z-up adds
// a -90 degrees rotation about X to bring the model into Y-up.
TransformSpec? _importTransform(double scale, ImportUpAxis upAxis) {
  if (scale == 1.0 && upAxis == ImportUpAxis.yUp) return null;
  final rotation = upAxis == ImportUpAxis.zUp
      ? Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2)
      : Quaternion.identity();
  return TrsTransform(rotation: rotation, scale: Vector3.all(scale));
}
