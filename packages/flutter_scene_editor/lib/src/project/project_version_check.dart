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
    final (:constraint, :path, :present) = _pubspecDependency(
      '$root/pubspec.yaml',
    );
    if (path != null) {
      resolved = _pubspecVersion(
        '${Directory('$root/$path').absolute.path}/pubspec.yaml',
      );
      source = 'path dependency';
    } else if (constraint != null) {
      resolved = constraint.replaceFirst('^', '');
      source = 'pubspec.yaml constraint';
    } else if (present) {
      // A git/hosted/sdk block dependency carries no version to compare
      // without a lockfile; that is not a missing dependency.
      return FlutterSceneVersionCheck.ok;
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
    r'^  flutter_scene:\r?\n(?:^    .*\r?\n){0,8}?^    version:\s*"([^"]+)"',
    multiLine: true,
  ).firstMatch(file.readAsStringSync());
  return match?.group(1);
}

/// The flutter_scene dependency in a pubspec.yaml. At most one of
/// [constraint]/[path] is non-null; [present] is true whenever the
/// dependency key exists in any form (including git/hosted blocks).
({String? constraint, String? path, bool present}) _pubspecDependency(
  String pubspecPath,
) {
  final file = File(pubspecPath);
  if (!file.existsSync()) return (constraint: null, path: null, present: false);
  final content = file.readAsStringSync();
  final present = RegExp(
    r'^  flutter_scene:',
    multiLine: true,
  ).hasMatch(content);
  final inline = RegExp(
    r'^  flutter_scene:[ \t]*([^\s#]+)[ \t]*\r?$',
    multiLine: true,
  ).firstMatch(content);
  if (inline != null) {
    return (constraint: inline.group(1), path: null, present: present);
  }
  final block = RegExp(
    r'^  flutter_scene:\s*\r?\n(?:^    .*\r?\n){0,4}?^    path:\s*(\S+)',
    multiLine: true,
  ).firstMatch(content);
  if (block != null) {
    return (constraint: null, path: block.group(1), present: present);
  }
  return (constraint: null, path: null, present: present);
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
