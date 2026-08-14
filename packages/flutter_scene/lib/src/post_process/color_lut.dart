import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// A parsed `.cube` table: the cube edge length and the red-fastest values.
typedef CubeTable = ({int size, Float32List values});

/// Parses the text of a `.cube` file into its table. Pure; the texture
/// upload lives in [ColorLut.fromCubeString].
@visibleForTesting
CubeTable parseCubeTable(String content) {
  var size = 0;
  Float32List? values;
  var cursor = 0;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final tokens = line.split(RegExp(r'\s+'));
    final keyword = tokens.first.toUpperCase();
    if (keyword == 'TITLE' ||
        keyword == 'DOMAIN_MIN' ||
        keyword == 'DOMAIN_MAX') {
      continue;
    }
    if (keyword == 'LUT_1D_SIZE') {
      throw ArgumentError('1D .cube tables are not supported.');
    }
    if (keyword == 'LUT_3D_SIZE') {
      size = int.parse(tokens[1]);
      if (size < 2 || size > 64) {
        throw ArgumentError('LUT_3D_SIZE must be between 2 and 64.');
      }
      values = Float32List(size * size * size * 3);
      continue;
    }
    final table = values;
    if (table == null || tokens.length < 3) {
      continue;
    }
    if (cursor + 3 > table.length) {
      throw ArgumentError('The .cube table has more rows than its size.');
    }
    table[cursor] = double.parse(tokens[0]);
    table[cursor + 1] = double.parse(tokens[1]);
    table[cursor + 2] = double.parse(tokens[2]);
    cursor += 3;
  }
  final table = values;
  if (table == null || cursor != table.length) {
    throw ArgumentError('The .cube table is missing rows.');
  }
  return (size: size, values: table);
}

/// Repacks a red-fastest cube table into the blue-slice strip's RGBA bytes.
@visibleForTesting
Uint8List packCubeStrip(CubeTable table) {
  final size = table.size;
  final values = table.values;
  final bytes = Uint8List(size * size * size * 4);
  final stripWidth = size * size;
  for (var i = 0; i < size * size * size; i++) {
    final r = i % size;
    final g = (i ~/ size) % size;
    final b = i ~/ (size * size);
    final pixel = (g * stripWidth + b * size + r) * 4;
    bytes[pixel] = (values[i * 3].clamp(0.0, 1.0) * 255.0).round();
    bytes[pixel + 1] = (values[i * 3 + 1].clamp(0.0, 1.0) * 255.0).round();
    bytes[pixel + 2] = (values[i * 3 + 2].clamp(0.0, 1.0) * 255.0).round();
    bytes[pixel + 3] = 255;
  }
  return bytes;
}

/// A 3D color-grading lookup table applied by the resolve pass.
///
/// Assign one to `ColorGradingSettings.lut` to grade the tone-mapped image
/// through a film look authored in any grading tool that exports the
/// Adobe/IRIDAS `.cube` format. The table is stored as a 2D strip of the
/// cube's blue slices, so it works on every backend without 3D textures.
///
/// The lookup happens on the display-encoded (sRGB) color after tone
/// mapping, matching how grading tools author display-referred looks.
/// {@category Rendering}
class ColorLut {
  ColorLut._(this.texture, this.size);

  /// The strip texture holding the cube's slices, `size * size` wide and
  /// `size` tall.
  final gpu.Texture texture;

  /// The cube's edge length.
  final int size;

  /// The asset path this table was loaded from, or null for one built from
  /// a string. Scene serialization persists the reference.
  String? get sourceAsset => _sourceAssets[this];

  /// Parses the text of a `.cube` file and uploads the table.
  ///
  /// Supports 3D tables up to edge length 64. `TITLE` and domain lines are
  /// tolerated; values are clamped to the [0, 1] display range.
  static ColorLut fromCubeString(String content) {
    final table = parseCubeTable(content);
    final bytes = packCubeStrip(table);
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      table.size * table.size,
      table.size,
    );
    texture.overwrite(ByteData.sublistView(bytes));
    return ColorLut._(texture, table.size);
  }

  /// Loads and parses a `.cube` asset.
  static Future<ColorLut> fromCubeAsset(String assetPath) async =>
      tagColorLutSource(
        fromCubeString(await rootBundle.loadString(assetPath)),
        assetPath,
      );
}

final Expando<String> _sourceAssets = Expando('ColorLut source asset');

/// Stamps [lut] with the [assetPath] it was loaded from (the scene realizer
/// loads through its own bundle) and returns it.
@internal
ColorLut tagColorLutSource(ColorLut lut, String assetPath) {
  _sourceAssets[lut] = assetPath;
  return lut;
}
