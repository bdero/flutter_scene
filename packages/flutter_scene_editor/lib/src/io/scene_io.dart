/// Reading and writing `.fscene` files, with native open and save dialogs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/binary/fsceneb.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/compose/compose.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart' show AssetRef;
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:vector_math/vector_math.dart';

import '../controller/editor_controller.dart';
import 'glb_import_options.dart';

const _fsceneTypeGroup = XTypeGroup(
  label: 'flutter_scene',
  extensions: <String>['fscene'],
);

const _modelTypeGroup = XTypeGroup(
  label: 'glTF model',
  extensions: <String>['glb', 'gltf'],
);

const _environmentTypeGroup = XTypeGroup(
  label: 'Environment map',
  extensions: <String>['hdr', 'exr', 'png', 'jpg', 'jpeg'],
);

/// Shows the native open dialog filtered to environment images (`.hdr`/`.exr`
/// plus LDR equirect formats), and returns the chosen path, or null on cancel.
Future<String?> pickEnvironmentPath() async {
  final file = await openFile(
    acceptedTypeGroups: const [_environmentTypeGroup],
  );
  return file?.path;
}

/// Imports the equirectangular environment image at [path] (a `.hdr`/`.exr`
/// HDR map or an LDR image) and sets it as an environment resource's look.
///
/// [environmentId] is the target environment resource (the stage's global
/// environment or a volume's); when null the stage's global resource is used
/// (the editor guarantees one exists). When the scene is saved (a non-null
/// `baseDirectory`), the file is copied under `imported/` and referenced
/// relatively so it persists with the scene; otherwise the absolute path is
/// referenced for the session. Returns the referenced asset path. The
/// environment applies through the editor's disk-environment loader.
Future<String> importEnvironmentMap(
  EditorController controller,
  String path, {
  LocalId? environmentId,
}) async {
  final assetRef = _importFileAsset(controller.baseDirectory, path);
  // Use the HDR for both lighting and the background. Sky-driven lighting owns
  // the scene environment, so turn it off and show the environment as the
  // skybox. Target the given environment resource, else the stage's global one.
  final envId = environmentId ?? controller.document.stage.environmentRef;
  if (envId == null) return assetRef;
  final id = envId.toToken();
  await controller.run('setEnvironmentProperties', {
    'environmentId': id,
    'properties': {'environment': 'asset', 'environmentAsset': assetRef},
  });
  await controller.run('setEnvironmentSkybox', {
    'environmentId': id,
    'sky': 'environment',
    'lightScene': false,
  });
  return assetRef;
}

const _imageTypeGroup = XTypeGroup(
  label: 'Image',
  extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
);

/// Shows the native open dialog filtered to image files, and returns the chosen
/// path, or null on cancel.
Future<String?> pickImagePath() async {
  final file = await openFile(acceptedTypeGroups: const [_imageTypeGroup]);
  return file?.path;
}

/// Imports the image at [path] as a texture resource and returns its id (or
/// null if nothing was created).
///
/// The image is externalized, not embedded: it is copied under `imported/` (or
/// referenced by absolute path for an unsaved scene) and the texture references
/// it as an asset, so the heavy image bytes persist with the scene as a file
/// rather than an embedded payload a lean `.fscene` save would drop. The
/// realizer decodes the asset from disk through the controller's texture loader.
Future<LocalId?> importTextureResource(
  EditorController controller,
  String path,
) async {
  final assetRef = _importFileAsset(controller.baseDirectory, path);
  final before = Set.of(controller.document.resources.keys);
  await controller.run('createTextureResourceFromAsset', {'asset': assetRef});
  final added = controller.document.resources.keys.where(
    (id) => !before.contains(id),
  );
  return added.isEmpty ? null : added.first;
}

/// Imports the image at [path] (see [importTextureResource]) and assigns it to
/// [slot] (a material texture-property key, e.g. `baseColorTexture`) of material
/// [materialId]. Returns the new texture resource id.
Future<LocalId?> importMaterialTexture(
  EditorController controller,
  LocalId materialId,
  String slot,
  String path,
) async {
  final textureId = await importTextureResource(controller, path);
  if (textureId == null) return null;
  await controller.run('setMaterialProperties', {
    'materialId': materialId.toToken(),
    'properties': {
      slot: {'\$resource': textureId.toToken()},
    },
  });
  return textureId;
}

