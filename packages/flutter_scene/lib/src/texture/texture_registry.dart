/// Resolves and loads the `.fstex` compressed textures the `buildTextures` build
/// hook cooked, keyed by source path (the texture counterpart of `loadScene` /
/// `loadFmatMaterial`).
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/services.dart';

import '../generated_assets/generated_asset_lookup.dart';
import '../generated_assets/generated_assets.dart';
import '../gpu/gpu.dart' as gpu;
import '../hot_reload/hot_reload_coordinator.dart';
import 'compressed_texture.dart';
import 'texture2d.dart';

const String _textureAssetMarker = 'flutter_scene/texture/';
const String _textureAssetSuffix = '.fstex';

/// One resolved cooked `.fstex`.
final class TextureEntry {
  TextureEntry({
    required this.assetKey,
    required this.package,
    required this.textureId,
  });

  /// The full Flutter asset-bundle key, e.g.
  /// `packages/<package>/flutter_scene/texture/assets/shadow_plane.fstex`.
  final String assetKey;

  /// The owning package.
  final String package;

  /// The source path relative to [package]'s root, without extension.
  final String textureId;

  static TextureEntry? tryParse(String assetKey) {
    if (!TextureRegistry.isTextureAssetKey(assetKey)) return null;
    final rest = assetKey.substring('packages/'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final package = rest.substring(0, slash);
    final afterPackage = rest.substring(slash + 1);
    if (!afterPackage.startsWith(_textureAssetMarker)) return null;
    final relativeTexturePath = afterPackage.substring(
      _textureAssetMarker.length,
    );
    final textureId = relativeTexturePath.substring(
      0,
      relativeTexturePath.length - _textureAssetSuffix.length,
    );
    return TextureEntry(
      assetKey: assetKey,
      package: package,
      textureId: textureId,
    );
  }
}

/// Uploaded textures shared across [loadTexture] calls, keyed by asset key,
/// so repeated loads of the same source share one GPU texture (and every
/// holder sees the same hot-reload swap).
final Map<String, _TextureCacheEntry> _textureCache = {};

/// One cached texture plus the number of outstanding [loadTexture] calls that
/// have not been released. The count exists so releasing one holder's claim
/// cannot pull the texture out from under another holder that is still
/// drawing with it.
final class _TextureCacheEntry {
  _TextureCacheEntry(this.source) {
    // Kept so the footprint can be read synchronously; a texture still loading
    // has no size to report yet.
    // A failed load leaves it unresolved and uncounted.
    source.then<void>((s) => _resolved = s).catchError((Object _) {});
  }

  final Future<_ReloadableTextureSource> source;
  int holders = 0;
  _ReloadableTextureSource? _resolved;

  gpu.Texture? get resolvedTexture => _resolved?.sampledTexture;
}

/// The live handle [loadTexture] returns. Materials re-resolve
/// [sampledTexture] at bind time, so swapping the GPU texture here (the
/// hot-reload path) updates every bound material on its next frame.
final class _ReloadableTextureSource implements TextureSource {
  _ReloadableTextureSource(gpu.Texture texture) {
    _swap(texture);
  }

  late gpu.Texture _texture;
  late gpu.SamplerOptions _sampler;

  void _swap(gpu.Texture texture) {
    _texture = texture;
    // Borrow GpuTextureSource's default sampler (trilinear repeat when the
    // texture carries mips), recomputed since a reload can change the chain.
    _sampler = GpuTextureSource(texture).sampler;
  }

  @override
  gpu.Texture? get sampledTexture => _texture;

  @override
  gpu.SamplerOptions get sampledSampler => _sampler;
}

/// A caller's sampling override of a shared [_ReloadableTextureSource]. The
/// texture is delegated (so hot-reload swaps still propagate); only the
/// sampler differs.
final class _SampledTextureView implements TextureSource {
  _SampledTextureView(this._source, this._sampler);

  final _ReloadableTextureSource _source;
  final gpu.SamplerOptions _sampler;

  @override
  gpu.Texture? get sampledTexture => _source.sampledTexture;

  @override
  gpu.SamplerOptions get sampledSampler => _sampler;
}

/// Resolves generated `.fstex` textures by source path.
final class TextureRegistry {
  TextureRegistry._(this._entries);

  final List<TextureEntry> _entries;

  /// Loads the registry by scanning the asset manifest for `.fstex` data
  /// assets, then the generated tree's manifest for everything else.
  static Future<TextureRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final entries = keys
        .map(TextureEntry.tryParse)
        .whereType<TextureEntry>()
        .toList();
    if (assetKeys == null) {
      final generated = await loadGeneratedAssetIndex(bundle);
      for (final match in generated.entriesOf(GeneratedAssetFamily.texture)) {
        // A data asset wins over a tree entry for the same texture.
        if (entries.any(
          (entry) =>
              entry.textureId == match.entry.id &&
              entry.package == match.entry.owner,
        )) {
          continue;
        }
        entries.add(
          TextureEntry(
            assetKey: match.key,
            package: match.entry.owner,
            textureId: match.entry.id,
          ),
        );
      }
    }
    entries.sort((a, b) => a.assetKey.compareTo(b.assetKey));
    return TextureRegistry._(entries);
  }

  /// Returns true when [assetKey] is a generated `.fstex` data asset.
  static bool isTextureAssetKey(String assetKey) =>
      assetKey.startsWith('packages/') &&
      assetKey.contains('/$_textureAssetMarker') &&
      assetKey.endsWith(_textureAssetSuffix);

