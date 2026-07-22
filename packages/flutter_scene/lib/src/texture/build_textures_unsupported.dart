/// Web/wasm stub for the texture build-hook helper. The real [buildTextures]
/// uses `dart:io` to write `.fstex` files and only runs on the native build
/// host (from a consumer's `hook/build.dart`). Routing the web/wasm import
/// here keeps `dart:io` (and `package:hooks`) off the wasm dependency graph,
/// so the package stays WASM-compatible. Calling it on web/wasm is never
/// expected.
library;

import 'mipmap.dart';

/// Web/wasm placeholder for the native build-hook enum.
enum TextureAssetMode { legacyOnly, dataAssetsIfAvailable, dataAssetsRequired }

/// Throws on web/wasm; see the library doc above. The native signature takes a
/// `BuildInput` / `BuildOutputBuilder` from `package:hooks`; this stub uses
/// `Object` instead so it pulls in no `dart:io`.
Never buildTextures({
  required Object buildInput,
  required Object buildOutput,
  required List<String> textures,
  Map<String, TextureContent> contents = const {},
  String outputDirectory = 'build/textures/',
  TextureAssetMode assetMode = TextureAssetMode.legacyOnly,
}) => throw UnsupportedError(
  'buildTextures runs at build time on native platforms only.',
);
