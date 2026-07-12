// Converts a Gaussian-splat PLY into the compact 32-byte-per-splat `.splat`
// layout (float position and scale, 8-bit color/opacity, 8-bit scalar-first
// quaternion), dropping the rest spherical harmonics the format cannot
// carry. Used by fetch_splat_asset.sh to keep the example's captured asset
// small enough to bundle.
//
// Run with `dart --packages=../../.dart_tool/package_config.json
// tool/ply_to_splat.dart <in.ply> <out.splat>` from examples/flutter_app.

// The splat codec is engine-internal, but this dev tool may import it.
// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/splats/splat_codec.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart --packages=../../.dart_tool/package_config.json '
      'tool/ply_to_splat.dart <in.ply> <out.splat>',
    );
    exit(64);
  }
  final bytes = File(args[0]).readAsBytesSync();
  final data = parseSplatPly(bytes);

  int quantize8(double v, double scale) =>
      ((v * scale) + 128).round().clamp(0, 255);

  final out = Uint8List(data.count * 32);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < data.count; i++) {
    final base = i * 32;
    final p = i * 3, q = i * 4;
    view.setFloat32(base, data.positions[p], Endian.little);
    view.setFloat32(base + 4, data.positions[p + 1], Endian.little);
    view.setFloat32(base + 8, data.positions[p + 2], Endian.little);
    view.setFloat32(base + 12, data.scales[p], Endian.little);
    view.setFloat32(base + 16, data.scales[p + 1], Endian.little);
    view.setFloat32(base + 20, data.scales[p + 2], Endian.little);
    out[base + 24] = (data.colors[p].clamp(0.0, 1.0) * 255).round();
    out[base + 25] = (data.colors[p + 1].clamp(0.0, 1.0) * 255).round();
    out[base + 26] = (data.colors[p + 2].clamp(0.0, 1.0) * 255).round();
    out[base + 27] = (data.opacities[i].clamp(0.0, 1.0) * 255).round();
    // Scalar first, matching the training PLY's rot_* order.
    out[base + 28] = quantize8(data.rotations[q + 3], 128);
    out[base + 29] = quantize8(data.rotations[q], 128);
    out[base + 30] = quantize8(data.rotations[q + 1], 128);
    out[base + 31] = quantize8(data.rotations[q + 2], 128);
  }
  File(args[1]).writeAsBytesSync(out);
  stdout.writeln('${data.count} splats -> ${args[1]} (${out.length} bytes)');
}
