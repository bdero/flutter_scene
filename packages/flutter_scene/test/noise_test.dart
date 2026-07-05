import 'package:flutter_scene/src/noise/fast_noise_lite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FastNoiseLite bounds', () {
    test('OpenSimplex2 2D/3D stays within sane bounds over a grid', () {
      final noise = FastNoiseLite(seed: 1337);
      for (double x = -50; x <= 50; x += 3.7) {
        for (double y = -50; y <= 50; y += 3.7) {
          final v2 = noise.getNoise2(x, y);
          expect(v2, inInclusiveRange(-1.05, 1.05));
          final v3 = noise.getNoise3(x, y, x - y);
          expect(v3, inInclusiveRange(-1.05, 1.05));
        }
      }
    });

    test('OpenSimplex2S 2D/3D stays within sane bounds over a grid', () {
      final noise = FastNoiseLite(seed: 1337)
        ..noiseType = NoiseType.openSimplex2S;
      for (double x = -50; x <= 50; x += 3.7) {
        for (double y = -50; y <= 50; y += 3.7) {
          final v2 = noise.getNoise2(x, y);
          expect(v2, inInclusiveRange(-1.05, 1.05));
          final v3 = noise.getNoise3(x, y, x + y);
          expect(v3, inInclusiveRange(-1.05, 1.05));
        }
      }
    });

    test('fBm with many octaves stays bounded', () {
      for (final type in NoiseType.values) {
        final noise = FastNoiseLite(seed: 1337)
          ..noiseType = type
          ..fractalType = FractalType.fbm
          ..octaves = 8;
        for (double x = -30; x <= 30; x += 2.5) {
          for (double y = -30; y <= 30; y += 2.5) {
            expect(noise.getNoise2(x, y), inInclusiveRange(-1.05, 1.05));
            expect(
              noise.getNoise3(x, y, x * 0.5),
              inInclusiveRange(-1.05, 1.05),
            );
          }
        }
      }
    });

    test('ridged and pingPong fractals stay bounded', () {
      for (final fractal in <FractalType>[
        FractalType.ridged,
        FractalType.pingPong,
      ]) {
        final noise = FastNoiseLite(seed: 4242)
          ..fractalType = fractal
          ..octaves = 6;
        for (double x = -20; x <= 20; x += 1.9) {
          for (double y = -20; y <= 20; y += 1.9) {
            expect(noise.getNoise2(x, y), inInclusiveRange(-1.05, 1.05));
            expect(noise.getNoise3(x, y, -x), inInclusiveRange(-1.05, 1.05));
          }
        }
      }
    });
  });

  group('Determinism', () {
    test('same seed and coords give the same value across calls', () {
      final a = FastNoiseLite(seed: 1337);
      final b = FastNoiseLite(seed: 1337);
      for (double x = -10; x <= 10; x += 1.3) {
        for (double y = -10; y <= 10; y += 1.3) {
          expect(a.getNoise2(x, y), equals(b.getNoise2(x, y)));
          expect(a.getNoise3(x, y, x + y), equals(b.getNoise3(x, y, x + y)));
          // Repeated calls on the same instance are stable too.
          expect(a.getNoise2(x, y), equals(a.getNoise2(x, y)));
        }
      }
    });

    test('different seeds give different values', () {
      final a = FastNoiseLite(seed: 1337);
      final b = FastNoiseLite(seed: 9999);
      var differences = 0;
      var samples = 0;
      for (double x = -10; x <= 10; x += 1.3) {
        for (double y = -10; y <= 10; y += 1.3) {
          samples++;
          if (a.getNoise2(x, y) != b.getNoise2(x, y)) differences++;
        }
      }
      // The vast majority of samples must differ between seeds.
      expect(differences, greaterThan(samples ~/ 2));
    });

    test('a specific pair of seeds differs at a fixed coordinate', () {
      expect(
        FastNoiseLite(seed: 1337).getNoise2(10.0, 20.0),
        isNot(equals(FastNoiseLite(seed: 9999).getNoise2(10.0, 20.0))),
      );
    });
  });

  group('Pinned values', () {
    // These were captured from this implementation. They guard against
    // accidental algorithm drift and (critically) against the web build
    // diverging from native: all hashing is forced to 32-bit, and the
    // floating-point path uses IEEE-754 doubles that are identical on the VM
    // and in the browser, so these values must hold on both. If a refactor
    // changes any of these, that is a behavior change to review, not a
    // tolerance to widen.
    const double tol = 1e-6;

    test('OpenSimplex2 2D', () {
      final n = FastNoiseLite(seed: 1337);
      expect(n.getNoise2(10.0, 20.0), closeTo(0.912922712299793, tol));
      expect(n.getNoise2(-3.5, 7.25), closeTo(0.214462635911099, tol));
      expect(n.getNoise2(123.456, -78.9), closeTo(-0.855608077542204, tol));
    });

    test('OpenSimplex2 3D', () {
      final n = FastNoiseLite(seed: 1337);
      expect(n.getNoise3(10.0, 20.0, 30.0), closeTo(0.066842120170555, tol));
      expect(n.getNoise3(-3.5, 7.25, 0.5), closeTo(0.273804249016109, tol));
      expect(
        n.getNoise3(123.456, -78.9, 42.0),
        closeTo(0.835447107935540, tol),
      );
    });

    test('OpenSimplex2S 2D/3D', () {
      final s = FastNoiseLite(seed: 1337)..noiseType = NoiseType.openSimplex2S;
      expect(s.getNoise2(10.0, 20.0), closeTo(0.623011691732364, tol));
      expect(s.getNoise2(-3.5, 7.25), closeTo(0.123126063629257, tol));
      expect(s.getNoise3(10.0, 20.0, 30.0), closeTo(-0.171646025830546, tol));
      expect(s.getNoise3(-3.5, 7.25, 0.5), closeTo(0.188487644587352, tol));
    });

    test('fBm fractal (octaves = 4)', () {
      final f = FastNoiseLite(seed: 1337)
        ..fractalType = FractalType.fbm
        ..octaves = 4;
      expect(f.getNoise2(10.0, 20.0), closeTo(0.606915091529966, tol));
      expect(f.getNoise3(10.0, 20.0, 30.0), closeTo(-0.124032077319534, tol));
    });

    test('ridged fractal (octaves = 4)', () {
      final r = FastNoiseLite(seed: 1337)
        ..fractalType = FractalType.ridged
        ..octaves = 4;
      expect(r.getNoise2(10.0, 20.0), closeTo(-0.302130854488225, tol));
      expect(r.getNoise3(10.0, 20.0, 30.0), closeTo(0.609339322330413, tol));
    });

    test('pingPong fractal (octaves = 4)', () {
      final p = FastNoiseLite(seed: 1337)
        ..fractalType = FractalType.pingPong
        ..octaves = 4;
      expect(p.getNoise2(10.0, 20.0), closeTo(-0.466411253642021, tol));
      expect(p.getNoise3(10.0, 20.0, 30.0), closeTo(-0.218678644660827, tol));
    });

    test('different seed pins a different value', () {
      final n = FastNoiseLite(seed: 9999);
      expect(n.getNoise2(10.0, 20.0), closeTo(0.704530627003459, tol));
    });
  });

  group('Integer hash layer', () {
    test('pins bit-exact noiseHash2/noiseHash3 values', () {
      // These vectors double as the reference for the GLSL NoiseHash2/3
      // parity checks; the two implementations must agree bit for bit.
      expect(noiseHash2(1337, 0, 0), 117456389);
      expect(noiseHash2(1337, 1, 2), -1108494942);
      expect(noiseHash2(1337, -3, 7), 626204859);
      expect(noiseHash2(1337, 1000000, -999999), -1831972764);
      expect(noiseHash3(42, 0, 0, 0), -1997630110);
      expect(noiseHash3(42, 5, -4, 3), -1157608306);
      expect(noiseHash3(42, -100, 200, -300), -1731503958);
    });
  });

  group('Verbatim gradient tables', () {
    test('RandVecs table lengths match FastNoiseLite', () {
      // RandVecs2D is 512 (256 vectors * 2), RandVecs3D is 1024 (256 * 4).
      expect(randVecsTableLengths, equals(<int>[512, 1024]));
    });
  });
}
