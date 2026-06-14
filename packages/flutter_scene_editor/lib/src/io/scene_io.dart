/// Reading and writing `.fscene` files, with native open and save dialogs.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/compose/compose.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';

import '../controller/editor_controller.dart';

const _fsceneTypeGroup = XTypeGroup(
  label: 'flutter_scene',
  extensions: <String>['fscene'],
);

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

/// Reads the `.fscene` at [sourcePath], applies each override in [overrides]
/// to the document (mutating it in place via [applyPrefabOverride]), then
/// writes the updated document back to [sourcePath].
///
/// NOTE this mutates the shared source file so every instance of that prefab
/// will reflect the applied overrides on next load. This is intentional
/// (Unity-style apply semantics). The caller is responsible for clearing the
/// instance overrides after a successful apply so the delta is not doubled.
///
/// Throws an [IOException] when the file cannot be read or written, and a
/// [FsceneFormatException] when the file is malformed.
Future<void> applyOverridesToSource({
  required String sourcePath,
  required List<PropertyOverride> overrides,
}) async {
  if (overrides.isEmpty) return;
  final file = File(sourcePath);
  final source = await file.readAsString();
  final doc = readFscene(source);
  for (final override in overrides) {
    applyPrefabOverride(doc, override);
  }
  await file.writeAsString(writeFscene(doc));
}
