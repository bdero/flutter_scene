import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/fake_frames.dart';

Matcher _closeToVector(Vector3 expected, {double epsilon = 1e-6}) =>
    predicate<Vector3>(
      (actual) => (actual - expected).length < epsilon,
      'is close to $expected',
    );

void main() {
  group('XrRig.applyFrame', () {
    test('produces one render view per frame view, ipd apart', () {
      final rig = XrRig();
      final frame = stereoFrame(head: Vector3(0, 1.6, 0), ipd: 0.064);
      final views = rig.applyFrame(frame);

      expect(views, hasLength(2));
      expect(identical(views, rig.views), isTrue);
      final left = views[0].camera.position;
      final right = views[1].camera.position;
      expect((right - left).length, closeTo(0.064, 1e-6));
      // Both eyes sit at head height, either side of the head.
      expect(left.y, closeTo(1.6, 1e-6));
      expect(right.y, closeTo(1.6, 1e-6));
      expect(
        rig.head.globalTransform.getTranslation(),
        _closeToVector(Vector3(0, 1.6, 0)),
      );
    });

    test('copies each view projection and viewport, and the frame target', () {
      final rig = XrRig();
      final frame = stereoFrame(head: Vector3(0, 1.6, 0));
      final views = rig.applyFrame(frame);
      for (var i = 0; i < 2; i++) {
        final lens = frame.views[i].projection;
        final projection = views[i].camera.projection as OffAxisProjection;
        expect(projection.tanLeft, lens.tanLeft);
        expect(projection.tanRight, lens.tanRight);
        expect(projection.tanDown, lens.tanDown);
        expect(projection.tanUp, lens.tanUp);
        expect(projection.near, lens.near);
        expect(projection.far, lens.far);
        expect(views[i].viewport, frame.views[i].viewport);
        expect(identical(views[i].externalTarget, frame.target), isTrue);
      }
      expect(views[0].viewport!.left, 0);
      expect(views[1].viewport!.left, 0.5);
    });

    test('eye cameras look where the runtime pose looks', () {
      final rig = XrRig();
      // Facing 90 degrees left of -Z is facing -X.
      final frame = stereoFrame(head: Vector3(0, 1.6, 0), yaw: math.pi / 2);
      final views = rig.applyFrame(frame);
      final expected = frame.views[0].pose.forward;
      expect(expected, _closeToVector(Vector3(-1, 0, 0)));
      // The default mapping reflects z, so the scene sees the mirrored
      // direction while the pose's own handedness is kept intact.
      final mapped = rig.xrToScene.transform3(expected.clone());
      expect(views[0].camera.forward, _closeToVector(mapped));
      expect(rig.gaze.direction, _closeToVector(mapped));
      expect(rig.gaze.origin, _closeToVector(Vector3(0, 1.6, 0)));
    });

    test('an identity xrToScene copies poses straight through', () {
      final rig = XrRig(xrToScene: Matrix4.identity());
      final frame = stereoFrame(head: Vector3(1, 2, 3), yaw: 0.3);
      rig.applyFrame(frame);
      final expected = frame.viewerPose!.toMatrix();
      final actual = rig.head.localTransform;
      for (var i = 0; i < 16; i++) {
        expect(actual.storage[i], closeTo(expected.storage[i], 1e-6));
      }
    });

    test('the default mapping keeps rotations proper and right on +x', () {
      final rig = XrRig();
      final frame = stereoFrame(head: Vector3.zero(), yaw: 0.0);
      rig.applyFrame(frame);
      final transform = rig.head.localTransform;
      expect(transform.determinant(), closeTo(1.0, 1e-6));
      expect(rig.head.right, _closeToVector(Vector3(1, 0, 0)));
      expect(rig.head.up, _closeToVector(Vector3(0, 1, 0)));
    });

    test('reuses its render views and projections across frames', () {
      final rig = XrRig();
      final first = rig.applyFrame(stereoFrame(head: Vector3(0, 1.6, 0)));
      final views = List.of(first);
      final projections = [for (final v in first) v.camera.projection];
      final second = rig.applyFrame(stereoFrame(head: Vector3(0, 1.7, 0.5)));
      for (var i = 0; i < 2; i++) {
        expect(identical(second[i], views[i]), isTrue);
        expect(identical(second[i].camera.projection, projections[i]), isTrue);
      }
      expect(second[0].camera.position.y, closeTo(1.7, 1e-6));
    });

    test('moving the origin moves the eyes with it', () {
      final rig = XrRig();
      rig.origin.position = Vector3(10, 0, 0);
      final views = rig.applyFrame(stereoFrame(head: Vector3(0, 1.6, 0)));
      final mid = (views[0].camera.position + views[1].camera.position) * 0.5;
      expect(mid, _closeToVector(Vector3(10, 1.6, 0)));
    });

    test('drives controller, target ray and hand nodes', () {
      final rig = XrRig();
      final ray = XrPose(
        position: Vector3(0.3, 1.2, -0.2),
        orientation: Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
      );
      final right = controllerState(
        id: 1,
        handedness: XrHandedness.right,
        targetRay: ray,
      );
      final hand = XrHand();
      hand.jointTracked[XrHandJoint.indexFingerTip.index] = true;
      hand.jointPoses[XrHandJoint.indexFingerTip.index].position.setValues(
        -0.3,
        1.0,
        -0.4,
      );
      final left = XrInputSourceState(
        id: 2,
        handedness: XrHandedness.left,
        targetRayMode: XrTargetRayMode.trackedPointer,
      )..hand = hand;

      rig.applyFrame(
        stereoFrame(head: Vector3(0, 1.6, 0), inputSources: [right, left]),
      );
      final controller = rig.controller(XrHandedness.right);
      expect(controller.visible, isTrue);
      expect(
        controller.globalTransform.getTranslation(),
        _closeToVector(rig.xrToScene.transform3(ray.position.clone())),
      );
      // A ray pitched 90 degrees down points along -y, in either convention.
      expect(
        rig.targetRay(XrHandedness.right).forward,
        _closeToVector(Vector3(0, -1, 0)),
      );
      final tip = rig.handJoints(
        XrHandedness.left,
      )[XrHandJoint.indexFingerTip.index];
      expect(tip.visible, isTrue);
      expect(
        rig.handJoints(XrHandedness.left)[XrHandJoint.wrist.index].visible,
        isFalse,
      );
      expect(
        tip.globalTransform.getTranslation(),
        _closeToVector(rig.xrToScene.transform3(Vector3(-0.3, 1.0, -0.4))),
      );

      // The next frame without the controller hides it.
      rig.applyFrame(stereoFrame(head: Vector3(0, 1.6, 0)));
      expect(controller.visible, isFalse);
      expect(rig.hand(XrHandedness.left).visible, isFalse);
    });
  });
}
