/// The `.fproject` file, an optional committed association between the editor
/// and a Flutter project (a directory with a `pubspec.yaml`), carrying named
/// build configurations. Open project and open scene are independent. The
/// file stores no absolute paths and no per-user state; the selected build
/// configuration lives in editor settings keyed by the project path.
library;

import 'dart:convert';
import 'dart:io';

/// Parameters for the editor-owned run session (`flutter run --machine`).
///
/// Run is not a free-form command; the editor composes the invocation so it
/// can own the machine protocol (structured progress, hot restart, stop).
/// [args] are extra `flutter run` arguments appended after the editor's own
/// (device, mode, target); each token is variable-substituted like command
/// templates. Free-form automation belongs in a [ProjectTask].
class RunParameters {
  const RunParameters({this.target = defaultTarget, this.args = const []});

  factory RunParameters.fromJson(Map<String, Object?> json) => RunParameters(
    target: json['target'] as String? ?? defaultTarget,
    args: [
      if (json['args'] is List)
        for (final arg in json['args'] as List)
          if (arg is String) arg,
    ],
  );

  static const String defaultTarget = 'lib/main.dart';

  /// The entrypoint passed as `--target`, relative to the working directory.
  final String target;

  /// Extra `flutter run` arguments (variable-substituted per token).
  final List<String> args;

  Map<String, Object?> toJson() => {
    if (target != defaultTarget) 'target': target,
    if (args.isNotEmpty) 'args': args,
  };

  RunParameters copyWith({String? target, List<String>? args}) =>
      RunParameters(target: target ?? this.target, args: args ?? this.args);
}

/// A named free-form command template, run as a raw subprocess with Console
/// streaming and no app lifecycle (the escape hatch custom run commands
/// migrate into).
class ProjectTask {
  const ProjectTask({
    required this.id,
    required this.name,
    required this.command,
  });

  factory ProjectTask.fromJson(Map<String, Object?> json) => ProjectTask(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    command: json['command'] as String? ?? '',
  );

  final String id;
  final String name;
  final String command;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'command': command};

  ProjectTask copyWith({String? name, String? command}) => ProjectTask(
    id: id,
    name: name ?? this.name,
    command: command ?? this.command,
  );
}

/// One build/run configuration. [buildCommand] is a free-form template; run
/// is structured (see [RunParameters]). [mode] drives the `${MODE}` variable
/// and the session's `--mode` flag; the target device is not part of the
/// configuration (it is session state selected in the toolbar, feeding
/// `${DEVICE}` and `${BUILD_TARGET}`).
class BuildConfiguration {
  const BuildConfiguration({
    required this.id,
    required this.name,
    required this.mode,
    required this.buildCommand,
    this.run = const RunParameters(),
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
        run: json['run'] is Map
            ? RunParameters.fromJson(
                (json['run'] as Map).cast<String, Object?>(),
              )
            : const RunParameters(),
        workingDirectory: json['workingDirectory'] as String? ?? '',
      );

  final String id;
  final String name;

  /// One of debug/profile/release, the `${MODE}` variable's value.
  final String mode;

  final String buildCommand;

  /// Parameters for the editor-owned run session.
  final RunParameters run;

  /// The command working directory relative to the project root (variables
  /// substitute here too). Empty runs from the project root.
  final String workingDirectory;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mode': mode,
    'buildCommand': buildCommand,
    if (run.toJson().isNotEmpty) 'run': run.toJson(),
    if (workingDirectory.isNotEmpty) 'workingDirectory': workingDirectory,
  };

  BuildConfiguration copyWith({
    String? name,
    String? mode,
    String? buildCommand,
    RunParameters? run,
    String? workingDirectory,
  }) => BuildConfiguration(
    id: id,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    buildCommand: buildCommand ?? this.buildCommand,
    run: run ?? this.run,
    workingDirectory: workingDirectory ?? this.workingDirectory,
  );
}

