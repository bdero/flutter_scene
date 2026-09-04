// Covers CameraRig: each preset assembles a node, camera component, director,
// and typed controller that are actually wired to each other.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('CameraRig', () {
    test('wires the node, camera, director, and controller together', () {
      final rig = CameraRig.orbit(distance: 12.0);

      expect(rig.node.getComponent<CameraComponent>(), same(rig.camera));
      expect(rig.node.getComponent<CameraDirector>(), same(rig.director));
      expect(rig.director.cameras, contains(rig.controller));
      expect(rig.controller.isDirected, isTrue);
      expect(rig.camera.activateOnMount, isTrue);
    });

    test('drives the node through the director', () {
      final rig = CameraRig.orbit(distance: 12.0);
      rig.director.update(1 / 60);
      final eye = rig.node.globalTransform.getTranslation();
      expect(eye.length, closeTo(12.0, 0.5));
    });

    test('gives back a typed controller', () {
      final first = CameraRig.firstPerson();
      // No cast needed: the rig's type parameter carries the camera's type.
      first.controller.addRecoil(0.1);

      final strategy = CameraRig.rts();
      strategy.controller.zoomBy(1.0);

      final shot = CameraRig.dolly(
        path: CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, 10.0)),
      );
      expect(shot.controller.progress, 0.0);
    });

    test('first person uses a wider lens than the engine default', () {
      final rig = CameraRig.firstPerson();
      final lens = rig.camera.projection;
      expect(lens, isA<PerspectiveProjection>());
      expect(
        (lens as PerspectiveProjection).fovRadiansY,
        closeTo(75 * degrees2Radians, 1e-9),
      );
    });

    test('isometric starts with a parallel lens, before the first frame', () {
      // The controller would set this on its first advance, but a rig that
      // only got it then would render one perspective frame first.
      final rig = CameraRig.isometric(viewHeight: 18.0);
      final lens = rig.camera.projection;
      expect(lens, isA<OrthographicProjection>());
      expect((lens as OrthographicProjection).height, closeTo(18.0, 1e-9));
      expect(rig.controller.pitch, closeTo(math.atan(1 / math.sqrt2), 1e-9));
    });

    test('top down looks straight down', () {
      final rig = CameraRig.topDown(height: 25.0);
      rig.director.update(1 / 60);
      expect(rig.director.pose.forward.y, closeTo(-1.0, 1e-5));
      expect(rig.node.globalTransform.getTranslation().y, closeTo(25.0, 1e-4));
    });

    test('third person probes for occluders only when asked to', () {
      final player = Node();
      expect(
        CameraRig.thirdPerson(followTarget: player).controller.occlusionProbe,
        isNull,
      );

      final rig = CameraRig.thirdPerson(
        followTarget: player,
        occludeAgainst: Node(),
      );
      expect(rig.controller.occlusionProbe, isNotNull);
      expect(rig.controller.followTarget, same(player));
    });

    test('add registers a second shot for blending', () {
      final rig = CameraRig.orbit();
      final cutscene = rig.add(
        DollyCameraController(
          path: CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, 10.0)),
        ),
        name: 'cutscene',
      );
      expect(rig.director.byName('cutscene'), same(cutscene));

      rig.director.cutTo(cutscene);
      rig.director.update(1 / 60);
      expect(rig.director.activeCamera, same(cutscene));
    });

    test('input forwards to the live camera', () {
      final rig = CameraRig.orbit(distance: 10.0);
      rig.director.update(1 / 60);
      rig.input.viewportSize = const Size(400.0, 400.0);
      rig.input.handleScroll(-120.0);
      rig.director.update(1 / 60);
      expect(rig.controller.distance, lessThan(10.0));
    });

    test('shake reaches the director', () {
      final shake = CameraShake();
      final rig = CameraRig.firstPerson(shake: shake);
      expect(rig.shake, same(shake));
      expect(rig.director.shake, same(shake));
    });
  });
}
