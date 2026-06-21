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

import '../fscene/scene_document.dart';
import '../fscene/specs.dart';

/// An external image file a scene references through a [TextureResource.asset],
/// resolved to a file on disk.
typedef ExternalImageAsset = ({String key, File file});

/// The distinct external image files [document]'s textures reference, resolved
/// relative to the scene file at [sceneSourceUri].
///
/// Each [TextureResource.asset] key is resolved against the scene's directory
/// (how the editor saves them, e.g. `imported/wood.png`). A key that does not
/// resolve to an existing file is reported and skipped, so a missing image
/// degrades to its unresolved reference rather than failing the build. The
/// result is deduplicated by key, so an image several textures share is returned
/// once.
List<ExternalImageAsset> resolveExternalImageAssets(
  SceneDocument document,
  Uri sceneSourceUri,
) {
  final baseDir = sceneSourceUri.resolve('.');
  final seen = <String>{};
  final out = <ExternalImageAsset>[];
  for (final resource in document.resources.values) {
    if (resource is! TextureResource) continue;
    final key = resource.asset?.key;
    if (key == null || !seen.add(key)) continue;
    final file = _resolveAssetFile(baseDir, key);
    if (file == null) {
      stderr.writeln(
        'flutter_scene buildScenes: image asset "$key" referenced by the scene '
        'was not found on disk; it will not be embedded',
      );
      continue;
    }
    out.add((key: key, file: file));
  }
  return out;
}

/// Inlines each resolved [assets] file into [document] as an embedded `rgba8`
/// image payload, rewriting every [TextureResource] that referenced it to point
/// at the payload instead of the external asset.
///
/// After this, the document carries the image bytes, so [writeFsceneb] embeds
/// them and the realized texture needs no asset-bundle lookup. An image that
/// fails to decode is left as its external reference (and reported).
void inlineExternalImageAssets(
  SceneDocument document,
  List<ExternalImageAsset> assets,
) {
  for (final asset in assets) {
    final decoded = img.decodeImage(asset.file.readAsBytesSync());
    if (decoded == null) {
      stderr.writeln(
        'flutter_scene buildScenes: could not decode image asset '
        '"${asset.key}"; leaving it as an external reference',
      );
      continue;
    }
    final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
    final raw = rgba.getBytes(order: img.ChannelOrder.rgba);
    final payload = document.addPayload(
      PayloadSpec(
        document.newId(),
        encoding: PayloadEncoding.image,
        format: 'rgba8',
        width: rgba.width,
        height: rgba.height,
        length: raw.length,
        bytes: raw,
      ),
    );
    // Repoint every texture that shared this asset at the one embedded payload.
    for (final entry in document.resources.entries.toList()) {
      final resource = entry.value;
      if (resource is TextureResource && resource.asset?.key == asset.key) {
        document.resources[entry.key] = TextureResource(
          resource.id,
          payload: payload.id,
        );
      }
    }
  }
}

// Resolves an asset [key] against the scene's [baseDir], returning the file when
// it exists. Absolute or scheme-qualified keys are rejected (a saved scene
// references its imported assets by a relative path).
File? _resolveAssetFile(Uri baseDir, String key) {
  if (key.startsWith('/') || key.contains('://')) return null;
  final file = File.fromUri(baseDir.resolve(key));
  return file.existsSync() ? file : null;
}
