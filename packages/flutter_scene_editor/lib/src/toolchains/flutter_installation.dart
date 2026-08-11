/// Flutter installations, named toolchains the editor can select globally.
/// An installation persists only intent (a name, the `flutter` CLI path, an
/// optional impellerc override, whether the editor manages its checkout);
/// identity (version, revision) and health are probed from disk, read-only,
/// so records stay honest when checkouts change underneath them. Probes never
/// launch the `flutter` tool, an unbootstrapped SDK reports an error state
/// with an explicit bootstrap action instead.
library;

import 'dart:convert';
import 'dart:io';

import 'editor_build_info.dart';

/// The engine-artifacts host directories the SDK cache uses. macOS keeps host
/// artifacts under darwin-x64 on every Mac (historical naming); other hosts
/// get their own directory. Same probe set flutter_gpu_shaders uses.
const kEngineHostDirectories = [
  'darwin-x64',
  'linux-x64',
  'linux-arm64',
  'windows-x64',
  'windows-arm64',
];

/// The impellerc inside [sdkRoot]'s artifact cache, or null when absent
/// (missing artifacts, or an SDK that has never run `flutter precache`).
String? impellercForSdkRoot(String sdkRoot) {
  final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';
  for (final host in kEngineHostDirectories) {
    final path = '$sdkRoot/bin/cache/artifacts/engine/$host/$exeName';
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// A persisted installation record.
class FlutterInstallation {
  const FlutterInstallation({
    required this.id,
    required this.name,
    required this.flutterBin,
    this.impellerc,
    this.managed = false,
  });

  factory FlutterInstallation.fromJson(Map<String, Object?> json) =>
      FlutterInstallation(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        flutterBin: json['flutterBin'] as String? ?? '',
        impellerc: json['impellerc'] as String?,
        managed: json['managed'] == true,
      );

  /// A stable identifier (referenced by the global selection).
  final String id;

  /// The user-facing display name.
  final String name;

  /// The `flutter` CLI path (`<sdk>/bin/flutter`).
  final String flutterBin;

  /// An explicit impellerc override (an engine developer's local build), or
  /// null to derive it from the SDK's artifact cache.
  final String? impellerc;

  /// Whether the editor created and owns this checkout under its app data.
  final bool managed;

  /// The SDK root, derived from [flutterBin] (`bin/flutter` -> root).
  String get sdkRoot => File(flutterBin).parent.parent.path;

  /// The `dart` CLI beside [flutterBin].
  String get dartBin =>
      '${File(flutterBin).parent.path}/dart${Platform.isWindows ? '.bat' : ''}';

  /// The impellerc this installation resolves to, honoring the override.
  String? get resolvedImpellerc => impellerc != null && impellerc!.isNotEmpty
      ? impellerc
      : impellercForSdkRoot(sdkRoot);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'flutterBin': flutterBin,
    if (impellerc != null) 'impellerc': impellerc,
    if (managed) 'managed': true,
  };

  FlutterInstallation copyWith({
    String? name,
    String? flutterBin,
    Object? impellerc = _unset,
  }) => FlutterInstallation(
    id: id,
    name: name ?? this.name,
    flutterBin: flutterBin ?? this.flutterBin,
    impellerc: impellerc == _unset ? this.impellerc : impellerc as String?,
    managed: managed,
  );

  static const _unset = Object();
}

/// A read-only identity probe of an installation's checkout.
class InstallationProbe {
  const InstallationProbe({
    this.frameworkVersion,
    this.frameworkRevision,
    this.engineRevision,
    this.engineContentHash,
    this.dartSdkVersion,
    this.repositoryUrl,
    this.bootstrapped = false,
  });

  final String? frameworkVersion;

  /// The checkout's HEAD (from git when available, else the cached
  /// `flutter.version.json`).
  final String? frameworkRevision;
  final String? engineRevision;
  final String? engineContentHash;
  final String? dartSdkVersion;
  final String? repositoryUrl;

  /// Whether the SDK has run its tool at least once (`bin/cache` populated).
  final bool bootstrapped;
}

enum InstallationSeverity { ok, warning, error }

/// The health of an installation, worst severity plus every message.
class InstallationValidation {
  const InstallationValidation(this.severity, this.messages);

  static const ok = InstallationValidation(InstallationSeverity.ok, []);

  final InstallationSeverity severity;
  final List<String> messages;

  String get summary => messages.join('\n');
}

/// Probes and validates installations with per-session caching.
class InstallationInspector {
  InstallationInspector();

  final _probes = <String, (_ProbeStamp, InstallationProbe)>{};

  /// Drops cached probes (a checkout changed underneath us, or the user asked
  /// for a refresh).
  void invalidate([String? flutterBin]) {
    if (flutterBin == null) {
      _probes.clear();
    } else {
      _probes.remove(flutterBin);
    }
  }

  /// Probes [installation]'s checkout, cached until `bin/flutter` or the
  /// version stamp changes.
  Future<InstallationProbe> probe(FlutterInstallation installation) async {
    final bin = installation.flutterBin;
    final stamp = _ProbeStamp.of(installation);
    final cached = _probes[bin];
    if (cached != null && cached.$1 == stamp) return cached.$2;
    final result = await _probe(installation);
    _probes[bin] = (stamp, result);
    return result;
  }

  Future<InstallationProbe> _probe(FlutterInstallation installation) async {
    final root = installation.sdkRoot;
    String? version;
    String? revision;
    String? engineRevision;
    String? engineContentHash;
    String? dartSdkVersion;
    String? repositoryUrl;
    final versionFile = File('$root/bin/cache/flutter.version.json');
    final bootstrapped = versionFile.existsSync();
    if (bootstrapped) {
      try {
        final decoded = jsonDecode(versionFile.readAsStringSync());
        if (decoded is Map) {
          String? read(String key) =>
              decoded[key] is String ? decoded[key] as String : null;
          version = read('frameworkVersion') ?? read('flutterVersion');
          revision = read('frameworkRevision');
          engineRevision = read('engineRevision');
          engineContentHash = read('engineContentHash');
          dartSdkVersion = read('dartSdkVersion');
          repositoryUrl = read('repositoryUrl');
        }
      } catch (_) {
        // A malformed stamp only degrades identity.
      }
    }
    // git is authoritative for the revision; the cached stamp can lag a
    // checkout switch.
    if (Directory('$root/.git').existsSync()) {
      try {
        final head = await Process.run('git', [
          '-C',
          root,
          'rev-parse',
          'HEAD',
        ]);
        if (head.exitCode == 0) {
          final sha = '${head.stdout}'.trim();
          if (sha.isNotEmpty) {
            if (revision != null && revision != sha) {
              // Stale stamp; the version string no longer describes HEAD.
              version = null;
            }
            revision = sha;
          }
        }
      } catch (_) {
        // No git on PATH; the stamp value stands.
      }
    }
    return InstallationProbe(
      frameworkVersion: version,
      frameworkRevision: revision,
      engineRevision: engineRevision,
      engineContentHash: engineContentHash,
      dartSdkVersion: dartSdkVersion,
      repositoryUrl: repositoryUrl,
      bootstrapped: bootstrapped,
    );
  }

  /// Validates [installation] against the editor's own build identity.
  Future<InstallationValidation> validate(
    FlutterInstallation installation,
    EditorBuildInfo editor,
  ) async {
    final errors = <String>[];
    final warnings = <String>[];
    final bin = File(installation.flutterBin);
    if (installation.flutterBin.isEmpty || !bin.existsSync()) {
      errors.add(
        'The flutter CLI was not found at "${installation.flutterBin}".',
      );
      return InstallationValidation(InstallationSeverity.error, errors);
    }
    final probe = await this.probe(installation);
    final override = installation.impellerc;
    if (override != null &&
        override.isNotEmpty &&
        !File(override).existsSync()) {
      errors.add('The impellerc override was not found at "$override".');
    } else if (installation.resolvedImpellerc == null) {
      errors.add(
        probe.bootstrapped
            ? 'impellerc is missing from this SDK\'s artifact cache. Run '
                  'flutter precache for it (Bootstrap).'
            : 'This SDK has not been bootstrapped (no bin/cache). Run '
                  'Bootstrap to download its Dart SDK and engine artifacts.',
      );
    }
    if (errors.isNotEmpty) {
      return InstallationValidation(InstallationSeverity.error, errors);
    }
    if (editor.isKnown &&
        probe.frameworkRevision != null &&
        probe.frameworkRevision != editor.frameworkRevision) {
      warnings.add(
        'This installation is Flutter '
        '${probe.frameworkVersion ?? 'unknown version'} '
        '(${_short(probe.frameworkRevision)}), but the editor was built with '
        '${editor.frameworkVersion ?? 'unknown version'} '
        '(${_short(editor.frameworkRevision)}). Shader compiles and engine '
        'behavior may differ, and a diverged impellerc may produce shader '
        'bundles this editor cannot load.',
      );
    }
    if (warnings.isNotEmpty) {
      return InstallationValidation(InstallationSeverity.warning, warnings);
    }
    return InstallationValidation.ok;
  }

  static String _short(String? sha) =>
      sha == null ? '?' : (sha.length > 10 ? sha.substring(0, 10) : sha);
}

class _ProbeStamp {
  const _ProbeStamp(this.binModified, this.stampModified);

  final int binModified;
  final int stampModified;

  static _ProbeStamp of(FlutterInstallation installation) {
    int mtime(String path) {
      try {
        return File(path).statSync().modified.microsecondsSinceEpoch;
      } on FileSystemException {
        return -1;
      }
    }

    return _ProbeStamp(
      mtime(installation.flutterBin),
      mtime('${installation.sdkRoot}/bin/cache/flutter.version.json'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ProbeStamp &&
      other.binModified == binModified &&
      other.stampModified == stampModified;

  @override
  int get hashCode => Object.hash(binModified, stampModified);
}
