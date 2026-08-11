/// The `.fproject` file, an optional committed association between the editor
/// and a Flutter project (a directory with a `pubspec.yaml`), carrying named
/// build configurations. Open project and open scene are independent. The
/// file stores no absolute paths and no per-user state; the selected build
/// configuration lives in editor settings keyed by the project path.
library;

import 'dart:convert';
import 'dart:io';

/// One build/run configuration. The commands are the source of truth for what
/// runs; [platform] and [mode] are advisory metadata for display grouping and
/// template regeneration.
class BuildConfiguration {
  const BuildConfiguration({
    required this.id,
    required this.name,
    required this.platform,
    required this.mode,
    required this.buildCommand,
    required this.runCommand,
  });

  factory BuildConfiguration.fromJson(Map<String, Object?> json) =>
      BuildConfiguration(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        platform: json['platform'] as String? ?? 'macos',
        mode: json['mode'] as String? ?? 'debug',
        buildCommand: json['buildCommand'] as String? ?? '',
        runCommand: json['runCommand'] as String? ?? '',
      );

  final String id;
  final String name;

  /// One of macos/ios/android/linux/windows/web.
  final String platform;

  /// One of debug/profile/release.
  final String mode;

  final String buildCommand;
  final String runCommand;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'mode': mode,
    'buildCommand': buildCommand,
    'runCommand': runCommand,
  };

  BuildConfiguration copyWith({
    String? name,
    String? platform,
    String? mode,
    String? buildCommand,
    String? runCommand,
  }) => BuildConfiguration(
    id: id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    mode: mode ?? this.mode,
    buildCommand: buildCommand ?? this.buildCommand,
    runCommand: runCommand ?? this.runCommand,
  );
}

/// A loaded `.fproject`.
class FProject {
  FProject({
    required this.path,
    required this.flutterProjectRoot,
    required List<BuildConfiguration> buildConfigurations,
  }) : buildConfigurations = List.of(buildConfigurations);

  static const int currentVersion = 1;

  /// The absolute `.fproject` file path.
  final String path;

  /// The directory containing `pubspec.yaml`, relative to the file.
  String flutterProjectRoot;

  final List<BuildConfiguration> buildConfigurations;

  String get name {
    final base = path.replaceAll('\\', '/').split('/').last;
    return base.endsWith('.fproject')
        ? base.substring(0, base.length - '.fproject'.length)
        : base;
  }

  /// The absolute Flutter project root (the run/build working directory).
  String get resolvedProjectRoot {
    final dir = File(path).parent.uri;
    return Directory.fromUri(
      dir.resolve(flutterProjectRoot.isEmpty ? '.' : flutterProjectRoot),
    ).path.replaceAll(RegExp(r'[/\\]$'), '');
  }

  BuildConfiguration? configurationById(String? id) {
    if (id == null) return null;
    for (final config in buildConfigurations) {
      if (config.id == id) return config;
    }
    return null;
  }

  static FProject load(String path) {
    final absolute = File(path).absolute.path;
    final decoded = jsonDecode(File(absolute).readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('Malformed .fproject file');
    }
    final json = decoded.cast<String, Object?>();
    final version = json['version'];
    if (version is! num || version.toInt() > currentVersion) {
      throw const FormatException('Unsupported .fproject version');
    }
    return FProject(
      path: absolute,
      flutterProjectRoot: json['flutterProjectRoot'] as String? ?? '.',
      buildConfigurations: [
        if (json['buildConfigurations'] is List)
          for (final entry in json['buildConfigurations'] as List)
            if (entry is Map)
              BuildConfiguration.fromJson(entry.cast<String, Object?>()),
      ],
    );
  }

  void save() {
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'version': currentVersion,
      'flutterProjectRoot': flutterProjectRoot,
      'buildConfigurations': [
        for (final config in buildConfigurations) config.toJson(),
      ],
    });
    final file = File(path);
    final temporary = File('$path.tmp');
    temporary.writeAsStringSync(encoded, flush: true);
    temporary.renameSync(file.path);
  }

  /// Creates `<dirname>.fproject` next to [projectRoot]'s pubspec with
  /// defaults for the platforms whose scaffolding exists. Throws a
  /// [FormatException] when the directory has no `pubspec.yaml`.
  static FProject createDefault(String projectRoot) {
    final root = Directory(
      projectRoot,
    ).absolute.path.replaceAll(RegExp(r'[/\\]$'), '');
    if (!File('$root/pubspec.yaml').existsSync()) {
      throw const FormatException(
        'The directory has no pubspec.yaml; an fproject wraps an existing '
        'Flutter project.',
      );
    }
    final dirName = root.replaceAll('\\', '/').split('/').last;
    final project = FProject(
      path: '$root/$dirName.fproject',
      flutterProjectRoot: '.',
      buildConfigurations: defaultBuildConfigurations(root),
    );
    project.save();
    return project;
  }
}

