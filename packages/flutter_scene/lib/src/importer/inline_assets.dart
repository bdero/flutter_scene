/// Inlining an authored scene's external image assets into a self-contained
/// document, so the `.fsceneb` a build produces carries its textures' bytes
/// rather than asset references the runtime would have to resolve from the
/// asset bundle.
///
/// The editor saves a lean `.fscene` that references imported images by path
/// (good for diffs and sharing). The `.fsceneb` container, by contrast, is meant
/// to be self-contained, so the build step resolves those references against the
/// scene's directory and folds the image bytes in as payload chunks. The
/// resolution step is separated from the inlining step so a build can declare
/// the referenced files as dependencies (and fold their hashes into its cache
/// stamp) every run, even when the conversion itself is skipped as up to date.
library;

import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:scene/scene.dart';

import '../texture/block_alignment.dart';
import '../texture/ktx2_image.dart';
import '../texture/mipmap.dart';

/// An external image file a scene references through a [TextureResource.asset],
/// resolved to a file on disk.
typedef ExternalImageAsset = ({String key, File file});

/// A binary scene that supplies bytes for a textual scene's payload manifest.
typedef ExternalPayloadAsset = ({String key, File file});

/// Rewrites document-relative `.fmat` references in [document] (materials,
/// skyboxes, and sky-driven lighting) to package-relative keys, so the
/// cooked `.fsceneb` resolves them through the DataAssets material registry
/// (which keys `.fmat` sources by their package-relative path).
/// [documentDir] is the scene source's directory relative to the package
/// root, empty when the scene sits at the root. Absolute references and ones
/// that escape the package root are left unchanged (they cannot resolve in a
/// built app; the load reports them).
///
/// [exists] reports whether a package-relative key is a file on disk. A ref
/// that does not resolve next to its document is left alone, so a ref authored
/// against the package root keeps working, which is how the source-root loader
/// reads the same documents.
void rebaseFmatMaterialRefs(
  SceneDocument document,
  String documentDir, {
  bool Function(String key)? exists,
}) {
  for (final entry in document.resources.entries.toList()) {
    final resource = entry.value;
    if (resource is MaterialResource && resource.type == 'fmat') {
      final asset = resource.asset;
      if (asset == null) continue;
      final rebased = _rebaseFmatKey(asset.key, documentDir, exists);
      if (rebased == null) continue;
      document.resources[entry.key] = resource.copyWith(
        asset: AssetRef(rebased),
      );
    } else if (resource is EnvironmentResource) {
      final skybox = resource.skybox;
      if (skybox != null) {
        skybox.source = _rebaseSkySource(skybox.source, documentDir, exists);
      }
      final skyEnvironment = resource.skyEnvironment;
      if (skyEnvironment != null) {
        skyEnvironment.source = _rebaseSkySource(
          skyEnvironment.source,
          documentDir,
          exists,
        );
      }
    }
  }
}

SkySourceSpec _rebaseSkySource(
  SkySourceSpec source,
  String documentDir,
  bool Function(String key)? exists,
) {
  if (source is! FmatSkySpec) return source;
  final rebased = _rebaseFmatKey(source.asset.key, documentDir, exists);
  if (rebased == null) return source;
  return FmatSkySpec(AssetRef(rebased), properties: source.properties);
}

/// [key] joined onto [documentDir] with `..` folding, or null when the key
/// is absolute, escapes the package root, or is already package-relative.
String? _rebaseFmatKey(
  String key,
  String documentDir,
  bool Function(String key)? exists,
) {
  final normalized = key.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
    return null;
  }
  final out = <String>[];
  for (final segment in [...documentDir.split('/'), ...normalized.split('/')]) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isEmpty) return null;
      out.removeLast();
      continue;
    }
    out.add(segment);
  }
  if (out.isEmpty) return null;
  final rebased = out.join('/');
  if (rebased == key) return null;
  // Nothing next to the document, so the ref is package-relative already.
  if (exists != null && !exists(rebased)) return null;
  return rebased;
}

