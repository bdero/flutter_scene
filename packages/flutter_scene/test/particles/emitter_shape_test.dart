import 'dart:math' as math;

import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Spawns one particle per seed, all sharing capacity, so a shape can be sampled
// across a spread of random seeds.
ParticleStorage _spawn(List<double> seeds) {
  final s = ParticleStorage(seeds.length);
  for (final seed in seeds) {
    final i = s.spawn();
    s.random01[i] = seed;
  }
  return s;
}

Vector3 _pos(ParticleStorage s, int i) =>
    Vector3(s.posX[i], s.posY[i], s.posZ[i]);
Vector3 _vel(ParticleStorage s, int i) =>
    Vector3(s.velX[i], s.velY[i], s.velZ[i]);

final List<double> _seeds = [for (var i = 0; i < 64; i++) (i + 0.5) / 64.0];

void main() {
  group('PointShape', () {
    test('spawns at the origin heading along the normalized direction', () {
      final shape = PointShape(direction: Vector3(0, 2, 0));
      final s = _spawn([0.1]);
      shape.sample(s, 0);
      expect(_pos(s, 0).length, 0.0);
      expect(_vel(s, 0).x, closeTo(0.0, 1e-9));
      expect(_vel(s, 0).y, closeTo(1.0, 1e-9));
      expect(_vel(s, 0).z, closeTo(0.0, 1e-9));
    });
  });

  group('SphereShape', () {
    test('surface points sit on the shell, radially directed', () {
      const shape = SphereShape(radius: 2.0, surfaceOnly: true);
      final s = _spawn(_seeds);
      for (var i = 0; i < s.aliveCount; i++) {
        shape.sample(s, i);
        expect(_pos(s, i).length, closeTo(2.0, 1e-6));
        expect(_vel(s, i).length, closeTo(1.0, 1e-6));
        // Position is the direction scaled by radius (radial outward).
        final radial = _vel(s, i)..scale(2.0);
        expect((_pos(s, i) - radial).length, closeTo(0.0, 1e-6));
      }
    });

    test('volume points stay inside the sphere', () {
      const shape = SphereShape(radius: 3.0);
      final s = _spawn(_seeds);
      for (var i = 0; i < s.aliveCount; i++) {
        shape.sample(s, i);
        expect(_pos(s, i).length, lessThanOrEqualTo(3.0 + 1e-6));
        expect(_vel(s, i).length, closeTo(1.0, 1e-6));
      }
    });

    test('hemisphere keeps positions and directions in the +Y half', () {
      const shape = SphereShape(radius: 1.0, hemisphere: true);
      final s = _spawn(_seeds);
      for (var i = 0; i < s.aliveCount; i++) {
        shape.sample(s, i);
        expect(s.posY[i], greaterThanOrEqualTo(-1e-9));
        expect(s.velY[i], greaterThanOrEqualTo(-1e-9));
      }
    });
  });

  group('ConeShape', () {
    test('base sits in the XZ plane within the radius', () {
      const shape = ConeShape(angle: 0.4, radius: 1.5);
      final s = _spawn(_seeds);
      for (var i = 0; i < s.aliveCount; i++) {
        shape.sample(s, i);
        expect(s.posY[i], closeTo(0.0, 1e-9));
        final discRadius = math.sqrt(
          s.posX[i] * s.posX[i] + s.posZ[i] * s.posZ[i],
        );
        expect(discRadius, lessThanOrEqualTo(1.5 + 1e-6));
      }
    });

    test('directions are unit length within the cone half-angle', () {
      const angle = 0.4;
      const shape = ConeShape(angle: angle, radius: 0.0);
      final s = _spawn(_seeds);
      for (var i = 0; i < s.aliveCount; i++) {
        shape.sample(s, i);
        expect(_vel(s, i).length, closeTo(1.0, 1e-6));
        // The axis is +Y, so cos(theta) = vel.y must clear cos(half-angle).
        expect(s.velY[i], greaterThanOrEqualTo(math.cos(angle) - 1e-6));
      }
    });
  });

  group('BoxShape', () {
    test('positions fill the box and share the direction', () {
      final shape = BoxShape(
        halfExtents: Vector3(1, 2, 3),
        direction: Vector3(0, 0, 4),
      );
      final s = _spawn(_seeds);
      for (var i = 0; i < s.aliveCount; i++) {
        shape.sample(s, i);
        expect(s.posX[i], inInclusiveRange(-1.0, 1.0));
        expect(s.posY[i], inInclusiveRange(-2.0, 2.0));
        expect(s.posZ[i], inInclusiveRange(-3.0, 3.0));
        expect(_vel(s, i).x, closeTo(0.0, 1e-9));
        expect(_vel(s, i).y, closeTo(0.0, 1e-9));
        expect(_vel(s, i).z, closeTo(1.0, 1e-9));
      }
    });
  });
}
