import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.bdero.smoke_render/android_manifest');

Future<Directory>? _dir;

/// Writes [png] to `<filesDir>/smoke/<name>` on Android as soon as it renders.
///
/// CI launches the app without a host driver and pulls this directory with
/// `run-as`, so a run that dies late keeps what it drew.
Future<void> storeCapture(String name, Uint8List png) async {
  if (!Platform.isAndroid) return;
  final dir = await (_dir ??= _open());
  // Rename into place so a pull mid-write never sees a partial file.
  final tmp = File('${dir.path}/$name.tmp');
  await tmp.writeAsBytes(png, flush: true);
  await tmp.rename('${dir.path}/$name');
}

/// Whether scene [id] passed in an earlier attempt of this CI run, which
/// leaves the app installed and its storage in place between attempts.
Future<bool> alreadyPassed(String id) async {
  if (!Platform.isAndroid) return false;
  final dir = await (_dir ??= _open());
  return File('${dir.path}/$id.passed').exists();
}

/// Records that scene [id] rendered and passed every check, so a retry after
/// a later failure skips it.
Future<void> markPassed(String id) async {
  if (!Platform.isAndroid) return;
  final dir = await (_dir ??= _open());
  await File('${dir.path}/$id.passed').create();
}

/// Records how many tests have finished, which CI polls to tell a slow run
/// from a stalled one.
Future<void> recordFinishedTests(int count) async {
  if (!Platform.isAndroid) return;
  final dir = await (_dir ??= _open());
  await File('${dir.path}/progress').writeAsString('$count', flush: true);
}

/// Writes the suite's verdict, `passed` or `failed` on the first line and then
/// each failure, which CI reads in place of a host driver's report so a lost
/// connection to the app cannot change the outcome.
Future<void> storeSummary(bool passed, Map<String, String> failures) async {
  if (!Platform.isAndroid) return;
  final dir = await (_dir ??= _open());
  final text = StringBuffer(passed ? 'passed' : 'failed');
  failures.forEach((test, details) => text.write('\n\n$test\n$details'));
  final tmp = File('${dir.path}/summary.tmp');
  await tmp.writeAsString('$text\n', flush: true);
  await tmp.rename('${dir.path}/summary');
}

Future<Directory> _open() async {
  final files = await _channel.invokeMethod<String>('getFilesDir');
  return Directory('$files/smoke').create(recursive: true);
}
