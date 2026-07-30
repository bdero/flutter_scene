import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:image/image.dart' as img;

import '../importer/build_cache.dart';
import 'ktx2_image.dart';
import 'mipmap.dart';

/// Controls how [buildTextures] exposes generated `.fstex` assets.
enum TextureAssetMode {
  /// Only write the generated `.fstex` files under `build/textures/`. The app
  /// lists them in `flutter.assets` and loads them by explicit asset key;
  /// `loadTexture` (source-path resolution) needs a DataAssets mode.
  legacyOnly,

  /// Register generated `.fstex` files as DataAssets when the current
  /// toolchain supports them, and otherwise fall back to [legacyOnly].
  dataAssetsIfAvailable,

  /// Require DataAssets support and fail the build with a targeted migration
  /// message when the current toolchain did not enable data assets for hooks.
  dataAssetsRequired,
}

const String _dataAssetsUnavailableMessage =
    'flutter_scene DataAssets mode requires Flutter support for Dart data '
    'assets. This feature is currently experimental and available on supported '
    'Flutter master builds. Run `flutter config --enable-dart-data-assets` or '
    'set `FLUTTER_DART_DATA_ASSETS=true`, then rebuild. If your Flutter '
    'toolchain does not recognize that setting, switch to a Flutter master '
    'channel build, or use TextureAssetMode.legacyOnly, list the generated '
    '`build/textures/*.fstex` files in `flutter.assets`, and load them by '
    'asset key.';

/// The extension of a cooked loose texture. The container is the engine's own
/// compressed block payload (a KTX2 wrapper around a format standard KTX2
/// tooling cannot read), so it gets an engine extension rather than `.ktx2`.
const String textureOutputExtension = '.fstex';

/// Returns the DataAsset name for a generated `.fstex` output, where
/// [relativeTexturePath] is the source path relative to the package root with
/// its extension swapped to `.fstex` (for example `assets/shadow_plane.fstex`).
String textureDataAssetName(String relativeTexturePath) =>
    'flutter_scene/texture/$relativeTexturePath';

/// Cooks loose image assets into the engine's compressed texture container and
/// registers them so an app loads them by source path with `loadTexture`.
///
/// Each path in [textures] (relative to the package root, any format
/// `package:image` decodes) is encoded as a supercompressed block payload with
/// a full mip chain, written under [outputDirectory] with its extension
/// swapped to `.fstex`, and (in a DataAssets mode) registered as a DataAsset.
/// At load time the payload transcodes to the device's supported block format
/// or decodes to rgba8 where none is supported.
///
/// [contents] optionally sets the downsample rule per source path; textures
/// not listed cook as [TextureContent.color] (sRGB, averaged in linear
/// light). Use [TextureContent.normal] for tangent-space normal maps and
/// [TextureContent.data] for non-color data.
///
/// Source images must be block-aligned (width and height multiples of 4);
/// misaligned images fail the build.
///
/// Call this from a consuming app's `hook/build.dart`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     buildTextures(
///       buildInput: config,
///       buildOutput: output,
///       textures: ['assets/shadow_plane.png'],
///       assetMode: TextureAssetMode.dataAssetsIfAvailable,
///     );
///   });
/// }
/// ```
void buildTextures({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required List<String> textures,
  Map<String, TextureContent> contents = const {},
  String outputDirectory = 'build/textures/',
  TextureAssetMode assetMode = TextureAssetMode.legacyOnly,
}) {
  // A typo here would silently cook a normal map with the sRGB color
  // downsample, so unknown keys fail the build instead.
  final unknownContentKeys = contents.keys
      .where((key) => !textures.contains(key))
      .toList();
  if (unknownContentKeys.isNotEmpty) {
    throw Exception(
      'contents names sources that are not listed in textures: '
      '${unknownContentKeys.join(', ')}. Fix the path or add it to textures.',
    );
  }

  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (assetMode == TextureAssetMode.dataAssetsRequired &&
      !dataAssetsAvailable) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }
  final emitDataAssets =
      assetMode != TextureAssetMode.legacyOnly && dataAssetsAvailable;

  final packageRoot = buildInput.packageRoot;
  final texturesRoot = packageRoot.resolve(outputDirectory);

  for (final inputFilePath in textures) {
    if (inputFilePath.startsWith('../') || inputFilePath.contains('/../')) {
      throw Exception(
        'Texture source must be inside the package: $inputFilePath. Place it '
        'under the package (for example in assets/), using a symlink if '
        'needed.',
      );
    }
    final sourceUri = packageRoot.resolve(inputFilePath);
    final sourceFile = File(sourceUri.toFilePath());
    if (!sourceFile.existsSync()) {
      throw Exception(
        'Texture source not found: $inputFilePath (resolved to '
        '${sourceFile.path})',
      );
    }
    final sourceBytes = sourceFile.readAsBytesSync();

    final dot = inputFilePath.lastIndexOf('.');
    final slash = inputFilePath.lastIndexOf('/');
    final stem = dot > slash ? inputFilePath.substring(0, dot) : inputFilePath;
    final relativeTexturePath = '$stem$textureOutputExtension';
    final outputTextureUri = texturesRoot.resolve(relativeTexturePath);
    Directory.fromUri(
      outputTextureUri.resolve('.'),
    ).createSync(recursive: true);

    final content = contents[inputFilePath] ?? TextureContent.color;
    final stamp =
        'rev=$buildCacheRevision texture content=${content.name} '
        'src=${contentHash(sourceBytes)}';
    final stampFile = File('${outputTextureUri.toFilePath()}.inputs');
    if (!isBuildCacheFresh(stampFile, stamp, [
      File(outputTextureUri.toFilePath()),
    ])) {
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        throw Exception('Could not decode image: $inputFilePath');
      }
      // The compressed formats are 4x4 block formats; a misaligned base level
      // is rejected at GPU load on devices that take the compressed path.
      // TODO(texture-compression): pad/rescale to a multiple of 4 (adjusting
      // UVs is not an option here, so resample) so these can be cooked too.
      if (decoded.width % 4 != 0 || decoded.height % 4 != 0) {
        throw Exception(
          'Texture dimensions must be multiples of 4 (the compressed block '
          'size): $inputFilePath is ${decoded.width}x${decoded.height}. '
          'Resize the image.',
        );
      }
      final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
      File(outputTextureUri.toFilePath()).writeAsBytesSync(
        encodeImageToKtx2Bytes(
          rgba.getBytes(order: img.ChannelOrder.rgba),
          rgba.width,
          rgba.height,
          generateMips: true,
          content: content,
          supercompress: true,
        ),
      );
      stampFile.writeAsStringSync(stamp);
    }

    buildOutput.dependencies.add(sourceUri);
    if (emitDataAssets) {
      buildOutput.assets.data.add(
        DataAsset(
          package: buildInput.packageName,
          name: textureDataAssetName(relativeTexturePath),
          file: outputTextureUri,
        ),
      );
    }
  }
}