/// A loaded `.fproject`.
class FProject {
  FProject({
    required this.path,
    required this.flutterProjectRoot,
    required List<BuildConfiguration> buildConfigurations,
    List<ProjectTask> tasks = const [],
    this.defaultScene,
  }) : buildConfigurations = List.of(buildConfigurations),
       tasks = List.of(tasks);

  static const int currentVersion = 2;

  /// The absolute `.fproject` file path.
  final String path;

  /// The directory containing `pubspec.yaml`, relative to the file.
  String flutterProjectRoot;

  final List<BuildConfiguration> buildConfigurations;

  /// Free-form command templates runnable from the toolbar's configuration
  /// menu (raw subprocesses, no app lifecycle).
  final List<ProjectTask> tasks;

  /// The committed scene a fresh checkout opens to, relative to the project
  /// root, or null. A per-user last-opened scene (editor settings) wins over
  /// this when present.
  String? defaultScene;

  /// [defaultScene] resolved to an absolute path, or null.
  String? get resolvedDefaultScene {
    final scene = defaultScene;
    if (scene == null || scene.isEmpty) return null;
    if (scene.startsWith('/')) return scene;
    return '$resolvedProjectRoot/$scene';
  }

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
    final configurations = <BuildConfiguration>[];
    final tasks = <ProjectTask>[
      if (json['tasks'] is List)
        for (final entry in json['tasks'] as List)
          if (entry is Map) ProjectTask.fromJson(entry.cast<String, Object?>()),
    ];
    if (json['buildConfigurations'] is List) {
      for (final entry in json['buildConfigurations'] as List) {
        if (entry is! Map) continue;
        final configJson = entry.cast<String, Object?>();
        final config = BuildConfiguration.fromJson(configJson);
        if (version.toInt() < 2 && configJson['runCommand'] is String) {
          final migrated = migrateV1RunCommand(
            configJson['runCommand'] as String,
            configId: config.id,
            configName: config.name,
          );
          configurations.add(config.copyWith(run: migrated.run));
          if (migrated.task != null) tasks.add(migrated.task!);
        } else {
          configurations.add(config);
        }
      }
    }
    return FProject(
      path: absolute,
      flutterProjectRoot: json['flutterProjectRoot'] as String? ?? '.',
      buildConfigurations: configurations,
      tasks: tasks,
      defaultScene: json['defaultScene'] as String?,
    );
  }

  ProjectTask? taskById(String? id) {
    if (id == null) return null;
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void save() {
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'version': currentVersion,
      'flutterProjectRoot': flutterProjectRoot,
      if (defaultScene case final scene? when scene.isNotEmpty)
        'defaultScene': scene,
      'buildConfigurations': [
        for (final config in buildConfigurations) config.toJson(),
      ],
      if (tasks.isNotEmpty) 'tasks': [for (final task in tasks) task.toJson()],
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

/// What ancestor-directory discovery found for a scene, the nearest
/// `.fproject` when one exists, and otherwise the nearest directory with a
/// `pubspec.yaml` (the candidate for offering project initialization).
typedef SceneProjectContext = ({
  String? fprojectPath,
  String? pubspecDirectory,
});

/// Walks up from [scenePath]'s directory looking for a `.fproject`, so a
/// scene opened on its own lands in its project's context. The nearest
/// project file wins (with several in one directory, one named after the
/// directory is preferred, then the lexicographically first). The walk stops
/// after [stopAtDirectory] (default the user's home directory, so a stray
/// project file near the filesystem root cannot capture everything; paths
/// outside home walk to the root).
SceneProjectContext findSceneProjectContext(
  String scenePath, {
  String? stopAtDirectory,
}) {
  final stopAt = Directory(
    stopAtDirectory ?? Platform.environment['HOME'] ?? '/',
  ).absolute.path.replaceAll(RegExp(r'[/\\]$'), '');
  String? pubspecDirectory;
  var dir = File(scenePath).absolute.parent;
  for (var depth = 0; depth < 64; depth++) {
    final dirPath = dir.path.replaceAll(RegExp(r'[/\\]$'), '');
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      break;
    }
    final candidates =
        entries
            .whereType<File>()
            .where((f) => f.path.endsWith('.fproject'))
            .map((f) => f.path)
            .toList()
          ..sort();
    if (candidates.isNotEmpty) {
      final dirName = dirPath.replaceAll('\\', '/').split('/').last;
      final preferred = '$dirPath/$dirName.fproject';
      return (
        fprojectPath: candidates.contains(preferred)
            ? preferred
            : candidates.first,
        pubspecDirectory: null,
      );
    }
    if (pubspecDirectory == null &&
        entries.whereType<File>().any(
          (f) => f.path.endsWith('/pubspec.yaml'),
        )) {
      pubspecDirectory = dirPath;
    }
    if (dirPath == stopAt || dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return (fprojectPath: null, pubspecDirectory: pubspecDirectory);
}

BuildConfiguration buildConfigurationTemplate(String mode) {
  final modeTitle = '${mode[0].toUpperCase()}${mode.substring(1)}';
  return BuildConfiguration(
    id: mode,
    name: modeTitle,
    mode: mode,
    buildCommand: r'${FLUTTER_CLI} build ${BUILD_TARGET} --${MODE}',
    run: const RunParameters(
      args: ['--enable-flutter-gpu', '--enable-impeller'],
    ),
  );
}

/// Default configurations, one per mode, fully variable-driven so the Mode
/// field and the toolbar's device selection change behavior without editing
/// command text. Run arguments always carry the Flutter GPU flags
/// flutter_scene needs.
List<BuildConfiguration> defaultBuildConfigurations(String projectRoot) => [
  for (final mode in const ['debug', 'profile', 'release'])
    buildConfigurationTemplate(mode),
];

/// A v1 `runCommand` converted to the v2 model, structured [run] parameters
/// when the command has the editor-composable shape, and otherwise a
/// preserved [task] alongside default run parameters so nothing is lost.
typedef MigratedRunCommand = ({RunParameters run, ProjectTask? task});

/// Converts a v1 free-form `runCommand` template.
///
/// A command of the shape `${FLUTTER_CLI} run ...` whose tokens are all
/// expressible as run parameters (`-d ${DEVICE}`, `--${MODE}` or the literal
/// mode flags, `--target`, plus arbitrary `-`/`--` flags) becomes
/// [RunParameters]. Anything else (a different executable, a hardcoded
/// device, positional arguments) is preserved verbatim as a [ProjectTask].
MigratedRunCommand migrateV1RunCommand(
  String runCommand, {
  required String configId,
  required String configName,
}) {
  ProjectTask asTask() => ProjectTask(
    id: '$configId-run',
    name: '$configName run (migrated)',
    command: runCommand,
  );
  final fallback = buildConfigurationTemplate('debug').run;
  final tokens = tokenizeCommand(runCommand.trim());
  if (tokens.length < 2 ||
      tokens[0] != r'${FLUTTER_CLI}' ||
      tokens[1] != 'run') {
    return (run: fallback, task: tokens.isEmpty ? null : asTask());
  }
  var target = RunParameters.defaultTarget;
  final args = <String>[];
  const modeFlags = ['--\${MODE}', '--debug', '--profile', '--release'];
  for (var i = 2; i < tokens.length; i++) {
    final token = tokens[i];
    if (token == '-d' || token == '--device-id') {
      if (i + 1 < tokens.length && tokens[i + 1] == r'${DEVICE}') {
        i++;
        continue;
      }
      return (run: fallback, task: asTask());
    }
    if (modeFlags.contains(token)) continue;
    if (token == '--target' || token == '-t') {
      if (i + 1 >= tokens.length) return (run: fallback, task: asTask());
      target = tokens[++i];
      continue;
    }
    if (token.startsWith('--target=')) {
      target = token.substring('--target='.length);
      continue;
    }
    if (!token.startsWith('-')) return (run: fallback, task: asTask());
    args.add(token);
  }
  return (run: RunParameters(target: target, args: args), task: null);
}

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
