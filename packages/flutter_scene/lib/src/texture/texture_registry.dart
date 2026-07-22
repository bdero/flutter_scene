/// Resolves and loads `.fstex` compressed textures registered through
/// DataAssets by the `buildTextures` build hook, keyed by source path (the
/// texture counterpart of `loadScene` / `loadFmatMaterial`).
library;

import 'package:flutter/services.dart';

import '../gpu/gpu.dart' as gpu;
import '../hot_reload/hot_reload_coordinator.dart';
import 'compressed_texture.dart';
import 'texture2d.dart';

const String _textureAssetMarker = 'flutter_scene/texture/';
const String _textureAssetSuffix = '.fstex';

/// One resolved `.fstex` DataAsset.
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
final Map<String, Future<_ReloadableTextureSource>> _textureCache = {};

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

/// Resolves DataAssets-backed `.fstex` textures by source path.
final class TextureRegistry {
  TextureRegistry._(this._entries);

  final List<TextureEntry> _entries;

  /// Loads the registry by scanning the asset manifest for `.fstex`
  /// DataAssets.
  static Future<TextureRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final entries =
        keys.map(TextureEntry.tryParse).whereType<TextureEntry>().toList()
          ..sort((a, b) => a.assetKey.compareTo(b.assetKey));
    return TextureRegistry._(entries);
  }

  /// Returns true when [assetKey] is a generated `.fstex` DataAsset.
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
        'No DataAssets-backed .fstex for source "$sourcePath" was found. '
        'Make sure the build hook calls buildTextures in a DataAssets mode '
        'with this source listed, that Dart data assets are enabled (flutter '
        'config --enable-dart-data-assets), and that the app has been '
        'rebuilt.',
      );
    }
    if (matches.length > 1) {
      final choices = matches.map((match) => match.package).join(', ');
      throw StateError(
        'Multiple DataAssets-backed .fstex files for source "$sourcePath" '
        'were found in packages: $choices. Pass package to disambiguate.',
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
/// The texture must have been cooked by the `buildTextures` build hook in a
/// DataAssets mode. The payload transcodes to a device-supported block format
/// (or decodes to rgba8) off the main isolate, uploads with its full mip
/// chain, and is cached, so repeated loads of the same source share one GPU
/// texture. In debug builds the texture hot reloads: editing the source image
/// re-cooks it and the next hot reload swaps the new texture into every bound
/// material in place. Pass [package] to disambiguate when the same source
/// path is provided by more than one package.
/// {@category Assets and loading}
Future<TextureSource> loadTexture(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
}) {
  final assetBundle = bundle ?? rootBundle;
  Future<Uint8List> loadBytes(String key) async {
    final data = await assetBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  return TextureRegistry.load(bundle: bundle).then((registry) {
    final key = registry.resolveKey(sourcePath, package: package);
    return _textureCache.putIfAbsent(key, () async {
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
    });
  });
}
