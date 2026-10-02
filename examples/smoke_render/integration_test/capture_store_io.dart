import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.bdero.smoke_render/android_manifest');

Future<Directory>? _dir;

/// Writes [png] to `<filesDir>/smoke/<name>` on Android as soon as it renders.
///
/// The host driver otherwise receives every frame in one report at the end, so
/// a run that dies late (a killed drive, a dropped adb transport) would lose
/// them all. CI pulls this directory with `run-as` after each attempt.
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

Future<Directory> _open() async {
  final files = await _channel.invokeMethod<String>('getFilesDir');
  return Directory('$files/smoke').create(recursive: true);
}
