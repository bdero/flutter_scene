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

import '../fscene/id.dart';
import '../fscene/scene_document.dart';
import '../fscene/specs.dart';

/// An external image file a scene references through a [TextureResource.asset],
/// resolved to a file on disk.
typedef ExternalImageAsset = ({String key, File file});

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
/// A texture's image is decoded to an `rgba8` payload (the realizer uploads it
/// directly). An environment's image is embedded as its encoded bytes with a
/// format tag (`hdr` for Radiance HDR, the file extension otherwise), so the
/// realizer decodes it with the right path (HDR float decode preserves the
/// radiance range, unlike an `rgba8` clamp). After this, [writeFsceneb] embeds
/// the bytes and realizing needs no asset-bundle lookup. An image that fails to
/// load is left as its external reference (and reported).
void inlineExternalImageAssets(
  SceneDocument document,
  List<ExternalImageAsset> assets,
) {
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
      final payload = texturePayloadByKey.putIfAbsent(
        key,
        () => _embedRgba8(document, key, file),
      );
      if (payload == null) continue;
      document.resources[entry.key] = TextureResource(
        resource.id,
        payload: payload,
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

// Decodes [file] to an rgba8 image payload and returns its id, or null when it
// cannot be decoded.
LocalId? _embedRgba8(SceneDocument document, String key, File file) {
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln(
      'flutter_scene buildScenes: could not decode image asset "$key"; '
      'leaving it as an external reference',
    );
    return null;
  }
  final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
  final raw = rgba.getBytes(order: img.ChannelOrder.rgba);
  return document
      .addPayload(
        PayloadSpec(
          document.newId(),
          encoding: PayloadEncoding.image,
          format: 'rgba8',
          width: rgba.width,
          height: rgba.height,
          length: raw.length,
          bytes: raw,
        ),
      )
      .id;
}

// Embeds [file]'s encoded bytes as an image payload tagged with its format
// (`hdr` for Radiance HDR, the file extension otherwise), for an environment the
// realizer decodes itself.
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
