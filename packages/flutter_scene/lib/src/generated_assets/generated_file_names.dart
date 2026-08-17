/// Hashing and file naming for the generated tree. Hook-only: the 64-bit FNV
/// constants cannot be represented in JavaScript, and the runtime never needs
/// them (it reads each output's name from the manifest).
library;

import 'dart:convert';

import 'generated_assets.dart';

/// 64-bit FNV-1a over [bytes].
///
/// Hooks always run on the native VM, where Dart ints carry the full 64 bits;
/// the multiply wraps into the sign bit, which the hex formatters below undo.
int fnv1a(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash ^= b;
    hash *= 0x100000001b3;
  }
  return hash;
}

/// [fnv1a] as 16 unsigned hex digits.
String fnv1aHex(List<int> bytes) {
  final hash = fnv1a(bytes);
  final high = (hash >> 32) & 0xFFFFFFFF;
  final low = hash & 0xFFFFFFFF;
  return '${high.toRadixString(16).padLeft(8, '0')}'
      '${low.toRadixString(16).padLeft(8, '0')}';
}

/// A short unsigned hex tag for [text], the two halves of its 64-bit hash
/// folded together so both ends of the input reach every digit.
String shortHash(String text) {
  final hash = fnv1a(utf8.encode(text));
  final folded = ((hash >> 32) ^ hash) & 0xFFFFFFFF;
  return folded.toRadixString(16).padLeft(8, '0');
}

/// The longest readable stem kept in a generated file name.
const int _maxStemLength = 48;

/// The generated file name for [nameId] within [family], with [extension]
/// (which includes the leading dot).
///
/// The tree is flat, since `flutter.assets` directory entries are not
/// recursive, so a source path's directories collapse into a hash tag rather
/// than nested output directories. The readable stem keeps the directory
/// browsable and the tag keeps two same-named sources apart.
///
/// [variant] changes the file name without changing the id the manifest maps,
/// so outputs that are only valid for one toolchain (an engine-compiled shader
/// bundle) cannot collide when two builds share a directory.
String generatedFileName(
  GeneratedAssetFamily family,
  String nameId,
  String extension, {
  String? variant,
}) {
  final slash = nameId.lastIndexOf('/');
  final rawStem = slash < 0 ? nameId : nameId.substring(slash + 1);
  var stem = rawStem.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
  if (stem.isEmpty) stem = 'asset';
  if (stem.length > _maxStemLength) stem = stem.substring(0, _maxStemLength);
  final key = variant == null
      ? '${family.name}/$nameId'
      : '${family.name}/$nameId@$variant';
  return '${family.prefix}.$stem.${shortHash(key)}$extension';
}

/// Whether [fileName] looks like a [generatedFileName] output, so a sweep of
/// the tree only ever deletes files the hooks produced.
bool isGeneratedFileName(String fileName) =>
    _generatedFileNamePattern.hasMatch(fileName);

final RegExp _generatedFileNamePattern = RegExp(
  '^(${GeneratedAssetFamily.values.map((f) => f.prefix).join('|')})'
  r'\.[A-Za-z0-9_\-]+\.[0-9a-f]{8}\..+$',
);

/// [fileName] with its hash tag removed, identifying every variant of one
/// generated output, or null when it is not a generated name.
String? generatedNameWithoutTag(String fileName) {
  final match = _generatedFileNamePattern.firstMatch(fileName);
  if (match == null) return null;
  final parts = fileName.split('.');
  // `<prefix>.<stem>.<tag>.<extension...>`, so the tag is the third field.
  return [...parts.sublist(0, 2), ...parts.sublist(3)].join('.');
}
