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
/// drag never pays for re-realization. Structural and resource edits
/// (create, delete, reparent, component and material changes) re-realize the
/// document, which is correct and fast for the procedural scenes this phase
/// targets. The live node for a document id is found through the realizer's
/// own id tagging ([nodeFsceneId]).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fscene/compose/compose.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

import '../io/glb_import_options.dart';

/// Reflects an [EditorSession] into a live [Scene] and back.
class EditorController extends ChangeNotifier {
  EditorController._(this.session, this.scene, this.baseDirectory);

  /// The headless editing session (document, commands, history, selection).
  final EditorSession session;

  /// The live scene the viewport renders.
  final Scene scene;

  /// The directory the open scene was loaded from, used to resolve prefab
  /// instance references (their source paths) relative to the scene file. Null
  /// for a new in-memory scene, which has no prefab references to resolve.
  final String? baseDirectory;

  final Map<LocalId, Node> _liveById = {};
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
  }) async {
    final controller = EditorController._(session, Scene(), baseDirectory);
    // Keep prefab-internal nodes (which live only in the composed document)
    // selectable across edits, not just source nodes.
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

  /// Opens a controller over a new empty document.
  static Future<EditorController> empty() =>
      open(EditorSession(SceneDocument()));

  /// Opens a controller over a document loaded from `.fscene` [source].
  /// [baseDirectory] resolves any prefab references in the document.
  static Future<EditorController> fromFscene(
    String source, {
    String? baseDirectory,
  }) => open(EditorSession.fromFscene(source), baseDirectory: baseDirectory);

  /// Opens a controller over a glTF binary ([glbBytes]) imported in memory to
  /// an editable document, ready to edit and save as `.fscene`. Set
  /// [compressTextures] to compress imported textures during the import.
  /// [scale] and [upAxis] apply a non-destructive transform to the imported
  /// content (a group node wrapping the roots), leaving the source untouched.
  static Future<EditorController> fromGlb(
    Uint8List glbBytes, {
    bool compressTextures = false,
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
    String? baseDirectory,
  }) {
    final doc = importGlbToSceneDocument(
      glbBytes,
      compressTextures: compressTextures,
    );
    final transform = _importTransform(scale, upAxis);
    if (transform != null) {
      wrapRootsUnderGroup(doc, name: 'Imported', transform: transform);
    }
    return open(EditorSession(doc), baseDirectory: baseDirectory);
  }

  /// The current selection.
  Selection get selection => session.selection;

  /// Read-only scene-graph queries.
  SceneQuery get query => session.query;

  /// The undo/redo history.
  EditHistory get history => session.history;

  /// The document being edited.
  SceneDocument get document => session.document;

  // The component registry, for reading component-type schemas (the editable
  // properties each type declares). Matches the registry realize uses.
  final FsceneComponentRegistry _componentRegistry = defaultComponentRegistry();

  /// The component type names that can be added to a node.
  List<String> componentTypes() => _componentRegistry.types.toList();

  /// The declared editable properties of component [type] (empty when the type
  /// declares none, or is unknown).
  List<ComponentPropertyDef> componentSchema(String type) =>
      _componentRegistry.codecFor(type)?.propertySchema ?? const [];

  /// The live node realized from document node [id], or null.
  Node? liveNode(LocalId id) => _liveById[id];

  /// The source-document node id that owns [liveNode] (the node itself, or the
  /// enclosing prefab instance root for a node realized from inside a prefab),
  /// or null. Used to turn a viewport raycast hit into a selectable node.
  LocalId? sourceIdForLiveNode(Node liveNode) => _sourceIdByLive[liveNode];

  /// Loads and caches the prefab document referenced by [source].
  ///
  /// Resolves [source.key] relative to [baseDirectory] (or treats it as
  /// absolute when it starts with `/`). Results are cached keyed by
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

  /// Imports a glTF binary ([glbBytes]) into the current scene as a new
  /// subtree, grafted under [parentId] (or the scene roots when null or
  /// missing), as one undoable edit. The imported root nodes become the
  /// selection. [compressTextures] compresses imported textures during the
  /// import.
  Future<void> importGlbIntoScene(
    Uint8List glbBytes, {
    LocalId? parentId,
    bool compressTextures = false,
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
  }) async {
    final source = importGlbToSceneDocument(
      glbBytes,
      compressTextures: compressTextures,
    );
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
    if (isPrefabMember(id)) {
      return _override(memberOrigin(id)!, 'name', name);
    }
    return run('setNodeName', {'nodeId': id.toToken(), 'name': name});
  }

  /// Sets node [id]'s visibility (an override when [id] is prefab content).
  Future<void> setNodeVisibleRouted(LocalId id, bool visible) {
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

  /// Previews a transform on the live node for [id] without touching the
  /// document or the history. Used during a gizmo drag; the final value is
  /// committed once with `setNodeTransform` on release.
  void previewLocalTransform(LocalId id, Matrix4 localTransform) {
    _liveById[id]?.localTransform = localTransform;
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
    final cheap = transaction.records.every(
      (r) => _cheapSlots.contains(r.slot),
    );
    if (cheap) {
      _reflectCheap(transaction);
    } else {
      await _realizeAll();
    }
  }

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
    final root = await realizeSceneAsync(toRealize);
    scene.removeAll();
    scene.add(root);
    _liveById.clear();
    _sourceIdByLive.clear();
    _index(root, null);
    // Re-apply selection highlights to the freshly realized live nodes.
    _syncHighlights();
  }

  Future<SceneDocument> _loadPrefab(AssetRef ref) async {
    final key = ref.key;
    final String path;
    if (key.startsWith('/')) {
      // An absolute path needs no base directory (the common case for a prefab
      // added to an unsaved scene, where the picked file is stored absolute).
      path = key;
    } else {
      final dir = baseDirectory;
      if (dir == null) {
        throw StateError(
          'Cannot resolve relative prefab "$key" without a base directory',
        );
      }
      path = '$dir/$key';
    }
    return readFscene(await File(path).readAsString());
  }

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
    lastError.dispose();
    scene.removeAll();
    super.dispose();
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
