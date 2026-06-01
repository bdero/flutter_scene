// Prebuilt-binary manifest model and download helper for the build hook.
//
// Kept separate from build.dart so the download-and-verify path can be
// unit tested without a full code-asset build or the real package's
// manifest. See hook/build.dart for how these are used.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Parsed contents of hook/native_binaries.json: where the prebuilt
/// libraries for a release live and their expected checksums.
class NativeBinaryManifest {
  NativeBinaryManifest({
    required this.version,
    required this.baseUrl,
    required this.tag,
    required this.binaries,
  });

  /// The package version these binaries were built for.
  final String version;

  /// The download root, e.g. a GitHub releases download URL. The full URL
  /// for an entry is `$baseUrl/$tag/$file`.
  final String baseUrl;

  /// The release tag the binaries are attached to.
  final String tag;

  /// Entries keyed by Rust target triple (e.g. `aarch64-apple-ios`).
  final Map<String, NativeBinaryEntry> binaries;

  /// Parses a decoded JSON map. Throws if a required field is missing or
  /// the wrong type, so a malformed manifest fails loudly at build time.
  static NativeBinaryManifest parse(Map<String, Object?> json) {
    final binaries = <String, NativeBinaryEntry>{};
    final rawBinaries = (json['binaries'] as Map<String, Object?>?) ?? {};
    for (final entry in rawBinaries.entries) {
      final value = entry.value as Map<String, Object?>;
      binaries[entry.key] = NativeBinaryEntry(
        file: value['file'] as String,
        sha256: value['sha256'] as String,
      );
    }
    return NativeBinaryManifest(
      version: json['version'] as String,
      baseUrl: json['base_url'] as String,
      tag: json['tag'] as String,
      binaries: binaries,
    );
  }

  /// Reads and parses the manifest at [file], or returns null if it does
  /// not exist.
  static NativeBinaryManifest? fromFile(File file) {
    if (!file.existsSync()) return null;
    return parse(jsonDecode(file.readAsStringSync()) as Map<String, Object?>);
  }
}

/// One prebuilt library: its file name within the release and its
/// expected sha256 (lower-case hex).
class NativeBinaryEntry {
  NativeBinaryEntry({required this.file, required this.sha256});

  final String file;
  final String sha256;
}

/// Ensures [cacheFile] holds the library at [url] whose contents hash to
/// [expectedSha256], returning [cacheFile].
///
/// Reuses [cacheFile] when it already matches the checksum. Otherwise
/// downloads [url], verifies the checksum (throwing on a mismatch so a
/// tampered or stale binary is never bundled), and writes it. [label] is
/// used only in error messages.
Future<File> downloadVerifiedBinary({
  required Uri url,
  required String expectedSha256,
  required File cacheFile,
  required String label,
}) async {
  if (cacheFile.existsSync() && sha256OfFile(cacheFile) == expectedSha256) {
    return cacheFile;
  }

  cacheFile.parent.createSync(recursive: true);
  final bytes = await _httpGet(url, label);
  final actual = sha256.convert(bytes).toString();
  if (actual != expectedSha256) {
    throw Exception(
      'Checksum mismatch for the prebuilt $label downloaded from $url.\n'
      '  expected: $expectedSha256\n  actual:   $actual\n'
      'Refusing to use a binary that does not match the manifest.',
    );
  }
  cacheFile.writeAsBytesSync(bytes);
  return cacheFile;
}

/// The sha256 (lower-case hex) of [file]'s contents.
String sha256OfFile(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

Future<List<int>> _httpGet(Uri url, String label) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'Downloading the prebuilt $label from $url failed with HTTP '
        '${response.statusCode}.',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}