String _fileExtension(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? 'bin' : name.substring(dot + 1);
}

/// Copies the file at [sourcePath] into the scene's `imported/` directory and
/// returns the scene-relative asset key, so an imported image/HDR persists with
/// the scene as a referenced file. When the scene is unsaved ([sceneDir] null)
/// the absolute source path is referenced for the session instead.
String _importFileAsset(String? sceneDir, String sourcePath) {
  if (sceneDir == null) {
    // TODO(import-copy-on-save): an asset imported into an unsaved scene is
    // referenced by absolute path; copy it under imported/ and rewrite the
    // reference to relative on the first Save As.
    return sourcePath;
  }
  final importedDir = Directory('$sceneDir${Platform.pathSeparator}imported')
    ..createSync(recursive: true);
  final ext = _fileExtension(sourcePath);
  final dest = _uniqueFile(importedDir, _modelBaseName(sourcePath), ext);
  dest.writeAsBytesSync(File(sourcePath).readAsBytesSync());
  return 'imported/${dest.uri.pathSegments.last}';
}

/// Shows the native open dialog filtered to glTF models (`.glb`/`.gltf`), and
/// returns the chosen path, or null when the user cancels.
Future<String?> pickModelPath() async {
  final file = await openFile(acceptedTypeGroups: const [_modelTypeGroup]);
  return file?.path;
}

/// Imports the glTF model at [path] (single-file `.glb` or multi-file `.gltf`
/// with sibling `.bin`/image files) into an editable [SceneDocument].
///
/// For `.gltf`, external resources are read from the file's directory. Throws
/// an [IOException] on read failure and a [FormatException] when a `.gltf`
/// references a resource that cannot be read (for example a sibling file the
/// sandbox did not grant access to).
Future<SceneDocument> importModelDocument(
  String path, {
  bool compressTextures = false,
}) async {
  final bytes = await File(path).readAsBytes();
  if (path.toLowerCase().endsWith('.gltf')) {
    final dir = File(path).parent.path;
    return importGltfToSceneDocument(
      bytes,
      compressTextures: compressTextures,
      resolveUri: (uri) {
        final file = File('$dir${Platform.pathSeparator}$uri');
        return file.existsSync() ? file.readAsBytesSync() : null;
      },
    );
  }
  return importGlbToSceneDocument(bytes, compressTextures: compressTextures);
}

/// Imports the glTF model at [path] into a fresh editable [EditorController].
/// [compressTextures] compresses imported textures; [scale] and [upAxis] apply
/// a non-destructive import transform.
Future<EditorController> importModel(
  String path, {
  bool compressTextures = false,
  double scale = 1.0,
  ImportUpAxis upAxis = ImportUpAxis.yUp,
}) async {
  final document = await importModelDocument(
    path,
    compressTextures: compressTextures,
  );
  return EditorController.fromImportedScene(
    document,
    scale: scale,
    upAxis: upAxis,
    baseDirectory: File(path).parent.path,
  );
}

/// Writes [controller]'s document to a `.fscene` file at [path].
///
/// Throws an [IOException] on write failure.
Future<void> saveFscene(EditorController controller, String path) async {
  await File(path).writeAsString(controller.session.toFscene());
}

/// Reads a `.fscene` file from [path] and returns a fresh [EditorController].
/// The file's directory becomes the base for resolving prefab references.
///
/// Throws an [IOException] on read failure and a [FormatException] on bad JSON.
Future<EditorController> openFscene(String path) async {
  final source = await File(path).readAsString();
  return EditorController.fromFscene(
    source,
    baseDirectory: File(path).parent.path,
  );
}

/// Shows the native open dialog filtered to `.fscene`, and returns the chosen
/// path, or null when the user cancels.
Future<String?> pickOpenPath() async {
  final file = await openFile(acceptedTypeGroups: const [_fsceneTypeGroup]);
  return file?.path;
}

/// Shows the native save dialog, and returns the chosen path, or null when the
/// user cancels.
Future<String?> pickSavePath({String? suggestedName}) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [_fsceneTypeGroup],
    suggestedName: suggestedName ?? 'scene.fscene',
  );
  return location?.path;
}