  /// Resolves [sourcePath] (relative to the owning package's root, with or
  /// without its image extension) to exactly one texture asset key.
  String resolveKey(String sourcePath, {String? package}) {
    final id = _textureId(sourcePath);
    final matches = _entries
        .where(
          (entry) =>
              entry.textureId == id &&
              (package == null || entry.package == package),
        )
        .toList();
    if (matches.isEmpty) {
      throw StateError(
        'No cooked .fstex for source "$sourcePath" was found. Make sure '
        'buildTextures lists this source. '
        '${generatedAssetFixHint('textures')}',
      );
    }
    if (matches.length > 1) {
      final choices = matches.map((match) => match.package).join(', ');
      throw StateError(
        'Multiple cooked .fstex files for source "$sourcePath" were found in '
        'packages: $choices. Pass package to disambiguate.',
      );
    }
    return matches.single.assetKey;
  }

  static Future<List<String>> _loadAssetManifestKeys(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets();
  }
}

// The source path without its final extension (the cooked asset swaps it for
// `.fstex`), so callers can pass `assets/shadow_plane.png` or
// `assets/shadow_plane`.
String _textureId(String sourcePath) {
  final dot = sourcePath.lastIndexOf('.');
  final slash = sourcePath.lastIndexOf('/');
  return dot > slash ? sourcePath.substring(0, dot) : sourcePath;
}

/// Loads a cooked compressed texture by its source path relative to the owning
/// package's root (for example `assets/shadow_plane.png`), ready to assign to
/// a material texture slot.
///
/// The texture must have been cooked by the `buildTextures` build hook. The
/// payload transcodes to a device-supported block format
/// (or decodes to rgba8) off the main isolate, uploads with its full mip
/// chain, and is cached, so repeated loads of the same source share one GPU
/// texture. In debug builds the texture hot reloads: editing the source image
/// re-cooks it and the next hot reload swaps the new texture into every bound
/// material in place.
///
/// The default sampling is trilinear repeat; pass [sampling] to override it
/// (the underlying GPU texture stays shared). Prefer [sampling] over wrapping
/// the returned source's raw texture yourself, which would pin the texture
/// handle and stop hot reload from reaching that holder. Pass [package] to
/// disambiguate when the same source path is provided by more than one
/// package.
/// {@category Assets and loading}
Future<TextureSource> loadTexture(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
  TextureSampling? sampling,
}) async {
  final assetBundle = bundle ?? rootBundle;
  Future<Uint8List> loadBytes(String key) async {
    final data = await assetBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  final registry = await TextureRegistry.load(bundle: bundle);
  final key = registry.resolveKey(sourcePath, package: package);
  final entry = _textureCache.putIfAbsent(
    key,
    () => _TextureCacheEntry(() async {
      final source = _ReloadableTextureSource(
        await gpuTextureFromKtx2Async(await loadBytes(key)),
      );
      HotReloadCoordinator.instance.registerTexture(
        source,
        assetKey: key,
        bundle: assetBundle,
        onReload: () async =>
            source._swap(await gpuTextureFromKtx2Async(await loadBytes(key))),
      );
      return source;
    }()),
  );
  entry.holders++;
  final _ReloadableTextureSource source;
  try {
    source = await entry.source;
  } catch (_) {
    // Do not pin a failed load; the next call retries it.
    entry.holders--;
    if (identical(_textureCache[key], entry)) {
      _textureCache.remove(key);
    }
    rethrow;
  }
  if (sampling == null) return source;
  return _SampledTextureView(source, sampling.toSamplerOptions());
}

/// Releases one claim on the texture [loadTexture] returned for [sourcePath],
/// dropping it from the shared cache when no claims remain.
///
/// Returns whether the cache entry was dropped. Every [loadTexture] call takes
/// a claim, so a texture two callers loaded needs two releases before it
/// leaves the cache; releasing one holder's claim never pulls the texture out
/// from under the other.
///
/// Dropping the entry releases the engine's reference, not the memory. A
/// texture a live material still points at stays resident until that reference
/// goes too, and the GPU allocation is reclaimed after that on the engine's
/// schedule rather than at this call. See `Scene.memoryReport` for what is
/// actually resident.
/// {@category Assets and loading}
Future<bool> releaseTexture(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
}) async {
  final registry = await TextureRegistry.load(bundle: bundle);
  final key = registry.resolveKey(sourcePath, package: package);
  return releaseTextureByAssetKey(key);
}

/// [releaseTexture] by resolved asset key, for callers that already have one.
@internal
bool releaseTextureByAssetKey(String assetKey) {
  final entry = _textureCache[assetKey];
  if (entry == null) return false;
  entry.holders--;
  if (entry.holders > 0) return false;
  _textureCache.remove(assetKey);
  return true;
}

/// Drops every cached texture, whatever their outstanding claims.
///
/// The blunt instrument, for tearing down a whole world at once. Prefer
/// [releaseTexture] where the caller knows what it loaded. Textures a live
/// scene still references stay resident until those references go.
/// {@category Assets and loading}
void clearTextureCache() => _textureCache.clear();

/// Resident bytes and count of the textures held by the shared cache.
///
/// Sums each texture's whole mip chain, so it is the real GPU footprint of
/// what the cache is pinning rather than an estimate. Textures still loading
/// are not counted, since their size is not known yet.
@internal
({int bytes, int count}) textureCacheFootprint() {
  var bytes = 0;
  var count = 0;
  for (final entry in _textureCache.values) {
    final texture = entry.resolvedTexture;
    if (texture == null) continue;
    count++;
    bytes += gpuTextureBytes(texture);
  }
  return (bytes: bytes, count: count);
}

/// The resident size of [texture], summed across its mip chain.
@internal
int gpuTextureBytes(gpu.Texture texture) {
  var bytes = 0;
  for (var level = 0; level < texture.mipLevelCount; level++) {
    bytes += texture.getMipLevelSizeInBytes(level);
  }
  return bytes;
}