/// Resolves the optional payload sidecar referenced by [document].
ExternalPayloadAsset? resolveExternalPayloadAsset(
  SceneDocument document,
  Uri sceneSourceUri,
) {
  final key = document.payloadSource;
  if (key == null) return null;
  final file = _resolveAssetFile(sceneSourceUri.resolve('.'), key);
  if (file == null) {
    throw FscenebFormatException(
      'Payload source "$key" referenced by the scene was not found on disk',
    );
  }
  return (key: key, file: file);
}

/// Attaches payload bytes from [asset] to matching manifest entries.
void inlineExternalPayloadAsset(
  SceneDocument document,
  ExternalPayloadAsset asset,
) {
  final source = readFsceneb(asset.file.readAsBytesSync());
  for (final entry in document.payloads.entries) {
    if (entry.value.bytes != null) continue;
    final supplied = source.payloads[entry.key];
    final bytes = supplied?.bytes;
    if (supplied == null || bytes == null) {
      throw FscenebFormatException(
        'Payload source ${asset.key} has no bytes for ${entry.key}',
      );
    }
    if (!_samePayloadDescriptor(entry.value, supplied)) {
      throw FscenebFormatException(
        'Payload source ${asset.key} has incompatible metadata for '
        '${entry.key}',
      );
    }
    entry.value.bytes = bytes;
  }
}

bool _samePayloadDescriptor(PayloadSpec a, PayloadSpec b) =>
    a.encoding == b.encoding &&
    a.layout == b.layout &&
    a.format == b.format &&
    a.width == b.width &&
    a.height == b.height &&
    a.length == b.length;

/// The distinct external image files [document] references, resolved relative to
/// the scene file at [sceneSourceUri].
///
/// Covers a [TextureResource.asset] and an environment resource's
/// [AssetEnvironment] image. Each key is resolved against the scene's directory
/// (how the editor saves them, e.g. `imported/wood.png`). A key that does not
/// resolve to an existing file is reported and skipped, so a missing image
/// degrades to its unresolved reference rather than failing the build. The
/// result is deduplicated by key, so an image several resources share is
/// returned once.
List<ExternalImageAsset> resolveExternalImageAssets(
  SceneDocument document,
  Uri sceneSourceUri,
) {
  final baseDir = sceneSourceUri.resolve('.');
  final seen = <String>{};
  final out = <ExternalImageAsset>[];
  void consider(String? key) {
    if (key == null || !seen.add(key)) return;
    final file = _resolveAssetFile(baseDir, key);
    if (file == null) {
      stderr.writeln(
        'flutter_scene buildScenes: image asset "$key" referenced by the scene '
        'was not found on disk; it will not be embedded',
      );
      return;
    }
    out.add((key: key, file: file));
  }

  for (final resource in document.resources.values) {
    if (resource is TextureResource) {
      consider(resource.asset?.key);
    } else if (resource is EnvironmentResource) {
      final environment = resource.environment;
      if (environment is AssetEnvironment) consider(environment.asset.key);
    }
  }
  return out;
}