/// Reads the prefab `.fscene` at [sourcePath], bakes [instance]'s delta into it
/// (overrides, then added and removed nodes), and writes it back.
///
/// NOTE this mutates the shared source file, so every instance of that prefab
/// reflects the change on next load. This is intentional apply semantics. The
/// caller clears the instance's delta after a successful apply so it is not
/// doubled.
///
/// Throws an [IOException] when the file cannot be read or written, and a
/// [FsceneFormatException] when the file is malformed.
Future<void> applyInstanceToSource({
  required String sourcePath,
  required SceneDocument host,
  required PrefabInstanceSpec instance,
}) async {
  final file = File(sourcePath);
  final doc = readFscene(await file.readAsString());
  for (final override in instance.overrides) {
    applyPrefabOverride(doc, override);
  }
  // Remove nodes the instance dropped (and their subtrees).
  for (final removed in instance.removedNodes) {
    _removeSubtree(doc, removed);
  }
  // Copy attached host subtrees into the prefab under their parent (or a root).
  for (final attachment in instance.attachments) {
    final rootSpec = host.nodes[attachment.node];
    if (rootSpec == null) continue;
    _copySubtree(host, doc, attachment.node);
    final parent = attachment.parent;
    if (parent != null && doc.nodes[parent] != null) {
      doc.nodes[parent]!.children.add(attachment.node);
    } else {
      doc.roots.add(attachment.node);
    }
  }
  await file.writeAsString(writeFscene(doc));
}

// Deep-copies the subtree rooted at [id] from [from] into [into] (nodes only;
// shared resources are already in the prefab or referenced by id).
void _copySubtree(SceneDocument from, SceneDocument into, LocalId id) {
  final node = from.nodes[id];
  if (node == null) return;
  into.nodes[id] = node;
  for (final child in node.children) {
    _copySubtree(from, into, child);
  }
}

void _removeSubtree(SceneDocument doc, LocalId root) {
  final node = doc.nodes.remove(root);
  doc.roots.remove(root);
  for (final other in doc.nodes.values) {
    other.children.remove(root);
  }
  if (node != null) {
    for (final child in node.children) {
      _removeSubtree(doc, child);
    }
  }
}

// --- Linked glTF import -----------------------------------------------------

/// The non-destructive transform a glTF import applies for [options] (a uniform
/// scale and up-axis fix), or null when scale is 1 and the up axis is the
/// glTF-native Y (a no-op). Z-up adds a -90 degrees rotation about X.
TransformSpec? importGroupTransform(GlbImportOptions options) {
  if (options.scale == 1.0 && options.upAxis == ImportUpAxis.yUp) return null;
  final rotation = options.upAxis == ImportUpAxis.zUp
      ? Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2)
      : Quaternion.identity();
  return TrsTransform(rotation: rotation, scale: Vector3.all(options.scale));
}

/// How a linked asset was imported, recorded next to its `.fsceneb` so it can
/// be re-imported and a changed source detected.
class ImportRecord {
  ImportRecord({
    required this.source,
    required this.scale,
    required this.upAxis,
    required this.compressTextures,
    required this.sourceHash,
  });

  /// The source model path, relative to the scene directory when it lives
  /// under it, otherwise absolute.
  final String source;
  final double scale;
  final ImportUpAxis upAxis;
  final bool compressTextures;

  /// A content hash of the source file at import time (for change detection).
  final String sourceHash;

  Map<String, Object?> toJson() => {
    'source': source,
    'scale': scale,
    'upAxis': upAxis.name,
    'compressTextures': compressTextures,
    'sourceHash': sourceHash,
  };

  factory ImportRecord.fromJson(Map<String, Object?> json) => ImportRecord(
    source: json['source'] as String,
    scale: (json['scale'] as num).toDouble(),
    upAxis: ImportUpAxis.values.byName(json['upAxis'] as String),
    compressTextures: json['compressTextures'] as bool? ?? false,
    sourceHash: json['sourceHash'] as String? ?? '',
  );

  GlbImportOptions toOptions() => GlbImportOptions(
    compressTextures: compressTextures,
    scale: scale,
    upAxis: upAxis,
  );
}

