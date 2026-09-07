import 'dart:convert';
import 'dart:io';

import '../toolchains/flutter_installation.dart';

/// Persisted editor preferences shared across documents.
class EditorSettings {
  EditorSettings({
    this.workspace,
    List<String>? recentScenes,
    List<FlutterInstallation>? flutterInstallations,
    this.selectedInstallationId,
    List<String>? recentProjects,
    Map<String, String>? selectedBuildConfigurations,
    Map<String, String>? selectedDevices,
    Map<String, bool>? restartOnSceneSave,
    Map<String, String>? lastScenes,
    String? editorCommand,
    this.gizmosEnabled = true,
    this.giProbesVisible = false,
    Set<String>? hiddenGizmoTypes,
  }) : hiddenGizmoTypes = Set.of(hiddenGizmoTypes ?? const {}),
       editorCommand = editorCommand ?? defaultEditorCommand,
       recentScenes = List.of(recentScenes ?? const []),
       flutterInstallations = List.of(flutterInstallations ?? const []),
       recentProjects = List.of(recentProjects ?? const []),
       selectedBuildConfigurations = Map.of(
         selectedBuildConfigurations ?? const {},
       ),
       selectedDevices = Map.of(selectedDevices ?? const {}),
       restartOnSceneSave = Map.of(restartOnSceneSave ?? const {}),
       lastScenes = Map.of(lastScenes ?? const {});

  static const int currentVersion = 1;
  static const int maximumRecentScenes = 10;
  static const int maximumRecentProjects = 10;

  /// The out-of-the-box source-editor launch command (VS Code's CLI).
  static const String defaultEditorCommand = 'code \${SOURCE_FILE}';

