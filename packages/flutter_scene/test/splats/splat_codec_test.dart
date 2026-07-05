import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/splats/splat_codec.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/splats/splat_data.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/splats/splat_sorter.dart';

/// Builds a binary little-endian Gaussian-splat PLY with [restPerChannel]
/// f_rest coefficients per channel, from per-splat property maps in
/// training space (log scales, logit opacity, raw f_dc).
Uint8List buildSplatPly(
  List<Map<String, double>> splats, {
  int restPerChannel = 0,
}) {
  final props = <String>[
    'x',
    'y',
    'z',
    'nx',
    'ny',
    'nz',
    'f_dc_0',
    'f_dc_1',
    'f_dc_2',
    for (var i = 0; i < restPerChannel * 3; i++) 'f_rest_$i',
    'opacity',
    'scale_0',
    'scale_1',
    'scale_2',
    'rot_0',
    'rot_1',
    'rot_2',
    'rot_3',
  ];
  final header = StringBuffer()
    ..write('ply\n')
    ..write('format binary_little_endian 1.0\n')
    ..write('element vertex ${splats.length}\n');
  for (final p in props) {
    header.write('property float $p\n');
  }
  header.write('end_header\n');

  final headerBytes = header.toString().codeUnits;
  final body = ByteData(splats.length * props.length * 4);
  var offset = 0;
  for (final splat in splats) {
    for (final p in props) {
      body.setFloat32(offset, splat[p] ?? 0.0, Endian.little);
      offset += 4;
    }
  }
  return Uint8List.fromList([...headerBytes, ...body.buffer.asUint8List()]);
}

double logit(double p) => math.log(p / (1 - p));

