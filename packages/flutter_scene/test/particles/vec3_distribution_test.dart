import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_scene/src/particles/vec3_distribution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ParticleStorage _storageWith(double seed) {
  final s = ParticleStorage(1);
  s.spawn();
  s.random01[0] = seed;
  return s;
}

void main() {
  group('ConstantVec3', () {
    test('returns its value regardless of particle', () {
      final d = ConstantVec3(Vector3(1, 2, 3));
      final s = _storageWith(0.3);
      final out = d.sample(s, 0, 0);
      expect(out.x, 1.0);
      expect(out.y, 2.0);
      expect(out.z, 3.0);
    });
  });

  group('UniformBoxVec3', () {
    test('stays within the box and is deterministic', () {
      final d = UniformBoxVec3(Vector3(-1, -2, -3), Vector3(1, 2, 3));
      final s = _storageWith(0.42);
      final a = d.sample(s, 0, 30);
      final b = d.sample(s, 0, 30);
      expect(a.x, b.x);
      expect(a.y, b.y);
      expect(a.z, b.z);
      expect(a.x, inInclusiveRange(-1.0, 1.0));
      expect(a.y, inInclusiveRange(-2.0, 2.0));
      expect(a.z, inInclusiveRange(-3.0, 3.0));
    });

    test('uses an independent random per axis', () {
      final d = UniformBoxVec3(Vector3.all(0), Vector3.all(1));
      final s = _storageWith(0.42);
      final v = d.sample(s, 0, 30);
      // Three salted streams should not collapse to one value.
      expect(v.x == v.y && v.y == v.z, isFalse);
    });

    test('reuses the out vector when provided', () {
      final d = UniformBoxVec3(Vector3.all(0), Vector3.all(1));
      final s = _storageWith(0.1);
      final out = Vector3.zero();
      final result = d.sample(s, 0, 30, out);
      expect(identical(result, out), isTrue);
    });
  });
}
