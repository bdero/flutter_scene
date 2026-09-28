// Regenerates the ETC1S encoder fixtures after an intentional encoder
// change, then their basisu decodes:
//
//   dart run tool/encode_etc1s_fixtures.dart
//   node tool/etc1s_goldens.mjs <basisu_st.wasm> --rgba \
//     etc1s_encoded_features_q128 etc1s_encoded_odd_q64 \
//     etc1s_encoded_shapes_q255

import 'dart:io';

import 'package:flutter_scene/src/texture/basisu/encode/etc1s_encoder.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:image/image.dart' as img;

/// Each fixture: its source image, its output name, and the settings.
const List<(String, String, Etc1sEncodeOptions)> etc1sEncoderFixtures = [
  (
    'etc1s_features_rgba_64.png',
    'etc1s_encoded_features_q128',
    Etc1sEncodeOptions(),
  ),
  (
    'etc1s_source_odd_17x9.png',
    'etc1s_encoded_odd_q64',
    Etc1sEncodeOptions(quality: 64, content: TextureContent.data),
  ),
  (
    'etc1s_source_shapes_96x80.png',
    'etc1s_encoded_shapes_q255',
    Etc1sEncodeOptions(quality: 255, mipmaps: false),
  ),
];

void main() {
  const directory = 'test/fixtures/ktx2';
  for (final (source, name, options) in etc1sEncoderFixtures) {
    final image = img
        .decodePng(File('$directory/$source').readAsBytesSync())!
        .convert(numChannels: 4, format: img.Format.uint8);
    final bytes = encodeEtc1sKtx2(
      image.getBytes(order: img.ChannelOrder.rgba),
      image.width,
      image.height,
      options: options,
    );
    File('$directory/$name.ktx2').writeAsBytesSync(bytes);
    stdout.writeln('$name.ktx2: ${bytes.length} bytes');
  }
}