void main() {
  test('parses the training PLY layout with its space transforms', () {
    final bytes = buildSplatPly([
      {
        'x': 1.0, 'y': 2.0, 'z': 3.0,
        'f_dc_0': 1.0, 'f_dc_1': 0.0, 'f_dc_2': -1.0,
        'opacity': logit(0.75),
        'scale_0': math.log(0.5), 'scale_1': math.log(2.0), 'scale_2': 0.0,
        // Scalar-first quaternion, doubled so normalization is exercised.
        'rot_0': 2.0, 'rot_1': 0.0, 'rot_2': 0.0, 'rot_3': 0.0,
      },
    ]);
    final data = parseSplatPly(bytes);

    expect(data.count, 1);
    expect(data.shDegree, 0);
    expect(data.positions, [1.0, 2.0, 3.0]);
    expect(data.scales[0], closeTo(0.5, 1e-6));
    expect(data.scales[1], closeTo(2.0, 1e-6));
    expect(data.scales[2], closeTo(1.0, 1e-6));
    expect(data.opacities[0], closeTo(0.75, 1e-6));
    // SH0 evaluation: 0.5 + C0 * f_dc.
    expect(data.colors[0], closeTo(0.5 + kShC0, 1e-6));
    expect(data.colors[1], closeTo(0.5, 1e-6));
    expect(data.colors[2], closeTo(0.5 - kShC0, 1e-6));
    // Stored x, y, z, w; the file's rot_0 is the scalar.
    expect(data.rotations, [0.0, 0.0, 0.0, 1.0]);
  });

  test('reorders channel-major f_rest into per-coefficient rgb', () {
    final rest = <String, double>{};
    // Channel-major: R coefficients 1..3, G 4..6, B 7..9.
    for (var i = 0; i < 9; i++) {
      rest['f_rest_$i'] = (i + 1).toDouble();
    }
    final bytes = buildSplatPly([
      {'opacity': logit(0.9), 'rot_0': 1.0, ...rest},
    ], restPerChannel: 3);
    final data = parseSplatPly(bytes);

    expect(data.shDegree, 1);
    // Coefficient 0 across channels: R=1, G=4, B=7; coefficient 2: 3, 6, 9.
    expect(data.sh!.sublist(0, 3), [1.0, 4.0, 7.0]);
    expect(data.sh!.sublist(6, 9), [3.0, 6.0, 9.0]);
  });

  test('truncates SH to maxShDegree and culls by alpha', () {
    final rest = <String, double>{
      for (var i = 0; i < 24; i++) 'f_rest_$i': 1.0,
    };
    final bytes = buildSplatPly([
      {'opacity': logit(0.9), 'rot_0': 1.0, ...rest},
      {'opacity': -20.0, 'rot_0': 1.0, ...rest}, // sigmoid ~ 0: culled
    ], restPerChannel: 8);

    final full = parseSplatPly(bytes);
    expect(full.count, 1);
    expect(full.shDegree, 2);

    final truncated = parseSplatPly(
      bytes,
      options: const SplatDecodeOptions(maxShDegree: 1),
    );
    expect(truncated.shDegree, 1);
    expect(truncated.sh!.length, 1 * 3 * 3);
  });

  test('parses the 32-byte .splat layout', () {
    final bytes = Uint8List(64);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < 2; i++) {
      final base = i * 32;
      view.setFloat32(base, 1.0 + i, Endian.little);
      view.setFloat32(base + 4, 2.0, Endian.little);
      view.setFloat32(base + 8, 3.0, Endian.little);
      view.setFloat32(base + 12, 0.1, Endian.little);
      view.setFloat32(base + 16, 0.2, Endian.little);
      view.setFloat32(base + 20, 0.3, Endian.little);
      bytes[base + 24] = 255; // r
      bytes[base + 25] = 128; // g
      bytes[base + 26] = 0; // b
      bytes[base + 27] = i == 0 ? 255 : 0; // opacity; splat 1 is culled
      bytes[base + 28] = 255; // ~w = 0.99
      bytes[base + 29] = 128; // x = 0
      bytes[base + 30] = 128; // y = 0
      bytes[base + 31] = 128; // z = 0
    }
    final data = parseSplatFile(bytes);
    expect(data.count, 1);
    expect(data.positions[0], 1.0);
    expect(data.scales[1], closeTo(0.2, 1e-6));
    expect(data.colors[0], closeTo(1.0, 1e-6));
    expect(data.colors[1], closeTo(128 / 255, 1e-6));
    expect(data.opacities[0], 1.0);
    expect(data.rotations[3], closeTo(1.0, 1e-6)); // w, normalized
    expect(sniffSplatFormat(bytes), SplatFormat.splat);
  });

  test('packs covariance from quaternion and scales', () {
    // Identity rotation: covariance is diag(sx^2, sy^2, sz^2).
    final data = SplatData.zeroed(2);
    data.positions.setAll(0, [1, 2, 3, 4, 5, 6]);
    data.scales.setAll(0, [0.5, 2.0, 3.0, 1.0, 1.0, 1.0]);
    data.rotations.setAll(0, [0, 0, 0, 1, 0, 0, math.sqrt1_2, math.sqrt1_2]);
    data.opacities.setAll(0, [0.25, 1.0]);
    data.colors.setAll(0, [1, 0, 0, 0, 1, 0]);

    final packed = packSplats(data);
    expect(
      packed.paramsWidth * packed.paramsHeight * 4,
      packed.paramsTexels.length,
    );

    final t = packed.paramsTexels;
    // Splat 0, texel 0: position + opacity.
    expect(t.sublist(0, 4), [1, 2, 3, 0.25]);
    // Texels 1-2: xx, xy, xz, yy | yz, zz.
    expect(t[4], closeTo(0.25, 1e-6)); // xx = 0.5^2
    expect(t[5], closeTo(0.0, 1e-6));
    expect(t[7], closeTo(4.0, 1e-6)); // yy = 2^2
    expect(t[9], closeTo(9.0, 1e-6)); // zz = 3^2
    // Texel 3: color.
    expect(t.sublist(12, 15), [1, 0, 0]);

    // Splat 1: 90-degree rotation about Z of a unit sphere stays identity.
    final o = kParamsTexelsPerSplat * 4;
    expect(t[o + 4], closeTo(1.0, 1e-6));
    expect(t[o + 7], closeTo(1.0, 1e-6));
    expect(t[o + 9], closeTo(1.0, 1e-6));
    expect(t[o + 5], closeTo(0.0, 1e-6));
  });

  test('packs rest SH with a power-of-two stride', () {
    final data = SplatData.zeroed(3, shDegree: 1);
    for (var i = 0; i < data.count; i++) {
      data.rotations[i * 4 + 3] = 1.0;
      for (var c = 0; c < 3; c++) {
        for (var ch = 0; ch < 3; ch++) {
          data.sh![(i * 3 + c) * 3 + ch] = (i * 100 + c * 10 + ch).toDouble();
        }
      }
    }
    final packed = packSplats(data);
    expect(packed.shStride, 4);
    final sh = packed.shTexels!;
    // Splat 2, coefficient 1: value 2*100 + 10 + channel.
    final base = (2 * packed.shStride + 1) * 4;
    expect(sh.sublist(base, base + 3), [210.0, 211.0, 212.0]);
    // Padding texel is zero.
    expect(sh[(2 * packed.shStride + 3) * 4], 0.0);
  });

  test('sorts back to front along the view direction', () {
    final rng = math.Random(1234);
    const count = 2000;
    final positions = Float32List(count * 3);
    for (var i = 0; i < positions.length; i++) {
      positions[i] = rng.nextDouble() * 200 - 100;
    }
    const dx = 0.3, dy = -0.5, dz = 0.8;
    final order = sortSplatsBackToFront(positions, count, dx, dy, dz);

    expect(order.length, count);
    final seen = <int>{};
    var last = double.infinity;
    for (var i = 0; i < count; i++) {
      final index = order[i].toInt();
      expect(order[i], index.toDouble()); // exact float integers
      expect(seen.add(index), isTrue); // a permutation
      final o = index * 3;
      final key =
          positions[o] * dx + positions[o + 1] * dy + positions[o + 2] * dz;
      // Non-increasing within quantization tolerance.
      const tolerance = 400 * math.sqrt2 / 65535 * 2;
      expect(key, lessThanOrEqualTo(last + tolerance));
      last = key;
    }
  });

  test('sorter handles degenerate inputs', () {
    expect(sortSplatsBackToFront(Float32List(0), 0, 0, 0, 1), isEmpty);
    final same = Float32List.fromList([1, 1, 1, 1, 1, 1]);
    final order = sortSplatsBackToFront(same, 2, 0, 0, 1);
    expect(order.toSet(), {0.0, 1.0});
  });

  test(
    'rejects oversized sets with a clear error',
    () {
      // A count whose params texels exceed 4096 rows of a 4096-wide texture.
      expect(
        () => packSplats(SplatData.zeroed(4096 * 4096 ~/ 4 + 1)),
        throwsArgumentError,
      );
    },
    skip: 'Allocates ~1.5GB; covered by the height check unit logic.',
  );
}
