/// The launcher's model: what projects exist, what state they are in, and
/// how the gallery orders and filters them.
///
/// Pure over the file system and the settings; no widgets, no GPU. The
/// launcher UI reads a [ProjectLibrary] and draws it.
library;

import 'dart:io';

import '../project/fproject.dart';

/// How a project's card is sorted in the gallery.
enum ProjectSort {
  /// Most recently opened first, which is the order the editor's recent list
  /// already carries.
  recent('Last opened'),

  /// A to Z by display name.
  name('Name'),

  /// Newest modification to the project file or its scenes first.
  modified('Last modified');

  const ProjectSort(this.label);

  /// The label shown in the sort control.
  final String label;
}

/// One project in the gallery.
class ProjectEntry {
  ProjectEntry({
    required this.path,
    required this.name,
    required this.root,
    required this.exists,
    required this.recentIndex,
    this.modified,
    this.sceneCount = 0,
    this.defaultScene,
    this.coverPath,
    this.problem,
  });

  /// The absolute `.fproject` path, and this entry's identity.
  final String path;

  /// The display name: the file's basename without its extension.
  final String name;

  /// The Flutter project root the `.fproject` points at, or the file's
  /// directory when it could not be read.
  final String root;

  /// Whether the `.fproject` file is still there. A missing project keeps its
  /// card, greyed, so it can be removed rather than silently vanishing.
  final bool exists;

  /// Position in the editor's recent-projects list, which is the recency
  /// order. Projects not in that list sort after the ones that are.
  final int recentIndex;

  /// Last modification across the project file and its scenes, or null when
  /// nothing could be stat'ed.
  final DateTime? modified;

  /// How many `.fscene` files the project root holds.
  final int sceneCount;

  /// The scene the project opens to, absolute, or null.
  final String? defaultScene;

  /// A cover image for the card, or null to fall back to the generated
  /// placeholder.
  final String? coverPath;

  /// Why the project could not be read, when it exists but did not load. The
  /// card shows it rather than dropping the project.
  final String? problem;

  /// Whether the card should read as unavailable.
  bool get isBroken => !exists || problem != null;
}

/// The gallery's contents.
class ProjectLibrary {
  ProjectLibrary(this.entries);

  final List<ProjectEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// The entries matching [query], sorted by [sort].
  ///
  /// Matching is a case-insensitive substring over the name and the path, so
  /// typing part of a directory finds a project whose name does not contain
  /// it. Broken entries sort last within any order, since the point of the
  /// gallery is to get into a project.
  List<ProjectEntry> view({String query = '', ProjectSort sort = ProjectSort.recent}) {
    final needle = query.trim().toLowerCase();
    final matched = [
      for (final entry in entries)
        if (needle.isEmpty ||
            entry.name.toLowerCase().contains(needle) ||
            entry.path.toLowerCase().contains(needle))
          entry,
    ];
    matched.sort((a, b) {
      if (a.isBroken != b.isBroken) return a.isBroken ? 1 : -1;
      switch (sort) {
        case ProjectSort.recent:
          return a.recentIndex.compareTo(b.recentIndex);
        case ProjectSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case ProjectSort.modified:
          final aTime = a.modified;
          final bTime = b.modified;
          if (aTime == null && bTime == null) {
            return a.recentIndex.compareTo(b.recentIndex);
          }
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
      }
    });
    return matched;
  }
}

/// Reads a project's card from disk.
///
/// [recentIndex] is its position in the editor's recent list. [coverFor]
/// resolves a cover image path for a project path, or returns null.
ProjectEntry readProjectEntry(
  String path, {
  required int recentIndex,
  String? Function(String projectPath)? coverFor,
}) {
  final file = File(path);
  final name = projectDisplayName(path);
  if (!file.existsSync()) {
    return ProjectEntry(
      path: path,
      name: name,
      root: file.parent.path,
      exists: false,
      recentIndex: recentIndex,
      coverPath: coverFor?.call(path),
    );
  }

  FProject? project;
  String? problem;
  try {
    project = FProject.load(path);
  } on FormatException catch (error) {
    problem = error.message;
  } on FileSystemException catch (error) {
    problem = error.message;
  }

  final root = project?.resolvedProjectRoot ?? file.parent.path;
  final scenes = _sceneFiles(root);
  var modified = _modifiedOrNull(file);
  for (final scene in scenes) {
    final at = _modifiedOrNull(scene);
    if (at != null && (modified == null || at.isAfter(modified))) modified = at;
  }

  return ProjectEntry(
    path: path,
    name: name,
    root: root,
    exists: true,
    recentIndex: recentIndex,
    modified: modified,
    sceneCount: scenes.length,
    defaultScene: project?.resolvedDefaultScene,
    coverPath: coverFor?.call(path),
    problem: problem,
  );
}

