/// XR sessions for Flutter Scene.
///
/// An [XrRuntime] starts an [XrSession], which delivers an [XrFrame] of
/// [XrView]s per display frame. An [XrRig] turns those into camera nodes and
/// `RenderView`s, an [XrSceneLoop] renders a `Scene` through the rig for every
/// frame, and an [XrInputSource] publishes the session's controllers and hands
/// into `flutter_scene_input`. The only runtime today is WebXR, selected on
/// the web; elsewhere `XrRuntime.instance.isSupported` is false.
library;

export 'src/features/anchors.dart' show XrAnchor, XrAnchors;
export 'src/features/depth.dart' show XrDepthInformation, XrDepthSensing;
export 'src/features/hit_test.dart'
    show
        XrHitTestInputSourceOrigin,
        XrHitTestOrigin,
        XrHitTestResult,
        XrHitTestSource,
        XrHitTestViewerOrigin,
        XrHitTesting;
export 'src/features/light_estimation.dart'
    show XrLightEstimate, XrLightEstimation;
export 'src/features/planes.dart'
    show XrPlane, XrPlaneDetection, XrPlaneOrientation;
export 'src/xr_frame.dart' show XrFrame;
export 'src/xr_input_source.dart' show XrInputSource;
export 'src/xr_input_state.dart'
    show
        XrGamepadState,
        XrHand,
        XrHandJoint,
        XrHandedness,
        XrInputSourceState,
        XrTargetRayMode;
export 'src/xr_pose.dart' show XrPose;
export 'src/xr_rig.dart' show XrRig;
export 'src/xr_runtime.dart' show XrRuntime;
export 'src/xr_scene_loop.dart' show XrSceneLoop;
export 'src/xr_session.dart'
    show
        XrBlendMode,
        XrFeatures,
        XrReferenceSpaceType,
        XrSession,
        XrSessionEndReason,
        XrSessionMode,
        XrSessionRequest;
export 'src/xr_view.dart' show XrEye, XrView;
