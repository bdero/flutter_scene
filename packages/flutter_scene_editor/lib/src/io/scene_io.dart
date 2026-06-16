/// Reading and writing `.fscene` files, with native open and save dialogs.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/compose/compose.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';

import '../controller/editor_controller.dart';
import 'glb_import_options.dart';

const _fsceneTypeGroup = XTypeGroup(
  label: 'flutter_scene',
  extensions: <String>['fscene'],
);

const _modelTypeGroup = XTypeGroup(
  label: 'glTF model',
  extensions: <String>['glb', 'gltf'],
);

/// Shows the native open dialog filtered to glTF models (`.glb`/`.gltf`), and
/// returns the chosen path, or null when the user cancels.
Future<String?> pickModelPath() async {
  final file = await openFile(acceptedTypeGroups: const [_modelTypeGroup]);
  return file?.path;
}

/// Imports the glTF model at [path] (single-file `.glb` or multi-file `.gltf`
/// with sibling `.bin`/image files) into an editable [SceneDocument].
///
/// For `.gltf`, external resources are read from the file's directory. Throws
/// an [IOException] on read failure and a [FormatException] when a `.gltf`
/// references a resource that cannot be read (for example a sibling file the
/// sandbox did not grant access to).
Future<SceneDocument> importModelDocument(
  String path, {
  bool compressTextures = false,
}) async {
  final bytes = await File(path).readAsBytes();
  if (path.toLowerCase().endsWith('.gltf')) {
    final dir = File(path).parent.path;
    return importGltfToSceneDocument(
      bytes,
      compressTextures: compressTextures,
      resolveUri: (uri) {
        final file = File('$dir${Platform.pathSeparator}$uri');
        return file.existsSync() ? file.readAsBytesSync() : null;
      },
    );
  }
  return importGlbToSceneDocument(bytes, compressTextures: compressTextures);
}

/// Imports the glTF model at [path] into a fresh editable [EditorController].
/// [compressTextures] compresses imported textures; [scale] and [upAxis] apply
/// a non-destructive import transform.
Future<EditorController> importModel(
  String path, {
  bool compressTextures = false,
  double scale = 1.0,
  ImportUpAxis upAxis = ImportUpAxis.yUp,
}) async {
  final document = await importModelDocument(
    path,
    compressTextures: compressTextures,
  );
  return EditorController.fromImportedScene(
    document,
    scale: scale,
    upAxis: upAxis,
    baseDirectory: File(path).parent.path,
  );
}

/// Writes [controller]'s document to a `.fscene` file at [path].
///
/// Throws an [IOException] on write failure.
Future<void> saveFscene(EditorController controller, String path) async {
  await File(path).writeAsString(controller.session.toFscene());
}

/// Reads a `.fscene` file from [path] and returns a fresh [EditorController].
/// The file's directory becomes the base for resolving prefab references.
///
/// Throws an [IOException] on read failure and a [FormatException] on bad JSON.
Future<EditorController> openFscene(String path) async {
  final source = await File(path).readAsString();
  return EditorController.fromFscene(
    source,
    baseDirectory: File(path).parent.path,
  );
}

/// Shows the native open dialog filtered to `.fscene`, and returns the chosen
/// path, or null when the user cancels.
Future<String?> pickOpenPath() async {
  final file = await openFile(acceptedTypeGroups: const [_fsceneTypeGroup]);
  return file?.path;
}

/// Shows the native save dialog, and returns the chosen path, or null when the
/// user cancels.
Future<String?> pickSavePath({String? suggestedName}) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [_fsceneTypeGroup],
    suggestedName: suggestedName ?? 'scene.fscene',
  );
  return location?.path;
}

/// Reads the prefab `.fscene` at [sourcePath], bakes [instance]'s delta into it
/// (overrides, then added and removed nodes), and writes it back.
///
/// NOTE this mutates the shared source file, so every instance of that prefab
/// reflects the change on next load. This is intentional apply semantics. The
/// caller clears the instance's delta after a successful apply so it is not
/// doubled.
///
/// Throws an [IOException] when the file cannot be read or written, and a
/// [FsceneFormatException] when the file is malformed.
Future<void> applyInstanceToSource({
  required String sourcePath,
  required SceneDocument host,
  required PrefabInstanceSpec instance,
}) async {
  final file = File(sourcePath);
  final doc = readFscene(await file.readAsString());
  for (final override in instance.overrides) {
    applyPrefabOverride(doc, override);
  }
  // Remove nodes the instance dropped (and their subtrees).
  for (final removed in instance.removedNodes) {
    _removeSubtree(doc, removed);
  }
  // Copy attached host subtrees into the prefab under their parent (or a root).
  for (final attachment in instance.attachments) {
    final rootSpec = host.nodes[attachment.node];
    if (rootSpec == null) continue;
    _copySubtree(host, doc, attachment.node);
    final parent = attachment.parent;
    if (parent != null && doc.nodes[parent] != null) {
      doc.nodes[parent]!.children.add(attachment.node);
    } else {
      doc.roots.add(attachment.node);
    }
  }
  await file.writeAsString(writeFscene(doc));
}

// Deep-copies the subtree rooted at [id] from [from] into [into] (nodes only;
// shared resources are already in the prefab or referenced by id).
void _copySubtree(SceneDocument from, SceneDocument into, LocalId id) {
  final node = from.nodes[id];
  if (node == null) return;
  into.nodes[id] = node;
  for (final child in node.children) {
    _copySubtree(from, into, child);
  }
}

void _removeSubtree(SceneDocument doc, LocalId root) {
  final node = doc.nodes.remove(root);
  doc.roots.remove(root);
  for (final other in doc.nodes.values) {
    other.children.remove(root);
  }
  if (node != null) {
    for (final child in node.children) {
      _removeSubtree(doc, child);
    }
  }
}
