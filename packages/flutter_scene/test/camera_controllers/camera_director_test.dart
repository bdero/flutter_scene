// Covers CameraDirector: priority and explicit selection pick the live shot,
// blends interpolate live (both cameras keep tracking), interrupting a blend
// starts from the in-between pose, the lens follows, and input forwards to
// whichever camera is live.

import 'dart:ui' show Offset, Size;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A camera that reports exactly where it is told to, so a test asserts on
/// the director's blending rather than on a controller's easing.
class _FixedCamera extends CameraController {
  _FixedCamera(this.eye, this.target, {this.lens});

  Vector3 eye;
  Vector3 target;
  CameraProjection? lens;
  int drags = 0;
  int releases = 0;

  @override
  void advance(double deltaSeconds) =>
      setPose(CameraPose.lookAt(eye, target, projection: lens));

  @override
  void handleDragUpdate(Offset delta) => drags++;

  @override
  void releaseInput() => releases++;
}

// Two cameras looking the same way (+Z) at different heights, so a blend
// between them is a pure vertical slide and easy to read.
_FixedCamera _atHeight(double y) =>
    _FixedCamera(Vector3(0.0, y, -10.0), Vector3(0.0, y, 0.0));

({Node node, CameraDirector director, CameraComponent camera}) _rig({
  CameraDirector? director,
  CameraProjection? projection,
}) {
  final node = Node();
  final camera = CameraComponent(projection: projection);
  node.addComponent(camera);
  final d = director ?? CameraDirector();
  node.addComponent(d);
  return (node: node, director: d, camera: camera);
}

double _y(CameraDirector director) => director.pose.position.y;

// Steps the director in frames small enough to survive its per-frame clamp.
void _run(CameraDirector director, double seconds) {
  const step = 0.05;
  for (var t = 0.0; t < seconds - 1e-9; t += step) {
    director.update(step);
  }
}