/// Imports [modelPath] (a `.glb`/`.gltf`) as a linked asset into [controller]'s
/// scene: converts it, writes the result under `imported/` next to the saved
/// scene, records the import in a sidecar, and instantiates it as a prefab
/// (under [parentId] when given). Returns the relative asset path.
///
/// Requires a saved scene (a non-null `baseDirectory`); throws a
/// [FormatException] otherwise.
Future<String> importLinkedModel(
  EditorController controller,
  String modelPath,
  GlbImportOptions options, {
  LocalId? parentId,
}) async {
  final sceneDir = controller.baseDirectory;
  if (sceneDir == null) {
    throw const FormatException(
      'Save the scene before importing a linked asset.',
    );
  }
  final document = await importModelDocument(
    modelPath,
    compressTextures: options.compressTextures,
  );
  _externalizeTextureAssets(document, modelPath, sceneDir);
  final baseName = _modelBaseName(modelPath);
  final transform = importGroupTransform(options);
  if (transform != null) {
    wrapRootsUnderGroup(document, name: baseName, transform: transform);
  }

  final importedDir = Directory('$sceneDir${Platform.pathSeparator}imported')
    ..createSync(recursive: true);
  final assetFile = _uniqueFile(importedDir, baseName, 'fsceneb');
  assetFile.writeAsBytesSync(writeFsceneb(document));

  final record = ImportRecord(
    source: _relativeTo(sceneDir, modelPath),
    scale: options.scale,
    upAxis: options.upAxis,
    compressTextures: options.compressTextures,
    sourceHash: _hashBytes(File(modelPath).readAsBytesSync()),
  );
  File('${assetFile.path}.import.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(record.toJson()),
  );

  final relative = 'imported/${assetFile.uri.pathSegments.last}';
  await controller.run('instantiatePrefab', {
    'prefabAsset': relative,
    'name': baseName,
    if (parentId != null) 'parentId': parentId.toToken(),
  });
  return relative;
}

// Rewrites texture resources referencing files outside the scene (a model's
// external image URIs, resolved next to the model source) to copies under
// `imported/textures/`, named by content hash so identically-named files from
// different packs (each kit's `Textures/colormap.png`) cannot collide and
// identical files are shared. A reference that cannot be resolved is left
// alone.
void _externalizeTextureAssets(
  SceneDocument document,
  String modelPath,
  String sceneDir,
) {
  final modelDir = File(modelPath).parent.path;
  final sep = Platform.pathSeparator;
  for (final entry in document.resources.entries.toList()) {
    final resource = entry.value;
    if (resource is! TextureResource) continue;
    final asset = resource.asset;
    if (asset == null) continue;
    final source = File(
      asset.key.startsWith('/') ? asset.key : '$modelDir$sep${asset.key}',
    );
    if (!source.existsSync()) continue;
    final bytes = source.readAsBytesSync();
    final stem = source.uri.pathSegments.last;
    final dot = stem.lastIndexOf('.');
    final name = dot <= 0 ? stem : stem.substring(0, dot);
    final ext = dot <= 0 ? '' : stem.substring(dot);
    final relative =
        'imported/textures/$name-${_hashBytes(bytes).substring(0, 8)}$ext';
    final target = File('$sceneDir$sep$relative');
    if (!target.existsSync()) {
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(bytes);
    }
    document.resources[entry.key] = TextureResource(
      entry.key,
      asset: AssetRef(relative),
    );
  }
}

/// Reads the [ImportRecord] for a linked asset at [assetPath] (the sidecar
/// `<assetPath>.import.json`), or null when absent or unreadable.
ImportRecord? readImportRecord(String assetPath) {
  final file = File('$assetPath.import.json');
  if (!file.existsSync()) return null;
  try {
    return ImportRecord.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  } on FormatException {
    return null;
  }
}

