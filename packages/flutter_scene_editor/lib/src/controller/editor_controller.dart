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

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

/// Reflects an [EditorSession] into a live [Scene] and back.
class EditorController extends ChangeNotifier {
  EditorController._(this.session, this.scene);

  /// The headless editing session (document, commands, history, selection).
  final EditorSession session;

  /// The live scene the viewport renders.
  final Scene scene;

  final Map<LocalId, Node> _liveById = {};

  /// Opens a controller over [session], realizing its document into a fresh
  /// scene. Async because realization may upload geometry and textures.
  static Future<EditorController> open(EditorSession session) async {
    final controller = EditorController._(session, Scene());
    await controller._realizeAll();
    session.selection.addListener(controller.notifyListeners);
    return controller;
  }

  /// Opens a controller over a new empty document.
  static Future<EditorController> empty() =>
      open(EditorSession(SceneDocument()));

  /// Opens a controller over a document loaded from `.fscene` [source].
  static Future<EditorController> fromFscene(String source) =>
      open(EditorSession.fromFscene(source));

  /// The current selection.
  Selection get selection => session.selection;

  /// Read-only scene-graph queries.
  SceneQuery get query => session.query;

  /// The undo/redo history.
  EditHistory get history => session.history;

  /// The document being edited.
  SceneDocument get document => session.document;

  /// The live node realized from document node [id], or null.
  Node? liveNode(LocalId id) => _liveById[id];

  /// Runs the command named [name] with [params], reflects the resulting
  /// transaction onto the live scene, and notifies listeners. Returns the
  /// committed transaction (its records carry the ids of anything created, so
  /// a multi-step action can chain on them). Surfaces a [CommandException]
  /// (invalid params) to the caller for the UI to show.
  Future<Transaction> run(
    String name, [
    Map<String, Object?> params = const {},
  ]) async {
    final transaction = session.run(name, params);
    await _reflect(transaction);
    notifyListeners();
    return transaction;
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
      final live = _liveById[record.targetId];
      final docNode = document.node(record.targetId);
      if (live == null || docNode == null) continue;
      switch (record.slot) {
        case ChangeSlot.transform:
          live.localTransform = docNode.transform.toMatrix4();
        case ChangeSlot.visible:
          live.visible = docNode.visible;
        case ChangeSlot.layers:
          // Node layers mirror the document node's layer mask.
          live.layers = docNode.layers;
        default:
          break; // name has no effect on the live graph
      }
    }
  }

  Future<void> _realizeAll() async {
    final root = await realizeSceneAsync(document);
    scene.removeAll();
    scene.add(root);
    _liveById.clear();
    _index(root);
  }

  void _index(Node node) {
    final id = nodeFsceneId(node);
    if (id != null) _liveById[id] = node;
    for (final child in node.children) {
      _index(child);
    }
  }

  @override
  void dispose() {
    session.selection.removeListener(notifyListeners);
    scene.removeAll();
    super.dispose();
  }
}