String get _hostPlatform => Platform.isMacOS
    ? 'macos'
    : Platform.isWindows
    ? 'windows'
    : 'linux';

String _buildTarget(String platform) =>
    platform == 'android' ? 'apk' : platform;

String _runDevice(String platform) => platform == 'web' ? 'chrome' : platform;

BuildConfiguration _template(String platform, String mode) {
  final title = platform == 'ios'
      ? 'iOS'
      : platform == 'macos'
      ? 'macOS'
      : '${platform[0].toUpperCase()}${platform.substring(1)}';
  final modeTitle = '${mode[0].toUpperCase()}${mode.substring(1)}';
  return BuildConfiguration(
    id: '$platform-$mode',
    name: '$title $modeTitle',
    platform: platform,
    mode: mode,
    buildCommand: '\${FLUTTER_CLI} build ${_buildTarget(platform)} --$mode',
    runCommand:
        '\${FLUTTER_CLI} run -d ${_runDevice(platform)} --$mode '
        '--enable-flutter-gpu --enable-impeller',
  );
}

/// Default configurations for [projectRoot], the host desktop platform in
/// every mode plus a debug config per other platform with scaffolding
/// present. Run templates always carry the Flutter GPU flags flutter_scene
/// needs.
List<BuildConfiguration> defaultBuildConfigurations(String projectRoot) {
  final configs = <BuildConfiguration>[];
  final host = _hostPlatform;
  if (Directory('$projectRoot/$host').existsSync()) {
    for (final mode in const ['debug', 'profile', 'release']) {
      configs.add(_template(host, mode));
    }
  }
  for (final platform in const [
    'macos',
    'ios',
    'android',
    'linux',
    'windows',
    'web',
  ]) {
    if (platform == host) continue;
    if (!Directory('$projectRoot/$platform').existsSync()) continue;
    configs.add(_template(platform, 'debug'));
  }
  if (configs.isEmpty) {
    // No scaffolding at all; offer the host defaults anyway so the list is
    // never empty (flutter create can add the platform later).
    for (final mode in const ['debug', 'profile', 'release']) {
      configs.add(_template(host, mode));
    }
  }
  return configs;
}

/// The variables a build/run command may reference. Substitution applies to
/// the two command fields only.
Map<String, String> commandVariables({
  required String flutterBin,
  required String dartBin,
  required String sdkRoot,
  required String? impellerc,
  required String projectRoot,
  required BuildConfiguration configuration,
}) => {
  'FLUTTER_CLI': flutterBin,
  'DART_CLI': dartBin,
  'FLUTTER_ROOT': sdkRoot,
  if (impellerc != null) 'IMPELLERC': impellerc,
  'PROJECT_ROOT': projectRoot,
  'MODE': configuration.mode,
  'PLATFORM': configuration.platform,
};

/// Replaces `${NAME}` references with [variables]. An unknown variable throws
/// a [FormatException] naming it (a silent empty expansion hides typos).
String substituteCommandVariables(
  String command,
  Map<String, String> variables,
) {
  return command.replaceAllMapped(RegExp(r'\$\{([A-Z_]+)\}'), (match) {
    final name = match.group(1)!;
    final value = variables[name];
    if (value == null) {
      throw FormatException('Unknown command variable \${$name}');
    }
    return value;
  });
}

/// Splits a substituted command into argv, whitespace-separated with
/// double-quote grouping (no shell).
List<String> tokenizeCommand(String command) {
  final tokens = <String>[];
  final current = StringBuffer();
  var quoted = false;
  var any = false;
  for (var i = 0; i < command.length; i++) {
    final char = command[i];
    if (char == '"') {
      quoted = !quoted;
      any = true;
      continue;
    }
    if (!quoted && (char == ' ' || char == '\t')) {
      if (any || current.isNotEmpty) {
        tokens.add(current.toString());
        current.clear();
        any = false;
      }
      continue;
    }
    current.write(char);
  }
  if (any || current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}
