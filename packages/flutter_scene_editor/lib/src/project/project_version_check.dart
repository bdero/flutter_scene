/// Compares an open project's flutter_scene dependency against the version
/// the editor was built with. Prefers the lockfile's resolved version, falls
/// back to the pubspec constraint, and resolves path dependencies through
/// their own pubspec. Pre-1.0, a differing minor is the breaking boundary
/// (warning); a differing patch is informational.
library;

import 'dart:io';

import '../toolchains/editor_build_info.dart';
import 'fproject.dart';

enum VersionCheckSeverity { ok, info, warning }

class FlutterSceneVersionCheck {
  const FlutterSceneVersionCheck(this.severity, this.message);

  static const ok = FlutterSceneVersionCheck(VersionCheckSeverity.ok, '');

  final VersionCheckSeverity severity;
  final String message;
}

FlutterSceneVersionCheck checkFlutterSceneVersion(
  FProject project,
  EditorBuildInfo editor,
) {
  final editorVersion = editor.flutterSceneVersion;
  if (editorVersion == null) return FlutterSceneVersionCheck.ok;
  final root = project.resolvedProjectRoot;

  String? resolved = _lockedVersion('$root/pubspec.lock');
  String source = 'pubspec.lock';
  if (resolved == null) {
    final (constraint, path) = _pubspecDependency('$root/pubspec.yaml');
    if (path != null) {
      resolved = _pubspecVersion(
        '${Directory('$root/$path').absolute.path}/pubspec.yaml',
      );
      source = 'path dependency';
    } else if (constraint != null) {
      resolved = constraint.replaceFirst('^', '');
      source = 'pubspec.yaml constraint';
    }
  }
  if (resolved == null) {
    return const FlutterSceneVersionCheck(
      VersionCheckSeverity.warning,
      'This project has no flutter_scene dependency, so its scenes will not '
      'render. Add flutter_scene to pubspec.yaml.',
    );
  }

  final projectPair = _majorMinor(resolved);
  final editorPair = _majorMinor(editorVersion);
  if (projectPair == null || editorPair == null) {
    return FlutterSceneVersionCheck.ok;
  }
  if (projectPair != editorPair) {
    return FlutterSceneVersionCheck(
      VersionCheckSeverity.warning,
      'This project uses flutter_scene $resolved (from $source), but the '
      'editor was built with $editorVersion. Scenes and materials may not '
      'load or behave identically. Align the project dependency with the '
      'editor, or use an editor release matching the project.',
    );
  }
  if (resolved != editorVersion) {
    return FlutterSceneVersionCheck(
      VersionCheckSeverity.info,
      'This project uses flutter_scene $resolved (from $source); the editor '
      'was built with $editorVersion (patch difference only).',
    );
  }
  return FlutterSceneVersionCheck.ok;
}

/// `major.minor` of a `major.minor.patch...` string, or null.
(int, int)? _majorMinor(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version.trim());
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// The resolved flutter_scene version in a pubspec.lock, or null.
String? _lockedVersion(String lockPath) {
  final file = File(lockPath);
  if (!file.existsSync()) return null;
  final match = RegExp(
    r'^  flutter_scene:\n(?:^    .*\n){0,8}?^    version:\s*"([^"]+)"',
    multiLine: true,
  ).firstMatch(file.readAsStringSync());
  return match?.group(1);
}

/// The flutter_scene dependency in a pubspec.yaml, as
/// (inline constraint, path) with exactly one non-null on a hit.
(String?, String?) _pubspecDependency(String pubspecPath) {
  final file = File(pubspecPath);
  if (!file.existsSync()) return (null, null);
  final content = file.readAsStringSync();
  final inline = RegExp(
    r'^  flutter_scene:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(content);
  if (inline != null) return (inline.group(1), null);
  final block = RegExp(
    r'^  flutter_scene:\s*\n(?:^    .*\n){0,4}?^    path:\s*(\S+)',
    multiLine: true,
  ).firstMatch(content);
  if (block != null) return (null, block.group(1));
  return (null, null);
}

/// The `version:` field of a pubspec.yaml, or null.
String? _pubspecVersion(String pubspecPath) {
  final file = File(pubspecPath);
  if (!file.existsSync()) return null;
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(file.readAsStringSync());
  return match?.group(1);
}
