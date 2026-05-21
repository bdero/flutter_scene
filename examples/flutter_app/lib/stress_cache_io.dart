import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Disk-backed cache for stress-test downloads (native platforms). Keyed by
/// the resource URL; persists across app launches under the application
/// support directory.

Future<Directory> _cacheDir() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/stress_tests');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

String _fileNameForKey(String key) =>
    key.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '_');

Future<File> _fileForKey(String key) async =>
    File('${(await _cacheDir()).path}/${_fileNameForKey(key)}');

/// Returns the cached bytes for [key], or null if absent/empty.
Future<Uint8List?> loadCachedResource(String key) async {
  final file = await _fileForKey(key);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  return bytes.isEmpty ? null : bytes;
}

/// Stores [bytes] for [key].
Future<void> storeCachedResource(String key, Uint8List bytes) async {
  final file = await _fileForKey(key);
  await file.writeAsBytes(bytes, flush: true);
}