/// Inlines each resolved [assets] file into [document], rewriting the resources
/// that referenced it to read the embedded payload instead of the external
/// asset.
///
/// A texture's image is decoded to an `rgba8` payload, or a supercompressed
/// KTX2 payload when [compressTextures] is set. An environment's image is
/// embedded as its encoded bytes, so HDR/EXR radiance is preserved. After this,
/// [writeFsceneb] embeds the bytes and realizing needs no asset-bundle lookup.
/// An image that fails to load is left as its external reference.
void inlineExternalImageAssets(
  SceneDocument document,
  List<ExternalImageAsset> assets, {
  bool compressTextures = false,
  bool alignForCompression = false,
}) {
  final fileByKey = {for (final asset in assets) asset.key: asset.file};
  // One payload per (key, kind): a texture wants rgba8, an environment wants the
  // encoded bytes, so a key used as both gets two payloads. A null entry caches
  // a decode failure so it is not retried.
  final texturePayloadByKey = <String, LocalId?>{};
  final environmentPayloadByKey = <String, LocalId>{};

  for (final entry in document.resources.entries.toList()) {
    final resource = entry.value;
    if (resource is TextureResource) {
      final key = resource.asset?.key;
      final file = key == null ? null : fileByKey[key];
      if (key == null || file == null) continue;
      final cacheKey = '$key|${resource.content}';
      final payload = texturePayloadByKey.putIfAbsent(
        cacheKey,
        () => _embedTexture(
          document,
          key,
          file,
          content: resource.content,
          compressTextures: compressTextures,
          alignForCompression: alignForCompression,
        ),
      );
      if (payload == null) continue;
      document.resources[entry.key] = TextureResource(
        resource.id,
        payload: payload,
        content: resource.content,
      );
    } else if (resource is EnvironmentResource) {
      final environment = resource.environment;
      if (environment is! AssetEnvironment) continue;
      final key = environment.asset.key;
      final file = fileByKey[key];
      if (file == null) continue;
      final payload = environmentPayloadByKey.putIfAbsent(
        key,
        () => _embedEncoded(document, key, file),
      );
      resource.environment = PayloadEnvironment(payload);
    }
  }
}

// Decodes [file] to a raw or compressed texture payload.
LocalId? _embedTexture(
  SceneDocument document,
  String key,
  File file, {
  required String content,
  required bool compressTextures,
  required bool alignForCompression,
}) {
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln(
      'flutter_scene buildScenes: could not decode image asset "$key"; '
      'leaving it as an external reference',
    );
    return null;
  }
  var image = decoded.convert(numChannels: 4, format: img.Format.uint8);
  var pixels = image.getBytes(order: img.ChannelOrder.rgba);
  if (compressTextures && !isBlockAligned(image.width, image.height)) {
    if (alignForCompression) {
      final originalWidth = image.width;
      final originalHeight = image.height;
      image = resampleToBlockAlignment(image);
      pixels = image.getBytes(order: img.ChannelOrder.rgba);
      sceneLog(
        'fscene: resampled a ${originalWidth}x$originalHeight texture to '
        '${image.width}x${image.height} to keep it compressed',
      );
    } else {
      sceneLog(
        'fscene: texture ${image.width}x${image.height} is not a multiple of '
        '4, storing it uncompressed. Resize it, or pass alignForCompression '
        'to resample it.',
      );
    }
  }
  final compress =
      compressTextures && isBlockAligned(image.width, image.height);
  final bytes = compress
      ? encodeImageToKtx2Bytes(
          pixels,
          image.width,
          image.height,
          generateMips: true,
          content: textureContentFromName(content),
          supercompress: true,
        )
      : pixels;
  return document
      .addPayload(
        PayloadSpec(
          document.newId(),
          encoding: PayloadEncoding.image,
          format: compress ? 'ktx2' : 'rgba8',
          width: image.width,
          height: image.height,
          length: bytes.length,
          bytes: bytes,
        ),
      )
      .id;
}

// Embeds [file]'s encoded bytes as an image payload tagged with its file
// extension, for an environment the realizer decodes itself (detecting the
// format from the bytes).
LocalId _embedEncoded(SceneDocument document, String key, File file) {
  final bytes = file.readAsBytesSync();
  return document
      .addPayload(
        PayloadSpec(
          document.newId(),
          encoding: PayloadEncoding.image,
          format: _imageFormat(key),
          length: bytes.length,
          bytes: bytes,
        ),
      )
      .id;
}

// The format tag for an image [key], from its extension (lowercased, no dot).
String _imageFormat(String key) {
  final dot = key.lastIndexOf('.');
  return dot < 0 ? 'bin' : key.substring(dot + 1).toLowerCase();
}

// Resolves an asset [key] against the scene's [baseDir], returning the file when
// it exists. Absolute or scheme-qualified keys are rejected (a saved scene
// references its imported assets by a relative path).
File? _resolveAssetFile(Uri baseDir, String key) {
  if (key.startsWith('/') || key.contains('://')) return null;
  final file = File.fromUri(baseDir.resolve(key));
  return file.existsSync() ? file : null;
}
