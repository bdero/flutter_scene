// Virtual cameras. The behaviours worth pinning are the ones that make a shot
// feel deliberate: damping that means the same thing at any frame rate, dead
// zones that stop a camera answering every twitch, and a first frame that
// snaps rather than swinging across the level.

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A target node at [at], optionally turned by [yaw] radians.
Node target(Vector3 at, {double yaw = 0}) => Node(name: 'target')
  ..position = at
  ..rotation = Quaternion.axisAngle(Vector3(0, 1, 0), yaw);

/// Runs [camera] for [seconds] at [fps].
void run(VirtualCamera camera, double seconds, {double fps = 60}) {
  final step = 1 / fps;
  for (var t = 0.0; t < seconds; t += step) {
    camera.advance(step);
  }
}

void main() {
  group('damping', () {
    test('means the same settle time at any frame rate', () {
      // A camera that lags differently on a slower machine is a camera that
      // has to be retuned per machine.
      final ends = <double>[];
      for (final fps in [30.0, 60.0, 144.0]) {
        var value = 0.0;
        final step = 1 / fps;
        for (var t = 0.0; t < 1.0; t += step) {
          value = dampScalar(value, 10, 0.3, step);
        }
        ends.add(value);
      }
      for (final end in ends) {
        expect(end, closeTo(ends.first, 0.05), reason: '$ends');
      }
    });

    test('a settle time is when it has essentially arrived', () {
      var value = 0.0;
      for (var t = 0.0; t < 0.5; t += 1 / 60) {
        value = dampScalar(value, 1, 0.5, 1 / 60);
      }
      expect(value, greaterThan(0.98));
    });

    test('zero damping snaps', () {
      expect(dampScalar(0, 5, 0, 1 / 60), 5);
    });

    test('per axis, so sideways can outrun depth', () {
      final out = Vector3.zero();
      dampVector(
        Vector3.zero(),
        Vector3(10, 10, 10),
        Vector3(0.01, 1.0, 5.0),
        1 / 60,
        out,
      );
      expect(out.x, greaterThan(out.y));
      expect(out.y, greaterThan(out.z));
    });
  });

  group('the first frame', () {
    test('snaps into place rather than easing in from nowhere', () {
      final camera = VirtualCamera(
        follow: target(Vector3(100, 0, 100)),
        body: TransposerBody(offset: Vector3(0, 2, -6)),
      );
      camera.advance(1 / 60);
      // Straight to the shot, not a sixtieth of the way there.
      expect(camera.pose.position.x, closeTo(100, 0.001));
      expect(camera.pose.position.z, closeTo(94, 0.001));
    });

    test('reset makes the next frame snap again', () {
      final follow = target(Vector3.zero());
      final camera = VirtualCamera(
        follow: follow,
        body: TransposerBody(offset: Vector3(0, 0, -5)),
      );
      camera.advance(1 / 60);
      follow.position = Vector3(50, 0, 0);
      camera.reset();
      camera.advance(1 / 60);
      expect(camera.pose.position.x, closeTo(50, 0.001));
    });
  });

  group('transposer', () {
    test('world binding keeps its bearing while the target turns', () {
      final follow = target(Vector3.zero());
      final camera = VirtualCamera(
        follow: follow,
        body: TransposerBody(
          offset: Vector3(0, 0, -5),
          binding: CameraBinding.worldSpace,
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      follow.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      camera.advance(1 / 60);
      expect(camera.pose.position.z, closeTo(-5, 0.001));
      expect(camera.pose.position.x, closeTo(0, 0.001));
    });

    test('target binding swings round with it', () {
      final follow = target(Vector3.zero());
      final camera = VirtualCamera(
        follow: follow,
        body: TransposerBody(
          offset: Vector3(0, 0, -5),
          binding: CameraBinding.lockToTargetWithWorldUp,
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      follow.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      camera.advance(1 / 60);
      // A quarter turn puts the camera on -X instead of -Z.
      expect(camera.pose.position.x, closeTo(-5, 0.001));
      expect(camera.pose.position.z, closeTo(0, 0.001));
    });

    test('lock to target takes the camera round with a compound rotation', () {
      // The binding with no world-up correction, and the one where getting the
      // rotation convention backwards is invisible on a single axis: yaw and
      // pitch together are what tell the two conventions apart.
      final follow = Node(name: 'target')
        ..rotation =
            Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2) *
            Quaternion.axisAngle(Vector3(1, 0, 0), 0.4);
      final camera = VirtualCamera(
        follow: follow,
        body: TransposerBody(
          offset: Vector3(0, 0, -5),
          binding: CameraBinding.lockToTarget,
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      // Where the scene graph itself would put a child at that offset, which
      // is the only definition of "behind the target" the engine has.
      final expected =
          Matrix4.compose(Vector3.zero(), follow.rotation, Vector3(1, 1, 1)) *
          Vector4(0, 0, -5, 1);
      expect(camera.pose.position.x, closeTo(expected.x, 0.001));
      expect(camera.pose.position.y, closeTo(expected.y, 0.001));
      expect(camera.pose.position.z, closeTo(expected.z, 0.001));
    });

    test('a target that pitches does not roll the shot', () {
      // World-up binding exists for exactly this: looking down a slope should
      // not tilt the horizon.
      final follow = Node(name: 'target')
        ..rotation = Quaternion.axisAngle(Vector3(1, 0, 0), 0.7);
      final camera = VirtualCamera(
        follow: follow,
        body: TransposerBody(
          offset: Vector3(0, 0, -5),
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      expect(camera.pose.position.y, closeTo(0, 0.001));
    });

    test('with no follow target it holds still rather than flying to zero', () {
      final camera = VirtualCamera(body: TransposerBody());
      camera.advance(1 / 60);
      expect(camera.pose.position, Vector3.zero());
    });
  });

  test('a follow camera sits behind the character, not in front of it', () {
    // The heading-only path used to invert twice and land in the right place
    // by accident. A single-axis test cannot tell that apart from correct, so
    // this one checks the sign against the character's own forward.
    final follow = Node(name: 'hero')
      ..rotation = Quaternion.axisAngle(Vector3(0, 1, 0), 2.3);
    final camera = VirtualCamera(
      follow: follow,
      body: TransposerBody(offset: Vector3(0, 0, -6), damping: Vector3.zero()),
    );
    camera.advance(1 / 60);
    final heroForward = follow.rotation.rotateVector(Vector3(0, 0, 1));
    // Behind means the camera is on the opposite side to where the hero faces.
    expect(camera.pose.position.dot(heroForward), lessThan(-5.9));
  });

  group('framing transposer', () {
    test('a target moving inside the dead zone does not move the camera', () {
      // Without this every twitch of the target moves the camera and the shot
      // never sits still.
      final follow = target(Vector3.zero());
      final camera = VirtualCamera(
        follow: follow,
        body: FramingTransposerBody(
          distance: 5,
          height: 0,
          deadZone: 1,
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      final before = camera.pose.position.clone();
      follow.position = Vector3(0.5, 0, 0);
      camera.advance(1 / 60);
      expect(camera.pose.position.x, closeTo(before.x, 0.001));
    });

    test('leaving it moves the camera, but only by the excess', () {
      final follow = target(Vector3.zero());
      final camera = VirtualCamera(
        follow: follow,
        body: FramingTransposerBody(
          distance: 5,
          height: 0,
          deadZone: 1,
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      follow.position = Vector3(3, 0, 0);
      camera.advance(1 / 60);
      // Three out, one of dead zone: the camera follows the other two.
      expect(camera.pose.position.x, closeTo(2, 0.001));
    });

    test('it keeps its distance behind the target', () {
      final camera = VirtualCamera(
        follow: target(Vector3.zero()),
        body: FramingTransposerBody(
          distance: 7,
          height: 3,
          damping: Vector3.zero(),
        ),
      );
      camera.advance(1 / 60);
      expect(camera.pose.position.z, closeTo(-7, 0.001));
      expect(camera.pose.position.y, closeTo(3, 0.001));
    });
  });

  group('orbital', () {
    test('heading walks the camera round the target', () {
      final camera = VirtualCamera(
        follow: target(Vector3.zero()),
        body: OrbitalBody(radius: 4, height: 0, damping: Vector3.zero()),
      );
      camera.advance(1 / 60);
      expect(camera.pose.position.z, closeTo(4, 0.001));
      (camera.body as OrbitalBody).heading = math.pi / 2;
      camera.advance(1 / 60);
      expect(camera.pose.position.x, closeTo(4, 0.001));
      expect(camera.pose.position.z, closeTo(0, 0.001));
    });

    test('it stays on its radius', () {
      final camera = VirtualCamera(
        follow: target(Vector3(10, 0, -4)),
        body: OrbitalBody(radius: 6, height: 0, damping: Vector3.zero()),
      );
      for (var i = 0; i < 8; i++) {
        (camera.body as OrbitalBody).heading = i * math.pi / 4;
        camera.advance(1 / 60);
        final flat = Vector3(
          camera.pose.position.x - 10,
          0,
          camera.pose.position.z + 4,
        );
        expect(flat.length, closeTo(6, 0.001), reason: 'at step $i');
      }
    });
  });

  group('aim', () {
    test('hard look at points straight at the target', () {
      final camera = VirtualCamera(
        follow: target(Vector3.zero()),
        lookAt: target(Vector3(0, 0, 10)),
        body: TransposerBody(offset: Vector3.zero(), damping: Vector3.zero()),
        aim: HardLookAtAim(),
      );
      camera.advance(1 / 60);
      final forward = camera.pose.forward;
      expect(forward.z, closeTo(1, 0.001));
    });

    test('a composer holds still while the target is inside its dead zone', () {
      final look = target(Vector3(0, 0, 10));
      final camera = VirtualCamera(
        follow: target(Vector3.zero()),
        lookAt: look,
        body: TransposerBody(offset: Vector3.zero(), damping: Vector3.zero()),
        aim: ComposerAim(deadZoneDegrees: 10, damping: 0),
      );
      camera.advance(1 / 60);
      final before = camera.pose.rotation.clone();
      // A degree or so off centre: inside the zone.
      look.position = Vector3(0.1, 0, 10);
      camera.advance(1 / 60);
      expect(camera.pose.rotation.x, closeTo(before.x, 1e-6));
      expect(camera.pose.rotation.y, closeTo(before.y, 1e-6));
    });

    test('and turns once the target leaves it', () {
      final look = target(Vector3(0, 0, 10));
      final camera = VirtualCamera(
        follow: target(Vector3.zero()),
        lookAt: look,
        body: TransposerBody(offset: Vector3.zero(), damping: Vector3.zero()),
        aim: ComposerAim(deadZoneDegrees: 5, damping: 0),
      );
      camera.advance(1 / 60);
      look.position = Vector3(10, 0, 10);
      camera.advance(1 / 60);
      final forward = camera.pose.forward;
      expect(forward.x, greaterThan(0.5));
    });

    test('a fixed aim never moves', () {
      final held = Quaternion.axisAngle(Vector3(0, 1, 0), 1.2);
      final camera = VirtualCamera(
        follow: target(Vector3.zero()),
        lookAt: target(Vector3(5, 5, 5)),
        aim: FixedAim(rotation: held),
      );
      camera.advance(1 / 60);
      expect(camera.pose.rotation.x, closeTo(held.x, 1e-6));
      expect(camera.pose.rotation.w, closeTo(held.w, 1e-6));
    });

    test('looking straight down does not produce a broken rotation', () {
      // The up vector is parallel to the view direction here, which is where
      // a naive look-at hands back NaNs.
      final rotation = lookRotation(Vector3(0, -1, 0));
      expect(rotation.x.isNaN, isFalse);
      expect(rotation.length, closeTo(1, 1e-6));
    });

    test('a zero direction is survived rather than crashed on', () {
      final rotation = lookRotation(Vector3.zero());
      expect(rotation.length, closeTo(1, 1e-6));
    });
  });

  group('as a shot in a director', () {
    test('the highest priority is the one that goes live', () {
      final director = CameraDirector();
      final low = VirtualCamera(
        follow: target(Vector3.zero()),
        body: TransposerBody(
          offset: Vector3(0, 0, -5),
          damping: Vector3.zero(),
        ),
      );
      final high = VirtualCamera(
        follow: target(Vector3.zero()),
        body: TransposerBody(
          offset: Vector3(0, 0, -20),
          damping: Vector3.zero(),
        ),
      );
      director
        ..add(low, priority: 1)
        ..add(high, priority: 10);
      Node(name: 'camera').addComponent(director);
      director.update(1 / 60);
      expect(director.activeCamera, same(high));
    });

    test('two shots blend rather than cutting', () {
      final director = CameraDirector(defaultBlend: const CameraBlend(0.5));
      final a = VirtualCamera(
        follow: target(Vector3.zero()),
        body: TransposerBody(
          offset: Vector3(0, 0, -5),
          damping: Vector3.zero(),
        ),
      );
      final b = VirtualCamera(
        follow: target(Vector3.zero()),
        body: TransposerBody(
          offset: Vector3(0, 0, -50),
          damping: Vector3.zero(),
        ),
      );
      director.add(a, priority: 10);
      Node(name: 'camera').addComponent(director);
      director.update(1 / 60);
      final started = director.pose.position.z;
      director.add(b, priority: 20);
      director.update(1 / 60);
      // Part way, not all the way.
      final blended = director.pose.position.z;
      expect(blended, lessThan(started));
      expect(blended, greaterThan(-50));
    });
  });

  test('a camera left running stays numerically sound', () {
    // The bodies and aims carry state between frames -- an anchor, a previous
    // position, a current rotation -- and reuse scratch vectors to hold it.
    // Two seconds of solving is enough for a normalization that was skipped or
    // a scratch vector that was read after being overwritten to show up.
    final follow = target(Vector3.zero());
    final camera = VirtualCamera(
      follow: follow,
      lookAt: follow,
      body: FramingTransposerBody(),
      aim: ComposerAim(),
    );
    run(camera, 2);
    expect(camera.pose.position.x.isFinite, isTrue);
    expect(camera.pose.rotation.length, closeTo(1, 1e-6));
  });
}
