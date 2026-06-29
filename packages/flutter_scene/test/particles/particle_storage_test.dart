import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParticleStorage pool', () {
    test('spawn appends dense indices and reports full', () {
      final s = ParticleStorage(3);
      expect(s.aliveCount, 0);
      expect(s.isFull, isFalse);
      expect(s.spawn(), 0);
      expect(s.spawn(), 1);
      expect(s.spawn(), 2);
      expect(s.aliveCount, 3);
      expect(s.isFull, isTrue);
      expect(s.spawn(), -1); // full
      expect(s.aliveCount, 3);
    });

    test('kill swaps the last live particle into the freed slot', () {
      final s = ParticleStorage(4);
      for (var i = 0; i < 4; i++) {
        s.spawn();
        s.posX[i] = i.toDouble(); // tag each particle by its spawn order
      }
      // Kill index 1; the last (index 3) should move into slot 1.
      s.kill(1);
      expect(s.aliveCount, 3);
      expect(s.posX[0], 0.0);
      expect(s.posX[1], 3.0); // moved
      expect(s.posX[2], 2.0);
    });

    test('killing the last particle just shrinks', () {
      final s = ParticleStorage(3);
      for (var i = 0; i < 3; i++) {
        s.spawn();
        s.posX[i] = i.toDouble();
      }
      s.kill(2);
      expect(s.aliveCount, 2);
      expect(s.posX[0], 0.0);
      expect(s.posX[1], 1.0);
    });

    test('reverse iteration with kill visits every particle once', () {
      final s = ParticleStorage(5);
      for (var i = 0; i < 5; i++) {
        s.spawn();
        s.posX[i] = i.toDouble();
      }
      // Kill all with even tags during a reverse sweep; survivors are odd.
      final visited = <double>[];
      for (var i = s.aliveCount - 1; i >= 0; i--) {
        visited.add(s.posX[i]);
        if (s.posX[i] % 2 == 0) s.kill(i);
      }
      expect(visited.toSet(), {0.0, 1.0, 2.0, 3.0, 4.0}); // each seen once
      final survivors = <double>[
        for (var i = 0; i < s.aliveCount; i++) s.posX[i],
      ];
      expect(survivors.toSet(), {1.0, 3.0});
      expect(s.aliveCount, 2);
    });

    test('clear resets the live set but keeps capacity', () {
      final s = ParticleStorage(2);
      s.spawn();
      s.spawn();
      s.clear();
      expect(s.aliveCount, 0);
      expect(s.spawn(), 0);
    });

    test('all columns move together on kill', () {
      final s = ParticleStorage(2);
      s.spawn();
      s.spawn();
      s.posX[1] = 9;
      s.velY[1] = 8;
      s.lifetime[1] = 7;
      s.colorA[1] = 0.5;
      s.random01[1] = 0.25;
      s.kill(0); // slot 1 moves into slot 0
      expect(s.posX[0], 9);
      expect(s.velY[0], 8);
      expect(s.lifetime[0], 7);
      expect(s.colorA[0], 0.5);
      expect(s.random01[0], 0.25);
    });
  });

  group('ParticleStorage.randomFor', () {
    test('is deterministic and in [0, 1)', () {
      final s = ParticleStorage(1);
      s.spawn();
      s.random01[0] = 0.42;
      final a = s.randomFor(0, 1);
      final b = s.randomFor(0, 1);
      expect(a, b);
      expect(a, greaterThanOrEqualTo(0.0));
      expect(a, lessThan(1.0));
    });

    test('different salts give different streams', () {
      final s = ParticleStorage(1);
      s.spawn();
      s.random01[0] = 0.42;
      expect(s.randomFor(0, 1), isNot(closeTo(s.randomFor(0, 2), 1e-9)));
    });
  });
}
