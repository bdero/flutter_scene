@TestOn('browser')
library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_scene/scene.dart' show RenderView;
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/iwer.dart';

Matcher _closeToVector(Vector3 expected, {double epsilon = 1e-5}) =>
    predicate<Vector3?>(
      (actual) => actual != null && (actual - expected).length < epsilon,
      'is close to $expected',
    );

// A rotation and its negation are the same rotation.
Matcher _closeToRotation(Quaternion expected, {double epsilon = 1e-5}) =>
    predicate<Quaternion?>(
      (actual) =>
          actual != null &&
          math.min((actual - expected).length, (actual + expected).length) <
              epsilon,
      'is close to $expected',
    );

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 1e-6));
  expect(actual.top, closeTo(expected.top, 1e-6));
  expect(actual.width, closeTo(expected.width, 1e-6));
  expect(actual.height, closeTo(expected.height, 1e-6));
}

const _vrLocalFloor = XrSessionRequest(
  mode: XrSessionMode.immersiveVr,
  referenceSpaces: [XrReferenceSpaceType.localFloor],
);

void main() {
  late IwerDevice device;

  setUpAll(() {
    device = installIwer();
  });

  tearDownAll(uninstallIwer);

  // The device outlives each test; put it back where the next one expects.
  setUp(() {
    device.position.setValues(0, 1.6, 0);
    device.quaternion.setValues(0, 0, 0, 1);
    device.fovy = math.pi / 2;
    device.primaryInputMode = 'controller';
    device.updateVisibilityState('visible');
  });

  test('reports every mode the emulated device supports', () async {
    final runtime = XrRuntime.instance;
    expect(runtime.isSupported, isTrue);
    expect(await runtime.isSessionSupported(XrSessionMode.immersiveVr), isTrue);
    expect(await runtime.isSessionSupported(XrSessionMode.immersiveAr), isTrue);
    expect(await runtime.isSessionSupported(XrSessionMode.inline), isTrue);
  });

  test('starts an immersive VR session with a stereo first frame', () async {
    final session = await startSession(
      const XrSessionRequest(
        mode: XrSessionMode.immersiveVr,
        referenceSpaces: [XrReferenceSpaceType.local],
      ),
    );
    expect(session.mode, XrSessionMode.immersiveVr);
    expect(session.blendMode, XrBlendMode.opaque);
    expect(session.isEnded, isFalse);
    expect(session.referenceSpaceType, XrReferenceSpaceType.local);

    final frame = await nextFrame(session);
    expect(frame.referenceSpaceType, XrReferenceSpaceType.local);
    expect(frame.views.map((view) => view.eye), [XrEye.left, XrEye.right]);
    expect(frame.hasTargets, isTrue);
    expect(frame.views.every((view) => !view.hasOwnTarget), isTrue);
    final width = frame.targetWidth!;
    final height = frame.targetHeight!;
    expect(width, greaterThan(0));
    expect(height, greaterThan(0));
    // The layer takes the window's shape; allow a pixel of rounding.
    final (innerWidth, innerHeight) = windowInnerSize();
    expect(width, closeTo(height * innerWidth / innerHeight, 1.0));
    // IWER rebases local to the head pose at request time, so the viewer
    // sits at the origin here; the floor spaces keep the global origin.
    expect(frame.viewerPosition, _closeToVector(Vector3.zero()));
    expect(frame.viewerOrientation, _closeToRotation(Quaternion.identity()));
    expect(
      frame.views[1].position - frame.views[0].position,
      _closeToVector(Vector3(device.ipd, 0, 0)),
    );
  });

  test('gives each eye half the target, side by side', () async {
    final session = await startSession(_vrLocalFloor);
    final frame = await nextFrame(session);
    expect(frame.views, hasLength(2));
    _expectRect(frame.views[0].viewport, const Rect.fromLTWH(0, 0, 0.5, 1));
    _expectRect(frame.views[1].viewport, const Rect.fromLTWH(0.5, 0, 0.5, 1));
  });

  test(
    'decodes a symmetric lens at the device fov and follows changes',
    () async {
      final session = await startSession(_vrLocalFloor);
      final frame = await nextFrame(session);
      final aspect = (frame.targetWidth! / 2) / frame.targetHeight!;
      for (final view in frame.views) {
        expect(view.fovRadiansY, closeTo(math.pi / 2, 1e-5));
        expect(view.tanRight, closeTo(-view.tanLeft, 1e-6));
        expect(view.tanUp, closeTo(-view.tanDown, 1e-6));
        expect(view.tanUp, closeTo(math.tan(math.pi / 4), 1e-5));
        expect(view.aspectRatio, closeTo(aspect, 1e-4));
        expect(view.near, closeTo(0.1, 1e-4));
        // Far is ill-conditioned in a float32 matrix.
        expect(view.far, closeTo(1000, 2));
      }

      device.fovy = 1.2;
      final narrowed = await nextFrame(session, skip: 1);
      for (final view in narrowed.views) {
        expect(view.fovRadiansY, closeTo(1.2, 1e-5));
        expect(view.aspectRatio, closeTo(aspect, 1e-4));
      }
    },
  );

  test(
    'reports the viewer pose and eyes ipd apart, then follows the device',
    () async {
      final session = await startSession(_vrLocalFloor);
      final ipd = device.ipd;
      expect(ipd, closeTo(0.063, 1e-9));

      final frame = await nextFrame(session);
      expect(frame.viewerPosition, _closeToVector(Vector3(0, 1.6, 0)));
      expect(frame.viewerOrientation, _closeToRotation(Quaternion.identity()));
      final left = frame.views[0];
      final right = frame.views[1];
      expect(left.position, _closeToVector(Vector3(-ipd / 2, 1.6, 0)));
      expect(right.position, _closeToVector(Vector3(ipd / 2, 1.6, 0)));
      expect(left.orientation, _closeToRotation(Quaternion.identity()));
      expect(right.orientation, _closeToRotation(Quaternion.identity()));

      // A quarter turn left about Y takes local +X to world -Z.
      final yaw = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      device.position.setValues(0.5, 1.2, -2);
      device.quaternion.setValues(yaw.x, yaw.y, yaw.z, yaw.w);
      final moved = await nextFrame(session, skip: 1);
      expect(moved.viewerPosition, _closeToVector(Vector3(0.5, 1.2, -2)));
      expect(moved.viewerOrientation, _closeToRotation(yaw));
      final eyeOffset = moved.views[1].position - moved.views[0].position;
      expect(eyeOffset, _closeToVector(Vector3(0, 0, -ipd)));
      expect(moved.views[0].orientation, _closeToRotation(yaw));
      expect(moved.views[1].orientation, _closeToRotation(yaw));
    },
  );

  test('drives a rig into the scene convention', () async {
    final session = await startSession(_vrLocalFloor);
    device.position.setValues(0.3, 1.6, -1.5);
    final rig = XrRig();
    List<RenderView>? views;
    final frame = await nextFrame(
      session,
      skip: 1,
      onFrame: (frame) => views = List.of(rig.applyFrame(frame)),
    );
    expect(views, hasLength(2));
    expect(rig.eyes, hasLength(2));
    expect(rig.eyeCameras, hasLength(2));
    final viewer = frame.viewerPosition!;
    // The default xrToScene reflects Z.
    expect(
      rig.head.globalTransform.getTranslation(),
      _closeToVector(Vector3(viewer.x, viewer.y, -viewer.z)),
    );
    final leftEye = views![0].camera.position;
    final rightEye = views![1].camera.position;
    expect((rightEye - leftEye).length, closeTo(device.ipd, 1e-5));
    expect(leftEye.y, closeTo(1.6, 1e-5));
    for (var i = 0; i < 2; i++) {
      expect(views![i].viewport, frame.views[i].viewport);
      expect(views![i].externalTarget, isNotNull);
    }
  });

  test('runs an AR session with hit testing and anchors', () async {
    final session = await startSession(
      const XrSessionRequest(
        mode: XrSessionMode.immersiveAr,
        optionalFeatures: [
          XrFeatures.hitTest,
          XrFeatures.anchors,
          XrFeatures.planeDetection,
        ],
        referenceSpaces: [XrReferenceSpaceType.localFloor],
      ),
    );
    expect(session.blendMode, XrBlendMode.alphaBlend);
    final features = session.features;
    expect(session.hitTest != null, features.contains(XrFeatures.hitTest));
    expect(session.anchors != null, features.contains(XrFeatures.anchors));
    expect(
      session.planes != null,
      features.contains(XrFeatures.planeDetection),
    );
    expect(session.depthSensing, isNull);
    expect(session.lightEstimation, isNull);

    final hitTest = session.hitTest;
    expect(hitTest, isNotNull, reason: 'metaQuest3 supports hit-test');
    final source = await hitTest!.requestSource(const XrHitTestOrigin.viewer());
    // No synthetic environment here, so hits may be empty; the request and
    // the per-frame read must still work.
    if (source != null) {
      List<XrHitTestResult>? results;
      await nextFrame(session, onFrame: (_) => results = source.results);
      expect(results, isNotNull);
      source.cancel();
    }

    final anchors = session.anchors;
    expect(anchors, isNotNull, reason: 'metaQuest3 supports anchors');
    Future<XrAnchor?>? pending;
    await nextFrame(
      session,
      onFrame: (frame) => pending = anchors!.createAnchor(
        XrPose(position: frame.viewerPose!.position.clone()),
      ),
    );
    final anchor = await pending!.timeout(frameTimeout);
    expect(anchor, isNotNull);
    await nextFrame(session, skip: 1);
    expect(anchors!.tracked, contains(anchor));
    expect(anchor!.isTracked, isTrue);
    expect(
      anchor.pose.position,
      _closeToVector(Vector3(0, 1.6, 0), epsilon: 1e-4),
    );
    anchor.delete();
    await nextFrame(session, skip: 1);
    expect(anchors.tracked, isNot(contains(anchor)));

    final planes = session.planes;
    if (planes != null) {
      List<XrPlane>? detected;
      await nextFrame(
        session,
        onFrame: (_) => detected = List.of(planes.planes),
      );
      expect(detected, isNotNull);
    }
  });

  test('takes the first granted reference space in request order', () async {
    final bounded = await startSession(
      const XrSessionRequest(
        mode: XrSessionMode.immersiveVr,
        referenceSpaces: [
          XrReferenceSpaceType.boundedFloor,
          XrReferenceSpaceType.local,
        ],
      ),
    );
    expect(bounded.referenceSpaceType, XrReferenceSpaceType.boundedFloor);
    expect(bounded.features, contains(XrFeatures.boundedFloor));
    final boundedFrame = await nextFrame(bounded);
    expect(boundedFrame.referenceSpaceType, XrReferenceSpaceType.boundedFloor);
    expect(boundedFrame.viewerPosition, _closeToVector(Vector3(0, 1.6, 0)));
    await bounded.end();

    final viewer = await startSession(
      const XrSessionRequest(
        mode: XrSessionMode.immersiveVr,
        referenceSpaces: [XrReferenceSpaceType.viewer],
      ),
    );
    expect(viewer.referenceSpaceType, XrReferenceSpaceType.viewer);
    final viewerFrame = await nextFrame(viewer);
    expect(viewerFrame.referenceSpaceType, XrReferenceSpaceType.viewer);
    // In viewer space the viewer is the origin.
    expect(viewerFrame.viewerPosition, _closeToVector(Vector3.zero()));
    expect(
      viewerFrame.views[1].position - viewerFrame.views[0].position,
      _closeToVector(Vector3(device.ipd, 0, 0)),
    );
  });

  test(
    'drops input sources while hidden and restores them when visible',
    () async {
      final session = await startSession(_vrLocalFloor);
      final visible = await frameWhere(
        session,
        (frame) => frame.inputSources.length == 2,
      );
      expect(visible.inputSources, hasLength(2));

      device.updateVisibilityState('hidden');
      final hidden = await nextFrame(session, skip: 2);
      expect(hidden.inputSources, isEmpty);
      expect(session.inputSources, isEmpty);

      device.updateVisibilityState('visible');
      final restored = await frameWhere(
        session,
        (frame) => frame.inputSources.length == 2,
      );
      expect(restored.inputSources, hasLength(2));
    },
  );

  // Last in the file, since it uninstalls the runtime.
  test(
    'end() stops frames, removes the canvas, and uninstall withdraws support',
    () async {
      final canvasesBefore = canvasCount();
      final fixedBefore = fixedCanvasCount();
      final session = await startSession(_vrLocalFloor);
      await nextFrame(session);
      expect(fixedCanvasCount(), fixedBefore + 1);

      var framesAfterEnd = 0;
      final subscription = session.frames.listen((_) {
        if (session.isEnded) framesAfterEnd++;
      });
      await session.end();
      expect(session.isEnded, isTrue);
      expect(await session.ended, XrSessionEndReason.ended);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await subscription.cancel();
      expect(framesAfterEnd, 0);
      expect(fixedCanvasCount(), fixedBefore);
      expect(canvasCount(), canvasesBefore);

      uninstallIwer();
      expect(
        await XrRuntime.instance.isSessionSupported(XrSessionMode.immersiveVr),
        isFalse,
      );
    },
  );
}
