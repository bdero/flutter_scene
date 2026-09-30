import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:image/image.dart' as img;

import 'package:scene/scene.dart' show sceneLog;

import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_tree.dart';
import '../importer/build_cache.dart';
import 'basisu/encode/etc1s_encoder.dart';
import 'block_alignment.dart';
import 'ktx2_image.dart';
import 'mipmap.dart';
import 'texture_encoding.dart';

export 'texture_encoding.dart' show TextureEncoding;

/// Controls where [buildTextures] puts generated `.fstex` assets.
enum TextureAssetMode {
  /// Cook the `.fstex` files into the app's `flutter_scene_generated/`
  /// directory and record them in its manifest, which `loadTexture` resolves by
  /// source path. The default, and identical on every Flutter channel.
  generatedTree,

  /// Require Dart data assets and fail the build when the current toolchain did
  /// not enable them for hooks.
  dataAssetsRequired,

  /// Removed. Kept so an upgraded hook fails with instructions instead
  /// of an undefined name.
  @Deprecated(
    'Removed in 0.21.0. Generated assets go into flutter_scene_generated/ and load by source path on every channel. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  legacyOnly,

  /// Removed. Kept so an upgraded hook fails with instructions instead
  /// of an undefined name.
  @Deprecated(
    'Removed in 0.21.0. Generated assets go into flutter_scene_generated/ and load by source path on every channel. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  dataAssetsIfAvailable,
}

// Where a data-asset build stages its files before registering them.
const String _dataAssetStagingDirectory = 'build/textures/';

const String _dataAssetsUnavailableMessage =
    'flutter_scene: TextureAssetMode.dataAssetsRequired needs Flutter support '
    'for Dart data assets, which this toolchain does not have enabled. Use '
    'TextureAssetMode.generatedTree (the default), which cooks the same '
    'textures into $generatedAssetsEntry on every channel.';

/// The extension of a cooked loose texture. The container is the engine's own
/// compressed block payload (a KTX2 wrapper around a format standard KTX2
/// tooling cannot read), so it gets an engine extension rather than `.ktx2`.
/// [TextureEncoding.etc1s] output is standard and keeps `.ktx2`.
const String textureOutputExtension = '.fstex';

/// Returns the DataAsset name for a generated texture output, where
/// [relativeTexturePath] is the source path relative to the package root with
/// its extension swapped to the cooked one (for example
/// `assets/shadow_plane.fstex`).
String textureDataAssetName(String relativeTexturePath) =>
    'flutter_scene/texture/$relativeTexturePath';

/// Cooks loose image assets into the engine's compressed texture container and
/// registers them so an app loads them by source path with `loadTexture`.
///
/// Each path in [textures] (relative to the package root, any format
/// `package:image` decodes) is encoded as a supercompressed block payload with
/// a full mip chain, written into the app's `flutter_scene_generated/`
/// directory with its extension swapped to `.fstex`, or registered as a
/// DataAsset under [TextureAssetMode.dataAssetsRequired].
/// At load time the payload transcodes to the device's supported block format
/// or decodes to rgba8 where none is supported.
///
/// [contents] optionally sets the downsample rule per source path; textures
/// not listed cook as [TextureContent.color] (sRGB, averaged in linear
/// light). Use [TextureContent.normal] for tangent-space normal maps and
/// [TextureContent.data] for non-color data.
///
/// [encoding] picks the stored format and [encodings] overrides it per
/// source path; see [TextureEncoding].
///
/// Source images must be block-aligned (width and height multiples of 4);
/// misaligned images fail the build, or are resampled up to the next multiple
/// when [alignForCompression] is set.
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
///       assetMode: TextureAssetMode.dataAssetsRequired,
///     );
///   });
/// }
/// ```
void buildTextures({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required List<String> textures,
  Map<String, TextureContent> contents = const {},
  TextureEncoding encoding = TextureEncoding.universal,
  Map<String, TextureEncoding> encodings = const {},
  TextureAssetMode assetMode = TextureAssetMode.generatedTree,
  bool alignForCompression = false,
}) {
  // A typo here would silently cook a normal map with the sRGB color
  // downsample (or in the wrong format), so unknown keys fail the build.
  for (final (name, keys) in [
    ('contents', contents.keys),
    ('encodings', encodings.keys),
  ]) {
    final unknown = keys.where((key) => !textures.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw Exception(
        '$name names sources that are not listed in textures: '
        '${unknown.join(', ')}. Fix the path or add it to textures.',
      );
    }
  }
  // A quality computed in the hook skips the constructor's assert.
  for (final (source, value) in [
    ('encoding', encoding),
    for (final MapEntry(:key, :value) in encodings.entries) (key, value),
  ]) {
    if (value.isEtc1s && (value.quality < 1 || value.quality > 255)) {
      throw ArgumentError(
        'ETC1S quality for $source must be 1 to 255, got ${value.quality}.',
      );
    }
  }

  // ignore: deprecated_member_use_from_same_package
  if (assetMode == TextureAssetMode.legacyOnly) {
    throwRemovedAssetMode(
      'TextureAssetMode.legacyOnly',
      'TextureAssetMode.generatedTree',
    );
  }
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == TextureAssetMode.dataAssetsIfAvailable) {
    throwRemovedAssetMode(
      'TextureAssetMode.dataAssetsIfAvailable',
      'TextureAssetMode.generatedTree',
    );
  }
  final emitDataAssets = assetMode == TextureAssetMode.dataAssetsRequired;
  if (emitDataAssets && !buildInput.config.buildDataAssets) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }

