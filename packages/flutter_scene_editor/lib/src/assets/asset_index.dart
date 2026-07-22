/// The project asset index: a background scan of the open scene's directory for
/// referenceable files (models, images, HDRs, scenes), plus an enumeration of
/// the document's embedded pool resources with their reverse-dependency counts.
///
/// This is the data behind the asset browser. It is deliberately read-only over
/// the filesystem and the document; mutations flow through the command layer.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/scene_document.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';

/// The kind of an on-disk project asset, picked by file extension.
enum FileAssetKind { model, image, hdr, scene }

/// A file under the project directory the browser can act on.
@immutable
class FileAsset {
  const FileAsset({
    required this.kind,
    required this.path,
    required this.name,
    required this.relativePath,
  });

  final FileAssetKind kind;

  /// Absolute path on disk.
  final String path;

  /// The file name (with extension).
  final String name;

  /// The path relative to the project root, for display.
  final String relativePath;
}

/// The kind of an embedded pool resource, for the browser's "in this scene"
/// section.
enum EmbeddedResourceKind { material, geometry, texture, environment, other }

/// An embedded resource in the document pool, with its reverse dependencies so
/// the browser can show "used by N" and flag unused resources (which are never
/// silently dropped, only removed on an explicit action).
@immutable
class EmbeddedResource {
  const EmbeddedResource({
    required this.id,
    required this.kind,
    required this.label,
    required this.usedBy,
  });

  final LocalId id;
  final EmbeddedResourceKind kind;

  /// A human-readable label (a name when the resource carries one, else its
  /// kind plus a short id).
  final String label;

  /// The display names of the nodes (and the stage) that reference this
  /// resource. Empty means unused.
  final List<String> usedBy;

  bool get isUnused => usedBy.isEmpty;
}

/// Extensions classified into [FileAssetKind]s.
const _modelExt = {'.glb', '.gltf', '.fsceneb'};
const _imageExt = {'.png', '.jpg', '.jpeg', '.webp'};
const _hdrExt = {'.hdr', '.exr'};
const _sceneExt = {'.fscene'};

FileAssetKind? _classify(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = name.substring(dot).toLowerCase();
  if (_modelExt.contains(ext)) return FileAssetKind.model;
  if (_imageExt.contains(ext)) return FileAssetKind.image;
  if (_hdrExt.contains(ext)) return FileAssetKind.hdr;
  if (_sceneExt.contains(ext)) return FileAssetKind.scene;
  return null;
}

/// Scans [root] (the project directory) for referenceable assets, recursing up
/// to [maxDepth] levels and stopping after [maxEntries] hits so a huge tree
/// cannot stall the UI. Hidden directories (including `.dart_tool`) and
/// `build`/`node_modules` are skipped. Returns the assets sorted by kind then
/// name. The walk is bounded and cheap, but stays async so a slow disk does not
/// block the caller.
Future<List<FileAsset>> scanProjectAssets(
  String root, {
  int maxDepth = 6,
  int maxEntries = 4000,
}) async {
  final results = <FileAsset>[];
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return results;
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';

  Future<void> walk(Directory dir, int depth) async {
    if (depth > maxDepth || results.length >= maxEntries) return;
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return; // Unreadable directory (permissions): skip, do not fail.
    }
    for (final entry in entries) {
      if (results.length >= maxEntries) return;
      final base = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (base.startsWith('.')) continue;
      if (entry is Directory) {
        if (base == 'build' || base == 'node_modules') continue;
        await walk(entry, depth + 1);
      } else if (entry is File) {
        final kind = _classify(base);
        if (kind == null) continue;
        results.add(
          FileAsset(
            kind: kind,
            path: entry.path,
            name: base,
            relativePath: entry.path.startsWith(prefix)
                ? entry.path.substring(prefix.length)
                : entry.path,
          ),
        );
      }
    }
  }

  await walk(rootDir, 0);
  results.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    return byKind != 0
        ? byKind
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return results;
}

EmbeddedResourceKind _resourceKind(ResourceSpec spec) => switch (spec) {
  MaterialResource() => EmbeddedResourceKind.material,
  GeometryResource() => EmbeddedResourceKind.geometry,
  TextureResource() => EmbeddedResourceKind.texture,
  EnvironmentResource() => EmbeddedResourceKind.environment,
  _ => EmbeddedResourceKind.other,
};

String _resourceLabel(ResourceSpec spec) {
  final shortId = spec.id.toToken();
  final tail = shortId.length > 6
      ? shortId.substring(shortId.length - 6)
      : shortId;
  return switch (spec) {
    EnvironmentResource(:final name) when name.isNotEmpty => name,
    EnvironmentResource() => 'Environment $tail',
    MaterialResource(:final type) => '$type material $tail',
    GeometryResource() => 'Geometry $tail',
    TextureResource() => 'Texture $tail',
    _ => 'Resource $tail',
  };
}

/// Enumerates [document]'s embedded pool resources with their reverse
/// dependencies (which nodes, and the stage, reference each). Used to render the
/// "in this scene" section and to flag and clean up unused resources.
List<EmbeddedResource> embeddedResources(SceneDocument document) {
  // Build a map of resource id -> referencing display names.
  final usedBy = <LocalId, List<String>>{};
  void addRef(LocalId id, String by) =>
      usedBy.putIfAbsent(id, () => []).add(by);

  for (final node in document.nodes.values) {
    final nodeName = node.name.isEmpty ? node.id.toToken() : node.name;
    for (final component in node.components) {
      for (final value in component.properties.values) {
        if (value is ResourceRefValue) addRef(value.id, nodeName);
      }
    }
  }
  final envRef = document.stage.environmentRef;
  if (envRef != null) addRef(envRef, 'Scene environment');

  final out = <EmbeddedResource>[
    for (final spec in document.resources.values)
      EmbeddedResource(
        id: spec.id,
        kind: _resourceKind(spec),
        label: _resourceLabel(spec),
        usedBy: usedBy[spec.id] ?? const [],
      ),
  ];
  out.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    return byKind != 0
        ? byKind
        : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}