void main() {
  group('CameraDirector', () {
    test('shows the first camera immediately, with no blend', () {
      final rig = _rig(
        director: CameraDirector(defaultBlend: const CameraBlend(10.0)),
      );
      final a = _atHeight(3.0);
      rig.director.add(a);
      rig.director.update(1 / 60);

      expect(rig.director.activeCamera, same(a));
      expect(rig.director.isBlending, isFalse);
      expect(_y(rig.director), closeTo(3.0, 1e-6));
      expect(rig.node.globalTransform.getTranslation().y, closeTo(3.0, 1e-6));
    });

    test('blendTo interpolates over the duration', () {
      final rig = _rig();
      final a = _atHeight(0.0);
      final b = _atHeight(10.0);
      rig.director.add(a);
      rig.director.update(0.05);

      rig.director.blendTo(b, duration: 1.0, curve: Curves.linear);
      _run(rig.director, 0.5);

      expect(rig.director.blendProgress, closeTo(0.5, 1e-6));
      expect(_y(rig.director), closeTo(5.0, 1e-5));

      _run(rig.director, 0.5);
      expect(rig.director.isBlending, isFalse);
      expect(_y(rig.director), closeTo(10.0, 1e-6));
    });

    test('cutTo switches with no interpolation', () {
      final rig = _rig();
      final a = _atHeight(0.0);
      final b = _atHeight(10.0);
      rig.director.add(a);
      rig.director.update(0.05);

      rig.director.cutTo(b);
      rig.director.update(0.05);
      expect(rig.director.isBlending, isFalse);
      expect(_y(rig.director), closeTo(10.0, 1e-6));
    });

    test('blends live, so the outgoing camera keeps tracking', () {
      final rig = _rig();
      final a = _atHeight(0.0);
      final b = _atHeight(10.0);
      rig.director.add(a);
      rig.director.update(0.05);

      rig.director.blendTo(b, duration: 1.0, curve: Curves.linear);
      _run(rig.director, 0.1); // 10% in: y = 1
      expect(_y(rig.director), closeTo(1.0, 1e-5));

      // The camera being left behind moves. A blend that had frozen it would
      // stay near y = 2 at the 20% mark; a live one follows it to 20.
      a.eye = Vector3(0.0, 20.0, -10.0);
      a.target = Vector3(0.0, 20.0, 0.0);
      _run(rig.director, 0.1);
      expect(rig.director.blendProgress, closeTo(0.2, 1e-6));
      expect(_y(rig.director), closeTo(20.0 + (10.0 - 20.0) * 0.2, 1e-4));
    });

    test('interrupting a blend continues from the live pose', () {
      final rig = _rig();
      final a = _atHeight(0.0);
      final b = _atHeight(100.0);
      final c = _atHeight(-100.0);
      rig.director.add(a);
      rig.director.update(0.05);

      rig.director.blendTo(b, duration: 1.0, curve: Curves.linear);
      _run(rig.director, 0.3);
      final interrupted = _y(rig.director);
      expect(interrupted, closeTo(30.0, 1e-4));

      rig.director.blendTo(c, duration: 1.0, curve: Curves.linear);
      rig.director.update(0.001);
      // No snap back to a, and no jump to c: the new blend leaves from where
      // the camera actually was.
      expect(_y(rig.director), closeTo(interrupted, 0.5));
    });

    test('priority picks the live camera and hands over on a change', () {
      final rig = _rig(
        director: CameraDirector(defaultBlend: const CameraBlend.cut()),
      );
      final low = _atHeight(0.0);
      final high = _atHeight(10.0);
      rig.director.add(low, priority: 0);
      rig.director.add(high, priority: 5);
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(high));

      rig.director.setPriority(high, -1);
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(low));
      expect(_y(rig.director), closeTo(0.0, 1e-6));
    });

    test('a disabled camera is out of the running', () {
      final rig = _rig(
        director: CameraDirector(defaultBlend: const CameraBlend.cut()),
      );
      final low = _atHeight(0.0);
      final high = _atHeight(10.0);
      rig.director.add(low, priority: 0);
      rig.director.add(high, priority: 5);
      rig.director.update(0.05);

      high.enabled = false;
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(low));
    });

    test('selection overrides priority until cleared', () {
      final rig = _rig(
        director: CameraDirector(defaultBlend: const CameraBlend.cut()),
      );
      final low = _atHeight(0.0);
      final high = _atHeight(10.0);
      rig.director.add(low, priority: 0);
      rig.director.add(high, priority: 5);
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(high));

      rig.director.cutTo(low);
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(low));

      rig.director.clearSelection(blend: const CameraBlend.cut());
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(high));
    });

    test('removing the live camera hands over', () {
      final rig = _rig(
        director: CameraDirector(defaultBlend: const CameraBlend.cut()),
      );
      final a = _atHeight(0.0);
      final b = _atHeight(10.0);
      rig.director.add(a, priority: 5);
      rig.director.add(b, priority: 0);
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(a));

      expect(rig.director.remove(a), isTrue);
      expect(a.isDirected, isFalse);
      rig.director.update(0.05);
      expect(rig.director.activeCamera, same(b));
    });

    test('reports transitions through onCameraChanged', () {
      final changes = <String>[];
      final rig = _rig(
        director: CameraDirector(
          defaultBlend: const CameraBlend.cut(),
          onCameraChanged: (from, to) => changes.add(
            '${from == null ? 'none' : 'some'}->'
            '${to == null ? 'none' : 'some'}',
          ),
        ),
      );
      final a = _atHeight(0.0);
      final b = _atHeight(10.0);
      rig.director.add(a);
      rig.director.update(0.05);
      rig.director.cutTo(b);
      rig.director.update(0.05);

      expect(changes, ['none->some', 'some->some']);
    });

    group('the lens', () {
      test('is left alone by a camera that does not specify one', () {
        final lens = PerspectiveProjection(fovRadiansY: 0.5);
        final rig = _rig(projection: lens);
        rig.director.add(_atHeight(0.0));
        rig.director.update(0.05);
        expect(rig.camera.projection, same(lens));
      });

      test('follows a camera that does specify one', () {
        final rig = _rig(projection: PerspectiveProjection());
        final ortho = OrthographicProjection(height: 8.0);
        final a = _FixedCamera(
          Vector3(0.0, 0.0, -10.0),
          Vector3.zero(),
          lens: ortho,
        );
        rig.director.add(a);
        rig.director.update(0.05);
        expect(rig.camera.projection, same(ortho));
      });

      test('blends between two lenses of the same kind', () {
        final rig = _rig(projection: PerspectiveProjection());
        final wide = _FixedCamera(
          Vector3(0.0, 0.0, -10.0),
          Vector3.zero(),
          lens: PerspectiveProjection(fovRadiansY: 0.4),
        );
        final narrow = _FixedCamera(
          Vector3(0.0, 0.0, -10.0),
          Vector3.zero(),
          lens: PerspectiveProjection(fovRadiansY: 1.0),
        );
        rig.director.add(wide);
        rig.director.update(0.05);

        rig.director.blendTo(narrow, duration: 1.0, curve: Curves.linear);
        _run(rig.director, 0.5);

        final projection = rig.camera.projection;
        expect(projection, isA<PerspectiveProjection>());
        expect(
          (projection as PerspectiveProjection).fovRadiansY,
          closeTo(0.7, 1e-5),
        );
      });
    });

    group('input forwarding', () {
      test('routes to the live camera', () {
        final rig = _rig(
          director: CameraDirector(defaultBlend: const CameraBlend.cut()),
        );
        final a = _atHeight(0.0);
        final b = _atHeight(10.0);
        rig.director.add(a);
        rig.director.add(b, priority: -1);
        rig.director.update(0.05);

        rig.director.input.handleDragUpdate(const Offset(1.0, 0.0));
        expect(a.drags, 1);
        expect(b.drags, 0);

        rig.director.cutTo(b);
        rig.director.update(0.05);
        rig.director.input.handleDragUpdate(const Offset(1.0, 0.0));
        expect(a.drags, 1);
        expect(b.drags, 1);
      });

      test('pushes the viewport size to every camera', () {
        final rig = _rig();
        final a = _atHeight(0.0);
        final b = _atHeight(10.0);
        rig.director.add(a);
        rig.director.add(b);
        rig.director.input.viewportSize = const Size(800.0, 600.0);

        expect(a.viewportSize, const Size(800.0, 600.0));
        expect(b.viewportSize, const Size(800.0, 600.0));
      });

      test('releases every camera, not just the live one', () {
        final rig = _rig();
        final a = _atHeight(0.0);
        final b = _atHeight(10.0);
        rig.director.add(a);
        rig.director.add(b);
        rig.director.input.releaseInput();

        expect(a.releases, 1);
        expect(b.releases, 1);
      });
    });

    test('shake displaces the pose without feeding back into blends', () {
      final shake = CameraShake(decayRate: 0.0)..addTrauma(1.0);
      final rig = _rig(director: CameraDirector(shake: shake));
      rig.director.add(_atHeight(0.0));

      var maxOffset = 0.0;
      for (var i = 0; i < 40; i++) {
        rig.director.update(0.05);
        maxOffset = maxOffset > rig.director.pose.position.length
            ? maxOffset
            : rig.director.pose.position.length;
      }
      // The camera sits on the +Z axis 10 units out; shake moves it off that
      // point but never accumulates away from it.
      expect(maxOffset, greaterThan(10.0));
      expect(rig.director.pose.position.length, lessThan(11.0));
    });

    test('a directed camera does not drive its own node', () {
      final rig = _rig();
      final ownNode = Node();
      final a = _atHeight(7.0);
      ownNode.addComponent(a);
      rig.director.add(a);

      a.update(0.05); // as the scene graph would tick it
      expect(ownNode.globalTransform.getTranslation().y, closeTo(0.0, 1e-9));

      rig.director.update(0.05);
      expect(rig.node.globalTransform.getTranslation().y, closeTo(7.0, 1e-6));
    });
  });
}