/// Builds the gallery from the editor's recent-projects list plus any
/// [extraPaths] (a scan of a projects folder, say).
///
/// Duplicate paths collapse onto the first mention, so a project that is both
/// recent and scanned appears once, keeping its recency.
ProjectLibrary buildProjectLibrary(
  List<String> recentProjects, {
  List<String> extraPaths = const [],
  String? Function(String projectPath)? coverFor,
}) {
  final seen = <String>{};
  final entries = <ProjectEntry>[];
  var index = 0;
  for (final path in [...recentProjects, ...extraPaths]) {
    final absolute = File(path).absolute.path;
    if (!seen.add(absolute)) continue;
    entries.add(
      readProjectEntry(absolute, recentIndex: index++, coverFor: coverFor),
    );
  }
  return ProjectLibrary(entries);
}

/// The display name for a `.fproject` path: its basename without the
/// extension.
String projectDisplayName(String path) {
  final base = path.replaceAll('\\', '/').split('/').last;
  return base.endsWith('.fproject')
      ? base.substring(0, base.length - '.fproject'.length)
      : base;
}

/// A short "3 days ago" for a card's footer, or an empty string for null.
///
/// Deliberately coarse: the card is a way back into work, and the exact
/// minute is never the reason one is picked over another.
String describeAge(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes} minute${elapsed.inMinutes == 1 ? '' : 's'} ago';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
  }
  if (elapsed.inDays < 30) {
    return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
  }
  final months = elapsed.inDays ~/ 30;
  if (months < 12) return '$months month${months == 1 ? '' : 's'} ago';
  final years = elapsed.inDays ~/ 365;
  return '$years year${years == 1 ? '' : 's'} ago';
}

/// The `.fproject` files directly inside [directory] and one level below it,
/// which is where a folder of projects keeps them.
///
/// Two levels rather than a full walk: a projects folder holds project
/// directories, and descending further would wander into build outputs and
/// package caches.
List<String> scanForProjects(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];
  final found = <String>[];
  void collect(Directory dir) {
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.fproject')) {
          found.add(entity.absolute.path);
        }
      }
    } on FileSystemException {
      // An unreadable directory is skipped rather than failing the scan.
    }
  }

  collect(root);
  try {
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is Directory && !_isHidden(entity.path)) collect(entity);
    }
  } on FileSystemException {
    // As above.
  }
  found.sort();
  return found;
}

bool _isHidden(String path) =>
    path.replaceAll('\\', '/').split('/').last.startsWith('.');

/// The `.fscene` files under [root], skipping the directories a Flutter
/// project fills with generated and vendored content.
List<File> _sceneFiles(String root) {
  final directory = Directory(root);
  if (!directory.existsSync()) return const [];
  const skip = {'build', '.dart_tool', '.git', 'ios', 'android', 'windows'};
  final scenes = <File>[];
  void walk(Directory dir, int depth) {
    if (depth > 4) return;
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File) {
          if (entity.path.endsWith('.fscene')) scenes.add(entity);
        } else if (entity is Directory) {
          final base = entity.path.replaceAll('\\', '/').split('/').last;
          if (skip.contains(base) || base.startsWith('.')) continue;
          walk(entity, depth + 1);
        }
      }
    } on FileSystemException {
      // Skip what cannot be listed.
    }
  }

  walk(directory, 0);
  return scenes;
}

DateTime? _modifiedOrNull(File file) {
  try {
    return file.lastModifiedSync();
  } on FileSystemException {
    return null;
  }
}
