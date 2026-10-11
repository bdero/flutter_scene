import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'emulated_xr/emulated_xr.dart';

export 'emulated_xr/emulated_xr.dart'
    show
        createBackendFramebuffer,
        deleteBackendFramebuffer,
        emulatedLayerSize,
        emulatedXrSupported,
        readBackendFramebuffer;

/// Where the emulated head sits, in WebXR space (-Z forward): back from the
/// stereo scene and pitched down onto it.
final vm.Vector3 kEmulatedHeadPosition = vm.Vector3(0.0, 1.3, 2.6);
final vm.Quaternion kEmulatedHeadOrientation = vm.Quaternion.axisAngle(
  vm.Vector3(1.0, 0.0, 0.0),
  -25.0 * vm.degrees2Radians,
);

/// The emulator's lens, a symmetric 90 degree vertical field with 63 mm
/// between the eyes, at its default clip range.
const double kEmulatedFovY = math.pi / 2;
const double kEmulatedIpd = 0.063;
const double kEmulatedNear = 0.1;
const double kEmulatedFar = 1000.0;

XrSession? _session;

/// The one immersive session the smoke run shares, started on first use with
/// the head at [kEmulatedHeadPosition]. Poses are read in the floor space; a
/// `local` space is rebased to the head at request time, which would put the
/// head at the origin.
Future<XrSession> emulatedXrSession() async {
  final existing = _session;
  if (existing != null && !existing.isEnded) return existing;
  await installEmulatedXr(
    position: kEmulatedHeadPosition,
    orientation: kEmulatedHeadOrientation,
  );
  return _session = await XrRuntime.instance.requestSession(
    const XrSessionRequest(
      mode: XrSessionMode.immersiveVr,
      referenceSpaces: [XrReferenceSpaceType.localFloor],
    ),
  );
}

/// Renders [scene] through [session] for [frames] display frames with a fresh
/// rig and returns the last frame, whose target holds that render.
Future<XrFrame> renderEmulatedFrames(
  Scene scene,
  XrSession session, {
  int frames = 3,
}) {
  final loop = XrSceneLoop(scene: scene, rig: XrRig(), session: session);
  final done = Completer<XrFrame>();
  var rendered = 0;
  late final StreamSubscription<XrFrame> subscription;
  subscription = session.frames.listen((frame) {
    loop.handleFrame(frame);
    if (!frame.hasTargets || ++rendered < frames) return;
    subscription.cancel();
    done.complete(frame);
  });
  return done.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      subscription.cancel();
      throw TimeoutException(
        'The emulated session delivered $rendered renderable frames.',
      );
    },
  );
}

/// Renders the pair the emulator would ask for, placed by hand through a rig
/// from the same head pose, into [target]. The reference for the session's
/// own frames.
void renderFlatPair(Scene scene, ExternalRenderTarget target) {
  final head = vm.Matrix4.compose(
    kEmulatedHeadPosition,
    kEmulatedHeadOrientation,
    vm.Vector3.all(1.0),
  );
  XrView eye(XrEye which, double x, Rect viewport) => XrView(
    eye: which,
    pose: XrPose(
      position: head.transform3(vm.Vector3(x, 0.0, 0.0)),
      orientation: kEmulatedHeadOrientation.clone(),
    ),
    projection: OffAxisProjection.symmetric(
      fovRadiansY: kEmulatedFovY,
      aspectRatio: (target.width / 2) / target.height,
      near: kEmulatedNear,
      far: kEmulatedFar,
    ),
    viewport: viewport,
  );
  final frame = XrFrame(
    predictedDisplayTime: Duration.zero,
    referenceSpaceType: XrReferenceSpaceType.localFloor,
    viewerPose: XrPose(
      position: kEmulatedHeadPosition.clone(),
      orientation: kEmulatedHeadOrientation.clone(),
    ),
    target: target,
    views: [
      eye(XrEye.left, -kEmulatedIpd / 2, const Rect.fromLTWH(0, 0, 0.5, 1)),
      eye(XrEye.right, kEmulatedIpd / 2, const Rect.fromLTWH(0.5, 0, 0.5, 1)),
    ],
  );
  final views = XrRig().applyFrame(frame);
  scene.update(0.0);
  scene.renderViewsToTargets([RenderViewGroup(views)]);
}