String _modelBaseName(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

File _uniqueFile(Directory dir, String base, String extension) {
  var candidate = File('${dir.path}${Platform.pathSeparator}$base.$extension');
  var n = 1;
  while (candidate.existsSync()) {
    candidate = File(
      '${dir.path}${Platform.pathSeparator}${base}_$n.$extension',
    );
    n++;
  }
  return candidate;
}

String _relativeTo(String dir, String path) {
  final prefix = dir.endsWith(Platform.pathSeparator)
      ? dir
      : '$dir${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

// A fast, stable 64-bit FNV-1a content hash, hex-encoded. Enough to detect a
// changed source file between sessions.
String _hashBytes(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  const mask = 0xffffffffffffffff;
  for (final byte in bytes) {
    hash = (hash ^ byte) & mask;
    hash = (hash * 0x100000001b3) & mask;
  }
  return hash.toRadixString(16);
}

// Resolves a prefab instance [node] to its linked-import asset path, source
// path, and record, or null when it is not a linked glTF import.
({String assetPath, String sourcePath, ImportRecord record})? _linkedImportOf(
  NodeSpec node,
  String sceneDir,
) {
  final instance = node.instance;
  if (instance == null) return null;
  final key = instance.source.key;
  final assetPath = key.startsWith('/')
      ? key
      : '$sceneDir${Platform.pathSeparator}$key';
  final record = readImportRecord(assetPath);
  if (record == null) return null;
  final sourcePath = record.source.startsWith('/')
      ? record.source
      : '$sceneDir${Platform.pathSeparator}${record.source}';
  return (assetPath: assetPath, sourcePath: sourcePath, record: record);
}

/// The [ImportRecord] for the linked glTF import [nodeId] is an instance of, or
/// null when [nodeId] is not a linked import (used to enable Re-import and to
/// pre-fill its dialog with the recorded settings).
ImportRecord? linkedImportRecordFor(
  EditorController controller,
  LocalId nodeId,
) {
  final sceneDir = controller.baseDirectory;
  if (sceneDir == null) return null;
  final node = controller.document.nodes[nodeId];
  if (node == null) return null;
  return _linkedImportOf(node, sceneDir)?.record;
}

/// Re-imports the linked glTF the instance [instanceId] references: re-converts
/// its recorded source with [options], overwrites the `imported/` asset and its
/// sidecar, and recomposes. The instance's overrides survive (the importer's
/// positional ids keep node ids stable). Not an undoable edit (a file rewrite).
Future<void> reimportLinkedModel(
  EditorController controller,
  LocalId instanceId,
  GlbImportOptions options,
) async {
  final sceneDir = controller.baseDirectory;
  if (sceneDir == null) {
    throw const FormatException('Save the scene before re-importing.');
  }
  final node = controller.document.nodes[instanceId];
  final linked = node == null ? null : _linkedImportOf(node, sceneDir);
  if (linked == null) {
    throw const FormatException('The selection is not a linked glTF import.');
  }
  final document = await importModelDocument(
    linked.sourcePath,
    compressTextures: options.compressTextures,
  );
  _externalizeTextureAssets(document, linked.sourcePath, sceneDir);
  final baseName = _modelBaseName(linked.sourcePath);
  final transform = importGroupTransform(options);
  if (transform != null) {
    wrapRootsUnderGroup(document, name: baseName, transform: transform);
  }
  File(linked.assetPath).writeAsBytesSync(writeFsceneb(document));

  final updated = ImportRecord(
    source: linked.record.source,
    scale: options.scale,
    upAxis: options.upAxis,
    compressTextures: options.compressTextures,
    sourceHash: _hashBytes(File(linked.sourcePath).readAsBytesSync()),
  );
  File('${linked.assetPath}.import.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(updated.toJson()),
  );

  controller.clearPrefabCache(node!.instance!.source.key);
  await controller.recompose();
}

/// A linked instance whose source model changed on disk since it was imported.
class LinkedSourceChange {
  LinkedSourceChange({required this.instanceId, required this.sourcePath});

  /// The instance node id (target of a Re-import).
  final LocalId instanceId;

  /// The absolute source model path that changed.
  final String sourcePath;
}

/// Scans [controller]'s linked imports and returns those whose source model
/// file's content differs from the hash recorded at import time. Used to prompt
/// the user to re-import after editing the source externally.
List<LinkedSourceChange> changedLinkedSources(EditorController controller) {
  final sceneDir = controller.baseDirectory;
  if (sceneDir == null) return const [];
  final changes = <LinkedSourceChange>[];
  for (final node in controller.document.nodes.values) {
    final linked = _linkedImportOf(node, sceneDir);
    if (linked == null) continue;
    final source = File(linked.sourcePath);
    if (!source.existsSync()) continue;
    if (_hashBytes(source.readAsBytesSync()) != linked.record.sourceHash) {
      changes.add(
        LinkedSourceChange(instanceId: node.id, sourcePath: linked.sourcePath),
      );
    }
  }
  return changes;
}
