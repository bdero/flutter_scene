// The analytic two-bone solver. Pure geometry, so the whole thing runs
// without a scene graph: build a limb, solve it, and check where the tip
// actually lands.
import 'package:flutter_scene/src/animation/two_bone_ik.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A limb bent in the XY plane: root at the origin, mid up and out, tip
/// further along. Upper and lower bones are both length 1.
const _root = (x: 0.0, y: 0.0, z: 0.0);

Vector3 rootPosition() => Vector3(_root.x, _root.y, _root.z);
Vector3 midPosition() => Vector3(1, 0, 0);
Vector3 tipPosition() => Vector3(1, -1, 0);

Vector3 solveTo(Vector3 target, {Vector3? pole, double softness = 0.01}) {
  final solution = solveTwoBoneIk(
    rootPosition: rootPosition(),
    midPosition: midPosition(),
    tipPosition: tipPosition(),
    target: target,
    pole: pole,
    softness: softness,
  );
  return twoBoneTipAfter(
    rootPosition: rootPosition(),
    midPosition: midPosition(),
    tipPosition: tipPosition(),
    solution: solution,
  );
}

void main() {
  group('reaching', () {
    test('a reachable target is reached', () {
      final target = Vector3(1.2, -0.4, 0);
      expect((solveTo(target) - target).length, lessThan(1e-4));
    });

    test('it reaches targets all around the root', () {
      for (final target in [
        Vector3(0.5, 1.2, 0),
        Vector3(-1.0, -0.6, 0),
        Vector3(0.2, -1.5, 0),
        Vector3(0.8, 0.3, 0.9),
        Vector3(-0.4, 0.1, -1.2),
      ]) {
        expect(
          (solveTo(target) - target).length,
          lessThan(1e-4),
          reason: 'target $target',
        );
      }
    });

    test('the bones keep their lengths', () {
      final target = Vector3(0.9, -0.9, 0.3);
      final solution = solveTwoBoneIk(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        tipPosition: tipPosition(),
        target: target,
      );
      final mid = twoBoneMidAfter(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        solution: solution,
      );
      final tip = twoBoneTipAfter(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        tipPosition: tipPosition(),
        solution: solution,
      );
      // A solver that stretched bones would hit any target, which is exactly
      // the failure this guards against.
      expect((mid - rootPosition()).length, closeTo(1, 1e-6));
      expect((tip - mid).length, closeTo(1, 1e-6));
    });
  });

  group('limits', () {
    test('an unreachable target is approached, not stretched to', () {
      final target = Vector3(10, 0, 0);
      final tip = solveTo(target);
      // Reach is 2; it gets close to that and no further.
      expect(tip.length, lessThan(2.0));
      expect(tip.length, greaterThan(1.9));
      // And it points the right way.
      expect(tip.normalized().x, closeTo(1, 1e-3));
    });

    test('softness leaves the limb short of locking straight', () {
      // A leg locked dead straight reads as broken, and the bend axis is
      // undefined there.
      final soft = solveTo(Vector3(10, 0, 0), softness: 0.1);
      final tight = solveTo(Vector3(10, 0, 0), softness: 0.0);
      expect(soft.length, lessThan(tight.length));
      expect(soft.length, closeTo(1.8, 1e-3));
    });

    test('a target inside the fold is pushed out to the minimum', () {
      // Equal bones can fold to zero, so this limb can technically reach the
      // root; the guard keeps the triangle from inverting.
      final tip = solveTo(Vector3(0.0001, 0, 0));
      expect(tip.length.isFinite, isTrue);
    });

    test('a target on the root itself leaves the limb alone', () {
      final solution = solveTwoBoneIk(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        tipPosition: tipPosition(),
        target: rootPosition(),
      );
      expect(solution.root.x, closeTo(0, 1e-9));
      expect(solution.root.w, closeTo(1, 1e-9));
    });
  });

  group('bend direction', () {
    test('a pole decides which way the joint bends', () {
      final target = Vector3(1.4, 0, 0);
      final front = solveTwoBoneIk(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        tipPosition: tipPosition(),
        target: target,
        pole: Vector3(0.7, 0, 5),
      );
      final back = solveTwoBoneIk(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        tipPosition: tipPosition(),
        target: target,
        pole: Vector3(0.7, 0, -5),
      );

      Vector3 midOf(TwoBoneSolution s) => twoBoneMidAfter(
        rootPosition: rootPosition(),
        midPosition: midPosition(),
        solution: s,
      );
      // Opposite poles put the knee on opposite sides.
      expect(midOf(front).z * midOf(back).z, lessThan(0));

      // Both still reach.
      for (final solution in [front, back]) {
        final tip = twoBoneTipAfter(
          rootPosition: rootPosition(),
          midPosition: midPosition(),
          tipPosition: tipPosition(),
          solution: solution,
        );
        expect((tip - target).length, lessThan(1e-4));
      }
    });

    test('a straight limb with no pole still solves', () {
      // With no bend there is no plane to keep, so the solver has to invent
      // one rather than dividing by a zero-length axis.
      final target = Vector3(1, 1, 0);
      final solution = solveTwoBoneIk(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(1, 0, 0),
        tipPosition: Vector3(2, 0, 0),
        target: target,
      );
      final tip = twoBoneTipAfter(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(1, 0, 0),
        tipPosition: Vector3(2, 0, 0),
        solution: solution,
      );
      expect(tip.x.isNaN, isFalse);
      expect((tip - target).length, lessThan(1e-4));
    });

    test('a pole in line with the target does not produce a null axis', () {
      final solution = solveTwoBoneIk(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(1, 0, 0),
        tipPosition: Vector3(2, 0, 0),
        target: Vector3(1.5, 0, 0),
        pole: Vector3(3, 0, 0),
      );
      expect(solution.root.w.isNaN, isFalse);
      expect(solution.mid.w.isNaN, isFalse);
    });
  });

  group('uneven bones', () {
    test('a long upper and short lower still reach', () {
      final target = Vector3(1.5, -1.0, 0.2);
      final solution = solveTwoBoneIk(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(2, 0, 0),
        tipPosition: Vector3(2, -0.5, 0),
        target: target,
      );
      final tip = twoBoneTipAfter(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(2, 0, 0),
        tipPosition: Vector3(2, -0.5, 0),
        solution: solution,
      );
      expect((tip - target).length, lessThan(1e-4));
    });

    test('uneven bones cannot fold past their difference', () {
      // Bones of 2 and 0.5 can never bring the tip closer than 1.5 to the
      // root, so a target inside that has to clamp.
      final solution = solveTwoBoneIk(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(2, 0, 0),
        tipPosition: Vector3(2, -0.5, 0),
        target: Vector3(0.2, 0, 0),
      );
      final tip = twoBoneTipAfter(
        rootPosition: Vector3.zero(),
        midPosition: Vector3(2, 0, 0),
        tipPosition: Vector3(2, -0.5, 0),
        solution: solution,
      );
      expect(tip.length, greaterThan(1.4));
    });
  });
}
