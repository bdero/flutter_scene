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
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fscene/compose/compose.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/realize/stage.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

import '../io/glb_import_options.dart';
import '../io/hdr_decoder.dart';

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
  ///
  /// A new scene starts lit by a physical sky, with the sky driving the
  /// image-based lighting and casting sun shadows, a usable look-dev default
  /// rather than a black void. The skybox and the sky-lighting binding take
  /// their own sky-source instances (as the `setSkybox` command does).
  static Future<EditorController> empty() {
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
          castShadows: true,
        ),
      ),
    );
    document.stage.environmentRef = environment.id;
    return open(EditorSession(document));
  }

  /// Opens a controller over a document loaded from `.fscene` [source].
  /// [baseDirectory] resolves any prefab references in the document.
  static Future<EditorController> fromFscene(
    String source, {
    String? baseDirectory,
  }) => open(EditorSession.fromFscene(source), baseDirectory: baseDirectory);

  /// Opens a controller over an already-imported [document] (from a `.glb` or
  /// multi-file `.gltf`), ready to edit and save as `.fscene`. [scale] and
  /// [upAxis] apply a non-destructive transform to the content (a group node
  /// wrapping the roots), leaving the rest of the document untouched.
  static Future<EditorController> fromImportedScene(
    SceneDocument document, {
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
    String? baseDirectory,
  }) {
    final transform = _importTransform(scale, upAxis);
    if (transform != null) {
      wrapRootsUnderGroup(document, name: 'Imported', transform: transform);
    }
    return open(EditorSession(document), baseDirectory: baseDirectory);
  }

  /// Opens a controller over a glTF binary ([glbBytes]) imported in memory.
  /// Set [compressTextures] to compress imported textures during the import.
  static Future<EditorController> fromGlb(
    Uint8List glbBytes, {
    bool compressTextures = false,
    double scale = 1.0,
    ImportUpAxis upAxis = ImportUpAxis.yUp,
    String? baseDirectory,
  }) => fromImportedScene(
    importGlbToSceneDocument(glbBytes, compressTextures: compressTextures),
    scale: scale,
    upAxis: upAxis,
    baseDirectory: baseDirectory,
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
        _ => null,
      };
    }
    if (material is UnlitMaterial && key == 'baseColor') {
      return rgba(material.baseColorFactor);
    }
    return null;
  }

  /// Live-previews scene-wide settings on the live scene without touching the
  /// document or history (for stage slider drags). Commit with
  /// `setStageProperties` on release. With [volumeIndex] set, previews that
  /// environment volume's look instead of the base.
  void previewStage({
    double? exposure,
    double? environmentIntensity,
    int? volumeIndex,
  }) {
    final settings = _previewSettings(volumeIndex);
    if (settings != null) {
      // With volumes active, the per-frame blend recomputes the live fields, so
      // preview must write the holder the blend reads from.
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

  /// Live-previews an environment volume's region and blend metadata on the
  /// live scene (so the look fades in/out as the region is dragged) without
  /// touching the document. Commit with `setVolumeProperties` on release.
  void previewVolumeBounds(
    int index, {
    Vector3? center,
    Vector3? halfExtents,
    double? radius,
    double? weight,
    double? blendDistance,
    double? priority,
  }) {
    if (index < 0 || index >= scene.environmentVolumes.length) return;
    final v = scene.environmentVolumes[index];
    if (weight != null) v.weight = weight;
    if (blendDistance != null) v.blendDistance = blendDistance;
    if (priority != null) v.priority = priority;
    final bounds = v.bounds;
    if (bounds is BoxVolumeBounds) {
      if (center != null) bounds.center.setFrom(center);
      if (halfExtents != null) bounds.halfExtents.setFrom(halfExtents);
    } else if (bounds is SphereVolumeBounds) {
      if (center != null) bounds.center.setFrom(center);
      if (radius != null) bounds.radius = radius;
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

  // The EnvironmentSettings the volume blend reads for [volumeIndex] (a
  // volume's settings, or the base when volumes are active), or null when no
  // volume blending is active (the live scene fields are authoritative).
  EnvironmentSettings? _previewSettings(int? volumeIndex) {
    if (volumeIndex != null) {
      if (volumeIndex < 0 || volumeIndex >= scene.environmentVolumes.length) {
        return null;
      }
      return scene.environmentVolumes[volumeIndex].settings;
    }
    // baseEnvironment is the blend's global base, but the per-frame blend only
    // runs when a volume is active; otherwise the live look fields are
    // authoritative, so preview must mutate those (return null).
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
  void previewSkyParameter(String key, Object raw, {int? volumeIndex}) {
    final settings = _previewSettings(volumeIndex);
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
      await realizeStage(document, scene);
      await _applyDiskEnvironment();
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
    final cheap = transaction.records.every(
      (r) => _cheapSlots.contains(r.slot),
    );
    if (cheap) {
      _reflectCheap(transaction);
    } else {
      await _realizeAll();
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
      if (!(resource is EnvironmentResource &&
          _reapplyGlobalEnvironmentInPlace(resource))) {
        await realizeStage(document, scene);
      }
      await _applyDiskEnvironment();
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
        if (!_reapplyResourceInPlace(resource, live.settings)) {
          live.settings = await realizeEnvironmentSettings(
            environment: resource.environment,
            environmentIntensity: resource.environmentIntensity,
            exposure: resource.exposure,
            toneMapping: resource.toneMapping,
            radianceCubeSize: resource.radianceCubeSize,
            skybox: resource.skybox,
            skyEnvironment: resource.skyEnvironment,
          );
        }
      }
    }
    notifyListeners();
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
    final root = await realizeSceneAsync(toRealize);
    scene.removeAll();
    scene.add(root);
    // Apply the document's scene-wide settings (environment/lighting, exposure,
    // tone mapping, anti-aliasing) to the live scene.
    await realizeStage(document, scene);
    await _applyDiskEnvironment();
    _liveById.clear();
    _sourceIdByLive.clear();
    _index(root, null);
    // Re-apply selection highlights to the freshly realized live nodes.
    _syncHighlights();
  }

  // The asset path of the disk-loaded environment currently applied, so a
  // re-realize does not reload an unchanged image, and a cache by path.
  String? _diskEnvPath;
  final Map<String, EnvironmentMap> _diskEnvCache = {};

  /// Loads an editor `AssetEnvironment` from disk (an imported `.hdr` or an LDR
  /// equirect image) and applies it to the live scene. `realizeStage` resolves
  /// environments through the asset bundle, which a user-picked file is not in,
  /// so the editor loads it here; a studio/empty environment is left to
  /// `realizeStage`.
  // The stage's effective global environment: the referenced environment
  // resource's when set, otherwise the inline stage environment.
  EnvironmentSpec _globalEnvironmentSpec() {
    final ref = document.stage.environmentRef;
    if (ref != null) {
      final resource = document.resource(ref);
      if (resource is EnvironmentResource) return resource.environment;
    }
    return document.stage.environment;
  }

  Future<void> _applyDiskEnvironment() async {
    final env = _globalEnvironmentSpec();
    if (env is! AssetEnvironment) {
      _diskEnvPath = null;
      return;
    }
    final path = _resolveAssetPath(env.asset.key);
    if (path == null || path == _diskEnvPath) return;
    final loaded = await _loadDiskEnvironment(path);
    if (loaded != null) {
      scene.environment = loaded;
      // realizeStage captures the base look before this runs, so when volumes
      // are active the base's disk environment has to be folded in too.
      // TODO(volume-hdr): a volume cannot reference a disk environment yet;
      // teach this loader to apply imported HDRs to a volume's settings.
      scene.baseEnvironment?.environment = loaded;
      _diskEnvPath = path;
      notifyListeners();
    }
  }

  String? _resolveAssetPath(String key) {
    if (key.startsWith('/')) return key;
    final dir = baseDirectory;
    return dir == null ? null : '$dir/$key';
  }

  Future<EnvironmentMap?> _loadDiskEnvironment(String path) async {
    final cached = _diskEnvCache[path];
    if (cached != null) return cached;
    try {
      final bytes = await File(path).readAsBytes();
      final EnvironmentMap env;
      if (path.toLowerCase().endsWith('.hdr')) {
        // Cap the working equirect width; a realtime environment does not need
        // more, and a 16K source would otherwise upload ~1 GB.
        const maxEnvironmentWidth = 4096;
        final hdr = decodeRadianceHdr(bytes, maxWidth: maxEnvironmentWidth);
        env = await EnvironmentMap.fromEquirectHdr(
          linearPixels: hdr.pixels,
          width: hdr.width,
          height: hdr.height,
        );
      } else {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        env = await EnvironmentMap.fromUIImages(radianceImage: frame.image);
      }
      _diskEnvCache[path] = env;
      return env;
    } catch (e) {
      lastError.value = 'Failed to load environment "$path": $e';
      return null;
    }
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
    // Prefab sources may be authored `.fscene` text or imported `.fsceneb`
    // binary (a linked glTF asset carries its geometry/texture payloads).
    if (path.endsWith('.fsceneb')) {
      return readFsceneb(await File(path).readAsBytes());
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