  factory EditorSettings.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Malformed editor settings');
    }
    final json = decoded.cast<String, Object?>();
    final version = json['version'];
    if (version is! num || version.toInt() > currentVersion) {
      throw const FormatException('Unsupported editor settings version');
    }
    return EditorSettings(
      workspace: _decodeWorkspace(json['workspace']),
      recentScenes: [
        if (json['recentScenes'] is List)
          for (final path in json['recentScenes'] as List)
            if (path is String) path,
      ].take(maximumRecentScenes).toList(),
      flutterInstallations: [
        if (json['flutterInstallations'] is List)
          for (final entry in json['flutterInstallations'] as List)
            if (entry is Map)
              FlutterInstallation.fromJson(entry.cast<String, Object?>()),
      ],
      selectedInstallationId: json['selectedInstallationId'] as String?,
      editorCommand: json['editorCommand'] as String?,
      recentProjects: [
        if (json['recentProjects'] is List)
          for (final path in json['recentProjects'] as List)
            if (path is String) path,
      ].take(maximumRecentProjects).toList(),
      selectedBuildConfigurations: {
        if (json['projectState'] is Map)
          for (final entry in (json['projectState'] as Map).entries)
            if (entry.key is String &&
                entry.value is Map &&
                (entry.value as Map)['selectedBuildConfigurationId'] is String)
              entry.key as String:
                  (entry.value as Map)['selectedBuildConfigurationId']
                      as String,
      },
      selectedDevices: {
        if (json['projectState'] is Map)
          for (final entry in (json['projectState'] as Map).entries)
            if (entry.key is String &&
                entry.value is Map &&
                (entry.value as Map)['selectedDeviceId'] is String)
              entry.key as String:
                  (entry.value as Map)['selectedDeviceId'] as String,
      },
      restartOnSceneSave: {
        if (json['projectState'] is Map)
          for (final entry in (json['projectState'] as Map).entries)
            if (entry.key is String &&
                entry.value is Map &&
                (entry.value as Map)['restartOnSceneSave'] is bool)
              entry.key as String:
                  (entry.value as Map)['restartOnSceneSave'] as bool,
      },
      lastScenes: {
        if (json['projectState'] is Map)
          for (final entry in (json['projectState'] as Map).entries)
            if (entry.key is String &&
                entry.value is Map &&
                (entry.value as Map)['lastScenePath'] is String)
              entry.key as String:
                  (entry.value as Map)['lastScenePath'] as String,
      },
      gizmosEnabled:
          json['gizmos'] is! Map || (json['gizmos'] as Map)['enabled'] != false,
      giProbesVisible:
          json['gizmos'] is Map && (json['gizmos'] as Map)['giProbes'] == true,
      hiddenGizmoTypes: {
        if (json['gizmos'] is Map &&
            (json['gizmos'] as Map)['hiddenTypes'] is List)
          for (final type in (json['gizmos'] as Map)['hiddenTypes'] as List)
            if (type is String) type,
      },
    );
  }

  /// The editor window's region sizes and collapse state, as the shell wrote
  /// it. Opaque here: settings persist it, the shell reads it.
  String? workspace;

  final List<String> recentScenes;

  /// Registered Flutter installations (the global toolchain registry).
  final List<FlutterInstallation> flutterInstallations;

  /// The globally selected installation's id, or null for the built-in
  /// bundled toolchain.
  String? selectedInstallationId;

  /// Recently opened `.fproject` paths, newest first.
  final List<String> recentProjects;

  /// Per-project selected build configuration ids, keyed by the `.fproject`
  /// absolute path. Per-user state deliberately kept out of the committed
  /// project file.
  final Map<String, String> selectedBuildConfigurations;

  /// Per-project selected device ids (the toolbar's device dropdown), same
  /// keying and rationale.
  final Map<String, String> selectedDevices;

  /// Per-project "hot restart the running session on scene save" toggles,
  /// same keying and rationale.
  final Map<String, bool> restartOnSceneSave;

  /// Per-project last-opened scene paths, same keying; wins over the
  /// project's committed defaultScene when resuming.
  final Map<String, String> lastScenes;

  /// Command that opens a source file in the user's editor. `${SOURCE_FILE}`
  /// is replaced with the file's shell-quoted absolute path, appended when
  /// the placeholder is absent.
  String editorCommand;

  /// The viewport component-gizmo master toggle.
  bool gizmosEnabled;

  /// Whether the global-illumination probe lattice draws in the viewport.
  bool giProbesVisible;

  /// Component types whose gizmos are hidden. Encoding the hidden set (not
  /// the shown set) keeps newly installed component types visible by
  /// default.
  final Set<String> hiddenGizmoTypes;

  static String? _decodeWorkspace(Object? value) {
    return value is Map ? jsonEncode(value) : null;
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
    'version': currentVersion,
    if (_encodeLayout(workspace) case final saved?) 'workspace': saved,
    'recentScenes': recentScenes,
    if (flutterInstallations.isNotEmpty)
      'flutterInstallations': [
        for (final installation in flutterInstallations) installation.toJson(),
      ],
    if (selectedInstallationId != null)
      'selectedInstallationId': selectedInstallationId,
    if (editorCommand != defaultEditorCommand) 'editorCommand': editorCommand,
    if (!gizmosEnabled || hiddenGizmoTypes.isNotEmpty || giProbesVisible)
      'gizmos': {
        if (!gizmosEnabled) 'enabled': false,
        if (giProbesVisible) 'giProbes': true,
        if (hiddenGizmoTypes.isNotEmpty)
          'hiddenTypes': hiddenGizmoTypes.toList()..sort(),
      },
    if (recentProjects.isNotEmpty) 'recentProjects': recentProjects,
    if (selectedBuildConfigurations.isNotEmpty ||
        selectedDevices.isNotEmpty ||
        restartOnSceneSave.isNotEmpty ||
        lastScenes.isNotEmpty)
      'projectState': {
        for (final key in {
          ...selectedBuildConfigurations.keys,
          ...selectedDevices.keys,
          ...restartOnSceneSave.keys,
          ...lastScenes.keys,
        })
          key: {
            if (selectedBuildConfigurations[key] case final config?)
              'selectedBuildConfigurationId': config,
            if (selectedDevices[key] case final device?)
              'selectedDeviceId': device,
            if (restartOnSceneSave[key] case final restart?)
              'restartOnSceneSave': restart,
            if (lastScenes[key] case final scene?) 'lastScenePath': scene,
          },
      },
  });

  static Map<String, Object?>? _encodeLayout(String? source) {
    if (source == null) return null;
    try {
      final decoded = jsonDecode(source);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  /// Adds [path] to the front and keeps at most ten distinct entries.
  void rememberScene(String path) {
    final absolute = File(path).absolute.path;
    recentScenes.removeWhere((candidate) => _samePath(candidate, absolute));
    recentScenes.insert(0, absolute);
    if (recentScenes.length > maximumRecentScenes) {
      recentScenes.removeRange(maximumRecentScenes, recentScenes.length);
    }
  }

  void forgetScene(String path) {
    recentScenes.removeWhere((candidate) => _samePath(candidate, path));
  }

  void restoreRecentScenes(Iterable<String> paths) {
    recentScenes
      ..clear()
      ..addAll(paths.take(maximumRecentScenes));
  }

  /// Adds [path] to the front of the recent projects, capped like scenes.
  void rememberProject(String path) {
    final absolute = File(path).absolute.path;
    recentProjects.removeWhere((candidate) => _samePath(candidate, absolute));
    recentProjects.insert(0, absolute);
    if (recentProjects.length > maximumRecentProjects) {
      recentProjects.removeRange(maximumRecentProjects, recentProjects.length);
    }
  }

  void forgetProject(String path) {
    recentProjects.removeWhere((candidate) => _samePath(candidate, path));
    selectedBuildConfigurations.remove(path);
    selectedDevices.remove(path);
    restartOnSceneSave.remove(path);
    lastScenes.remove(path);
  }

  /// The registered installation with [id], or null (including the built-in
  /// toolchain's null id).
  FlutterInstallation? installationById(String? id) {
    if (id == null) return null;
    for (final installation in flutterInstallations) {
      if (installation.id == id) return installation;
    }
    return null;
  }

  /// The currently selected installation, or null for the built-in toolchain
  /// (also the fallback when the selected id no longer exists).
  FlutterInstallation? get selectedInstallation =>
      installationById(selectedInstallationId);

  static bool _samePath(String a, String b) {
    if (Platform.isWindows || Platform.isMacOS) {
      return a.toLowerCase() == b.toLowerCase();
    }
    return a == b;
  }
}

/// Loads and atomically saves [EditorSettings].
class EditorSettingsStore {
  EditorSettingsStore({required this.file});

  final File file;

  EditorSettings load() {
    try {
      if (file.existsSync()) {
        return EditorSettings.fromJsonString(file.readAsStringSync());
      }
    } on FileSystemException {
      return EditorSettings();
    } on FormatException {
      return EditorSettings();
    }
    return EditorSettings();
  }

  void save(EditorSettings settings) {
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(settings.toJsonString(), flush: true);
    temporary.renameSync(file.path);
  }
}