  final options = HookOptions.of(buildInput);
  final packageRoot = buildInput.packageRoot;
  final texturesRoot = packageRoot.resolve(_dataAssetStagingDirectory);

  if (emitDataAssets) {
    // A tree left by an earlier build would ship the same textures twice, so
    // the data assets this run registers replace it.
    GeneratedAssetTree.openExisting(packageRoot, buildInput.packageName)
      ?..dropOwned(GeneratedAssetFamily.texture, owner: buildInput.packageName)
      ..save();
  }

  // The outputs go into the app's persistent flutter_scene_generated/ tree,
  // whose manifest maps each source path to its cooked texture (and stores the
  // build stamp).
  final tree = emitDataAssets
      ? null
      : GeneratedAssetTree.open(
          packageRoot,
          buildInput.packageName,
          options: options,
        );
  if (tree != null &&
      (textures.isNotEmpty || tree.hasFamily(GeneratedAssetFamily.texture))) {
    tree.requireAssetEntry();
  }

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
    final dot = inputFilePath.lastIndexOf('.');
    final slash = inputFilePath.lastIndexOf('/');
    final stem = dot > slash ? inputFilePath.substring(0, dot) : inputFilePath;
    final textureEncoding = encodings[inputFilePath] ?? encoding;
    final extension = textureEncoding.fileExtension;
    final relativeTexturePath = '$stem$extension';
    final outputTextureUri =
        tree?.fileUri(
          GeneratedAssetFamily.texture,
          nameId: stem,
          extension: extension,
        ) ??
        texturesRoot.resolve(relativeTexturePath);
    Directory.fromUri(
      outputTextureUri.resolve('.'),
    ).createSync(recursive: true);

    final content = contents[inputFilePath] ?? TextureContent.color;
    final encodingStamp = textureEncoding.isEtc1s
        ? ' encoding=etc1s/${textureEncoding.quality}'
        : '';
    final stamp =
        'rev=$buildCacheRevision texture content=${content.name}'
        '$encodingStamp '
        'src=${sourceFingerprint(sourceFile, strict: options.strictHashing)}';
    final stampFile = File('${outputTextureUri.toFilePath()}.inputs');
    // The generated tree ships every file in it, so the stamp lives in the
    // manifest there rather than in a sidecar next to the output.
    final fresh = tree != null
        ? tree.isFresh(GeneratedAssetFamily.texture, stem, stamp, [
            outputTextureUri,
          ])
        : isBuildCacheFresh(stampFile, stamp, [
            File(outputTextureUri.toFilePath()),
          ]);
    if (!fresh) {
      stdout.writeln('flutter_scene: cooking $inputFilePath');
      final decoded = img.decodeImage(sourceFile.readAsBytesSync());
      if (decoded == null) {
        throw Exception('Could not decode image: $inputFilePath');
      }
      // The compressed formats are 4x4 block formats; a misaligned base level
      // is rejected at GPU load on devices that take the compressed path.
      var source = decoded;
      if (!isBlockAligned(source.width, source.height)) {
        if (!alignForCompression) {
          throw Exception(
            'Texture dimensions must be multiples of 4 (the compressed block '
            'size): $inputFilePath is ${decoded.width}x${decoded.height}. '
            'Resize the image, or pass alignForCompression to resample it.',
          );
        }
        source = resampleToBlockAlignment(source);
        sceneLog(
          'flutter_scene: resampled $inputFilePath from '
          '${decoded.width}x${decoded.height} to '
          '${source.width}x${source.height} for block alignment',
        );
      }
      final rgba = source.convert(numChannels: 4, format: img.Format.uint8);
      final pixels = rgba.getBytes(order: img.ChannelOrder.rgba);
      // TODO(etc1s-fscene-textures): textures embedded in .fscene/.fsceneb
      // still cook to the engine's format; offer ETC1S to scene builds too.
      writeGeneratedBytes(
        outputTextureUri,
        textureEncoding.isEtc1s
            ? encodeEtc1sKtx2(
                pixels,
                rgba.width,
                rgba.height,
                options: Etc1sEncodeOptions(
                  quality: textureEncoding.quality,
                  content: content,
                ),
              )
            : encodeImageToKtx2Bytes(
                pixels,
                rgba.width,
                rgba.height,
                generateMips: true,
                content: content,
                supercompress: true,
              ),
      );
      if (tree == null) stampFile.writeAsStringSync(stamp);
    }
    tree?.recordFile(
      family: GeneratedAssetFamily.texture,
      id: stem,
      uri: outputTextureUri,
      stamp: stamp,
      source: inputFilePath,
    );

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

  if (tree != null) {
    tree
      ..pruneMissingSources()
      ..save();
  }
}
