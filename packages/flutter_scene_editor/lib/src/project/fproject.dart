/// The `.fproject` file, an optional committed association between the editor
/// and a Flutter project (a directory with a `pubspec.yaml`), carrying named
/// build configurations. Open project and open scene are independent. The
/// file stores no absolute paths and no per-user state; the selected build
/// configuration lives in editor settings keyed by the project path.
library;

import 'dart:convert';
import 'dart:io';

/// One build/run configuration. The commands are the source of truth for what
/// runs. [mode] drives the `${MODE}` variable, so the Mode dropdown changes
/// behavior without editing command text; the target device is not part of
/// the configuration (it is session state selected in the toolbar, feeding
/// `${DEVICE}` and `${BUILD_TARGET}`).
class BuildConfiguration {
  const BuildConfiguration({
    required this.id,
    required this.name,
    required this.mode,
    required this.buildCommand,
    required this.runCommand,
    this.workingDirectory = '',
  });

  factory BuildConfiguration.fromJson(Map<String, Object?> json) =>
      // A legacy `platform` key is tolerated and dropped (devices replaced
      // per-configuration platforms).
      BuildConfiguration(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        mode: json['mode'] as String? ?? 'debug',
        buildCommand: json['buildCommand'] as String? ?? '',
        runCommand: json['runCommand'] as String? ?? '',
        workingDirectory: json['workingDirectory'] as String? ?? '',
      );

  final String id;
  final String name;

  /// One of debug/profile/release, the `${MODE}` variable's value.
  final String mode;

  final String buildCommand;
  final String runCommand;

  /// The command working directory relative to the project root (variables
  /// substitute here too). Empty runs from the project root.
  final String workingDirectory;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mode': mode,
    'buildCommand': buildCommand,
    'runCommand': runCommand,
    if (workingDirectory.isNotEmpty) 'workingDirectory': workingDirectory,
  };

  BuildConfiguration copyWith({
    String? name,
    String? mode,
    String? buildCommand,
    String? runCommand,
    String? workingDirectory,
  }) => BuildConfiguration(
    id: id,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    buildCommand: buildCommand ?? this.buildCommand,
    runCommand: runCommand ?? this.runCommand,
    workingDirectory: workingDirectory ?? this.workingDirectory,
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

BuildConfiguration buildConfigurationTemplate(String mode) {
  final modeTitle = '${mode[0].toUpperCase()}${mode.substring(1)}';
  return BuildConfiguration(
    id: mode,
    name: modeTitle,
    mode: mode,
    buildCommand: r'${FLUTTER_CLI} build ${BUILD_TARGET} --${MODE}',
    runCommand:
        r'${FLUTTER_CLI} run -d ${DEVICE} --${MODE} '
        r'--enable-flutter-gpu --enable-impeller',
  );
}

/// Default configurations, one per mode, fully variable-driven so the Mode
/// field and the toolbar's device selection change behavior without editing
/// command text. Run templates always carry the Flutter GPU flags
/// flutter_scene needs.
List<BuildConfiguration> defaultBuildConfigurations(String projectRoot) => [
  for (final mode in const ['debug', 'profile', 'release'])
    buildConfigurationTemplate(mode),
];

/// The variables a command (and its working directory) may reference.
/// `DEVICE`/`BUILD_TARGET` appear only when a device is selected, so a
/// command referencing them without one fails with a nameable error.
Map<String, String> commandVariables({
  required String flutterBin,
  required String dartBin,
  required String sdkRoot,
  required String? impellerc,
  required String projectRoot,
  required BuildConfiguration configuration,
  String? deviceId,
  String? buildTarget,
}) => {
  'FLUTTER_CLI': flutterBin,
  'DART_CLI': dartBin,
  'FLUTTER_ROOT': sdkRoot,
  if (impellerc != null) 'IMPELLERC': impellerc,
  'PROJECT_ROOT': projectRoot,
  'MODE': configuration.mode,
  if (deviceId != null) 'DEVICE': deviceId,
  if (buildTarget != null) 'BUILD_TARGET': buildTarget,
};

/// The directory [configuration]'s commands run from, the project root
/// unless the configuration overrides it (relative to the project root,
/// variables substituted; absolute overrides pass through).
String resolveWorkingDirectory(
  FProject project,
  BuildConfiguration configuration,
  Map<String, String> variables,
) {
  final root = project.resolvedProjectRoot;
  final raw = configuration.workingDirectory.trim();
  if (raw.isEmpty) return root;
  final substituted = substituteCommandVariables(raw, variables);
  final absolute =
      substituted.startsWith('/') ||
      (Platform.isWindows && RegExp(r'^[A-Za-z]:').hasMatch(substituted));
  return absolute ? substituted : '$root/$substituted';
}

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
