/// Reading and writing `.fscene` files, with native open and save dialogs.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';

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
///
/// Throws an [IOException] on read failure and a [FormatException] on bad JSON.
Future<EditorController> openFscene(String path) async {
  final source = await File(path).readAsString();
  return EditorController.fromFscene(source);
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
