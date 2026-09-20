// Regenerates `assets/dfg.bin`, the precomputed split-sum environment-BRDF
// (DFG) table the PBR and fmat lighting sample, so no app pays the
// 4.19-million-sample Monte-Carlo integration at startup.
//
//   dart run tool/generate_dfg_lut.dart
//
// The output is the same bytes `buildDfgLutHalfData()` returns (64x64 RGBA
// half-float, little-endian), which `test/dfg_lut_asset_test.dart` re-checks.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/material/dfg_lut_data.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'assets/dfg.bin';
  final watch = Stopwatch()..start();
  final half = buildDfgLutHalfData();
  watch.stop();
  final bytes = Uint8List.view(
    half.buffer,
    half.offsetInBytes,
    half.lengthInBytes,
  );
  if (Endian.host != Endian.little) {
    // The runtime reads the asset through `ByteBuffer.asUint16List`, which is
    // host-endian; the shipped file is little-endian.
    throw StateError('Generate the asset on a little-endian host.');
  }
  File(path).writeAsBytesSync(bytes);
  stdout.writeln(
    'Wrote $path (${bytes.length} bytes, ${kDfgLutSize}x$kDfgLutSize RGBA16F, '
    '$kDfgLutSampleCount samples/texel) in ${watch.elapsedMilliseconds} ms.',
  );
}
