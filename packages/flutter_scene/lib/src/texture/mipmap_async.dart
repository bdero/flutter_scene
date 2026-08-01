// The off-thread mip chain build. Split from mipmap.dart because that file is
// re-exported by `build_hooks.dart`, and a build hook runs on the plain Dart
// VM where `package:flutter` (and so `dart:ui`) cannot be resolved.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'mipmap.dart';

/// Builds the mip chain for [pixels] on a background isolate, so a large
/// texture does not block the caller while it downsamples.
///
/// The synchronous [generateMipChain] stays for the sync realize path, which
/// cannot await.
Future<List<MipLevel>> generateMipChainAsync(
  Uint8List pixels,
  int width,
  int height,
  TextureContent content,
) => compute(_generateMipChain, (
  pixels: pixels,
  width: width,
  height: height,
  content: content,
));

/// Isolate entry point. Pure Dart, no GPU.
List<MipLevel> _generateMipChain(
  ({Uint8List pixels, int width, int height, TextureContent content}) input,
) => generateMipChain(input.pixels, input.width, input.height, input.content);
