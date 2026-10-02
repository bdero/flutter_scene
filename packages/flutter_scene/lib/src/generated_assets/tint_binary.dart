/// Finding the `flutter_scene_tint` binary the WGSL sidecar step runs.
///
/// A local build wins when one is named, through `flutter_scene_tint: <path>`
/// under `hooks: user_defines:` or the `FLUTTER_SCENE_TINT` environment
/// variable. Otherwise the binary for this host is downloaded once from the
/// pinned GitHub release (built by `.github/workflows/tint_binaries.yml` from
/// `tools/tint_cli/`), checked against its sha256, and cached.
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

/// The pubspec user-define naming a local `flutter_scene_tint`.
const String kTintUserDefine = 'flutter_scene_tint';

/// Environment override for builders driven directly.
const String kTintEnv = 'FLUTTER_SCENE_TINT';

/// The release the download comes from.
const String kTintReleaseTag = 'flutter_scene_tint-1';

/// Per-host release asset and its sha256.
///
/// TODO(tint-release): fill in from the release's `tint_binaries.json` once
/// `flutter_scene_tint-1` is published. Until then every host needs the local
/// override, and resolution fails with instructions instead of downloading.
const Map<String, ({String file, String sha256})> kTintBinaries = {};

/// Thrown when no usable binary can be found.
final class TintBinaryException implements Exception {
  TintBinaryException(this.message);
  final String message;

  @override
  String toString() => 'TintBinaryException: $message';
}

/// The release's host key for the machine running the hook.
String? tintHostKey([Abi? abi]) => switch (abi ?? Abi.current()) {
  Abi.macosArm64 => 'darwin-arm64',
  Abi.macosX64 => 'darwin-x64',
  Abi.linuxX64 => 'linux-x64',
  Abi.linuxArm64 => 'linux-arm64',
  Abi.windowsX64 => 'windows-x64',
  _ => null,
};

/// Resolves the binary path for [input], downloading it if needed.
Future<String> resolveTintBinary(BuildInput input) async {
  final define = input.userDefines[kTintUserDefine];
  final override = define is String ? define : Platform.environment[kTintEnv];
  if (override != null && override.isNotEmpty) {
    if (!File(override).existsSync()) {
      throw TintBinaryException(
        '$kTintUserDefine names $override, which does not exist',
      );
    }
    return override;
  }

  final host = tintHostKey();
  final entry = host == null ? null : kTintBinaries[host];
  if (entry == null) {
    throw TintBinaryException(
      'no prebuilt flutter_scene_tint for ${host ?? Abi.current()} in '
      '$kTintReleaseTag. Build one with tools/tint_cli/build.sh and name it '
      'with `$kTintUserDefine: <path>` under hooks: user_defines: in the app '
      'pubspec, or turn off flutter_scene_webgpu.',
    );
  }

  final dir = Directory.fromUri(
    input.outputDirectoryShared.resolve('flutter_scene_tint/$kTintReleaseTag/'),
  )..createSync(recursive: true);
  final file = File('${dir.path}${entry.file}');
  if (file.existsSync() && _sha256(file.readAsBytesSync()) == entry.sha256) {
    return file.path;
  }
  final url = Uri.parse(
    'https://github.com/bdero/flutter_scene/releases/download/'
    '$kTintReleaseTag/${entry.file}',
  );
  final bytes = await _download(url);
  final actual = _sha256(bytes);
  if (actual != entry.sha256) {
    throw TintBinaryException(
      'downloaded ${entry.file} has sha256 $actual, expected ${entry.sha256}',
    );
  }
  final partial = File('${file.path}.partial')..writeAsBytesSync(bytes);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', partial.path]);
  }
  partial.renameSync(file.path);
  return file.path;
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

Future<List<int>> _download(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw TintBinaryException('GET $url returned ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    client.close();
  }
}
