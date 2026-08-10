import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Persisted editor preferences shared across documents.
class EditorSettings {
  EditorSettings({
    this.dockLayout,
    Map<String, String>? namedLayouts,
    List<String>? recentScenes,
  }) : namedLayouts = LinkedHashMap.of(namedLayouts ?? const {}),
       recentScenes = List.of(recentScenes ?? const []);

  static const int currentVersion = 1;
  static const int maximumRecentScenes = 10;

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
    final layouts = <String, String>{};
    final encodedLayouts = json['namedLayouts'];
    if (encodedLayouts is Map) {
      for (final entry in encodedLayouts.entries) {
        if (entry.key is String && entry.value is Map) {
          layouts[entry.key as String] = jsonEncode(entry.value);
        }
      }
    }
    return EditorSettings(
      dockLayout: _decodeLayout(json['dockLayout']),
      namedLayouts: layouts,
      recentScenes: [
        if (json['recentScenes'] is List)
          for (final path in json['recentScenes'] as List)
            if (path is String) path,
      ].take(maximumRecentScenes).toList(),
    );
  }

  String? dockLayout;
  final LinkedHashMap<String, String> namedLayouts;
  final List<String> recentScenes;

  static String? _decodeLayout(Object? value) {
    return value is Map ? jsonEncode(value) : null;
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
    'version': currentVersion,
    if (_encodeLayout(dockLayout) case final layout?) 'dockLayout': layout,
    'namedLayouts': {
      for (final entry in namedLayouts.entries)
        if (_encodeLayout(entry.value) case final layout?) entry.key: layout,
    },
    'recentScenes': recentScenes,
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

  /// Saves a named snapshot, replacing an exact or case-insensitive match.
  void saveNamedLayout(String name, String layout) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('Layout name is empty');
    final existing = namedLayouts.keys.cast<String?>().firstWhere(
      (candidate) => candidate!.toLowerCase() == trimmed.toLowerCase(),
      orElse: () => null,
    );
    if (existing != null && existing != trimmed) namedLayouts.remove(existing);
    namedLayouts[trimmed] = layout;
  }

  void deleteNamedLayout(String name) {
    namedLayouts.remove(name);
  }

  static bool _samePath(String a, String b) {
    if (Platform.isWindows || Platform.isMacOS) {
      return a.toLowerCase() == b.toLowerCase();
    }
    return a == b;
  }
}

/// Loads and atomically saves [EditorSettings].
class EditorSettingsStore {
  EditorSettingsStore({required this.file, this.legacyDockLayoutFile});

  final File file;
  final File? legacyDockLayoutFile;

  EditorSettings load() {
    try {
      if (file.existsSync()) {
        return EditorSettings.fromJsonString(file.readAsStringSync());
      }
    } on FileSystemException {
      return _migrateLegacyLayout();
    } on FormatException {
      return _migrateLegacyLayout();
    }
    return _migrateLegacyLayout();
  }

  EditorSettings _migrateLegacyLayout() {
    try {
      final legacy = legacyDockLayoutFile;
      if (legacy != null && legacy.existsSync()) {
        return EditorSettings(dockLayout: legacy.readAsStringSync());
      }
    } on FileSystemException {
      // The default settings remain usable.
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
