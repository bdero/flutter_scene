/// Codecs for the camera controllers, so a rig authored in the editor is the
/// rig the game runs.
///
/// Every controller is already a [CameraController], which is a [Component];
/// these codecs are what let one be saved, reloaded, and edited by property
/// rather than only assembled in code.
///
/// Two conventions run through the file:
///
///  * **Pose versus tuning.** A controller's tuning (speeds, limits,
///    sensitivities) is public and mutable, so those fields read and write
///    directly. Its live pose (yaw, pitch, distance, focus) is deliberately
///    read-only — input owns it — so those fields serialize through `read` and
///    are restored through the constructor in `create`, with no `write`. The
///    effect is that an authored starting pose survives a round trip without
///    the editor being able to fight the controller for it mid-frame.
///  * **Unlimited distances.** `maxDistance` defaults to `double.infinity`,
///    which has no JSON form, so the document spells it `0` — the same
///    "0 means no limit" convention [PointLightComponent]'s range uses.
///
/// Callback-shaped configuration (a `FollowCameraController.occlusionProbe`,
/// an `RtsCameraController.groundHeightAt`, a `DollyCameraController.easing`
/// or `onFinished`) has no document form and stays code-provided: it is not
/// declared here, so it is neither written nor silently blanked on load.
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/camera_director.dart';
import 'package:flutter_scene/src/camera_controllers/camera_path.dart';
import 'package:flutter_scene/src/camera_controllers/camera_sequence.dart';
import 'package:flutter_scene/src/camera_controllers/dolly_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/first_person_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/fly_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/follow_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/orbit_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/rts_camera_controller.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/fscene/realize/ref_read.dart';
import 'package:flutter_scene/src/fscene/realize/virtual_camera_codec.dart';
import 'package:flutter_scene/src/kit/camera/camera_shake.dart';
import 'package:flutter_scene/src/node.dart';

/// Registers the camera-controller codecs into [registry].
void registerCameraControllerCodecs(FsceneComponentRegistry registry) {
  registry
    ..register(OrbitCameraControllerCodec())
    ..register(FlyCameraControllerCodec())
    ..register(FollowCameraControllerCodec())
    ..register(FirstPersonCameraControllerCodec())
    ..register(RtsCameraControllerCodec())
    ..register(DollyCameraControllerCodec())
    ..register(CameraDirectorCodec())
    ..register(CameraSequenceCodec())
    ..register(VirtualCameraCodec());
}

// --- Shared conventions ---

/// The document form of a distance limit: `0` for [double.infinity].
double _encodeLimit(double value) => value.isFinite ? value : 0.0;

/// The live form of a distance limit read back from a document.
double _decodeLimit(double value) => value <= 0.0 ? double.infinity : value;

ComponentField<C> _smoothingField<C extends CameraController>(
  double defaultValue,
) => ComponentField.number(
  'smoothing',
  defaultValue: defaultValue,
  doc:
      'Approximate seconds to settle after input stops. Zero moves instantly '
      'with no easing.',
  constraints: const [Range.nonNegative(), SoftRange(0, 1)],
  get: (c) => c.smoothing,
  set: (c, v) => c.smoothing = v,
);

/// A pose field: serialized from the live controller, restored through the
/// constructor. See the library doc.
ComponentField<C> _poseField<C extends Component>(
  String name, {
  required double defaultValue,
  required double Function(C component) get,
  required String doc,
  List<PropertyConstraint<num>> constraints = const [],
}) => ComponentField(
  ComponentPropertyDef(
    name,
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(defaultValue),
    doc: doc,
    constraints: constraints,
  ),
  read: (c, _) => DoubleValue(get(c)),
);

ComponentField<C> _vectorPoseField<C extends Component>(
  String name, {
  required Vector3 defaultValue,
  required Vector3 Function(C component) get,
  required String doc,
}) => ComponentField(
  ComponentPropertyDef(
    name,
    ComponentPropertyKind.vec3,
    defaultValue: Vec3Value(defaultValue),
    doc: doc,
  ),
  read: (c, _) => Vec3Value(get(c)),
);

ComponentField<C> _followTargetField<C extends Component>(
  Node? Function(C component) get,
  String doc,
) => ComponentField(
  ComponentPropertyDef('followTarget', ComponentPropertyKind.nodeRef, doc: doc),
  read: (c, _) => nodeRefOf(get(c)),
);

Node? _resolveNode(PropertyReader props, String name) {
  final id = props.nodeId(name);
  if (id == null) return null;
  final node = props.context.resolveNode?.call(id);
  if (node == null) {
    debugPrint(
      'fscene: camera controller $name $id did not resolve; leaving it unset',
    );
  }
  return node;
}

// --- The shot lens ---

/// A [CameraProjection] carried by a shot, in the same flat spelling the
/// camera component uses, nested one level so it can be absent entirely.
const _lensFields = [
  ComponentPropertyDef(
    'projection',
    ComponentPropertyKind.string,
    defaultValue: StringValue('perspective'),
    options: ['perspective', 'orthographic'],
    doc: 'The lens model.',
  ),
  ComponentPropertyDef(
    'fovRadiansY',
    ComponentPropertyKind.number,
    doc: 'Vertical field of view, in radians. Perspective lenses only.',
  ),
  ComponentPropertyDef(
    'height',
    ComponentPropertyKind.number,
    doc: 'Vertical extent, in world units. Orthographic lenses only.',
  ),
  ComponentPropertyDef('near', ComponentPropertyKind.number, doc: 'Near clip.'),
  ComponentPropertyDef('far', ComponentPropertyKind.number, doc: 'Far clip.'),
];

ComponentField<C> _lensField<C extends Component>(
  CameraProjection? Function(C component) get,
  void Function(C component, CameraProjection? value) set,
) => ComponentField(
  const ComponentPropertyDef(
    'lens',
    ComponentPropertyKind.object,
    objectFields: _lensFields,
    doc:
        'The lens this shot asks for, or absent to leave the camera\'s own '
        'alone.',
  ),
  read: (c, _) => _encodeLens(get(c)),
  write: (c, v, _) => set(c, v is MapValue ? _decodeLens(v) : null),
);

MapValue? _encodeLens(CameraProjection? lens) => switch (lens) {
  PerspectiveProjection(:final fovRadiansY, :final near, :final far) =>
    MapValue({
      'projection': const StringValue('perspective'),
      'fovRadiansY': DoubleValue(fovRadiansY),
      'near': DoubleValue(near),
      'far': DoubleValue(far),
    }),
  OrthographicProjection(:final height, :final near, :final far) => MapValue({
    'projection': const StringValue('orthographic'),
    'height': DoubleValue(height),
    'near': DoubleValue(near),
    'far': DoubleValue(far),
  }),
  // A lens of some other kind has no flat spelling; leaving it out beats
  // saving it as a perspective lens it is not.
  _ => null,
};

CameraProjection? _decodeLens(MapValue value) {
  double read(String name, double fallback) => switch (value.values[name]) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => fallback,
  };
  final tag = switch (value.values['projection']) {
    StringValue(value: final v) => v,
    _ => 'perspective',
  };
  return tag == 'orthographic'
      ? OrthographicProjection(
          height: read('height', 10.0),
          near: read('near', 0.1),
          far: read('far', 1000.0),
        )
      : PerspectiveProjection(
          fovRadiansY: read('fovRadiansY', 45 * degrees2Radians),
          near: read('near', 0.1),
          far: read('far', 1000.0),
        );
}

// --- Orbit ---

/// Codec for [OrbitCameraController], the turntable camera.
class OrbitCameraControllerCodec
    extends DeclarativeComponentCodec<OrbitCameraController> {
  @override
  String get type => 'orbitCameraController';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<OrbitCameraController>> get fields => [
    ComponentField(
      ComponentPropertyDef(
        'target',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3.zero()),
        doc: 'The point the camera orbits.',
      ),
      read: (c, _) => Vec3Value(c.target),
      write: (c, v, _) {
        if (v is Vec3Value) c.target = v.value;
      },
    ),
    _poseField(
      'distance',
      defaultValue: 6.0,
      doc: 'Distance from the target to the camera.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.distance,
    ),
    _poseField(
      'azimuth',
      defaultValue: 0.0,
      doc: 'Rotation around world up, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.azimuth,
    ),
    _poseField(
      'polar',
      defaultValue: 0.3,
      doc: 'Elevation above the target, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.polar,
    ),
    ComponentField.number(
      'minDistance',
      defaultValue: 0.1,
      doc: 'Closest the camera may dolly in.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.minDistance,
      set: (c, v) => c.minDistance = v,
    ),
    ComponentField.number(
      'maxDistance',
      defaultValue: 0.0,
      doc: 'Furthest the camera may dolly out, or 0 for no limit.',
      constraints: const [Range.nonNegative()],
      get: (c) => _encodeLimit(c.maxDistance),
      set: (c, v) => c.maxDistance = _decodeLimit(v),
    ),
    ComponentField.number(
      'minPolar',
      defaultValue: -(math.pi / 2 - 0.02),
      doc: 'Lowest elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.minPolar,
      set: (c, v) => c.minPolar = v,
    ),
    ComponentField.number(
      'maxPolar',
      defaultValue: math.pi / 2 - 0.02,
      doc: 'Highest elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.maxPolar,
      set: (c, v) => c.maxPolar = v,
    ),
    ComponentField.number(
      'rotateSpeed',
      defaultValue: math.pi,
      doc: 'Radians of orbit per full drag across the viewport.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.rotateSpeed,
      set: (c, v) => c.rotateSpeed = v,
    ),
    ComponentField.number(
      'dollySpeed',
      defaultValue: 0.15,
      doc: 'Dolly response per unit of scroll or pinch.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.dollySpeed,
      set: (c, v) => c.dollySpeed = v,
    ),
    ComponentField.number(
      'panSpeed',
      defaultValue: 1.0,
      doc: 'Pan distance as a multiple of the current orbit distance.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.panSpeed,
      set: (c, v) => c.panSpeed = v,
    ),
    ComponentField.number(
      'scrollSensitivity',
      defaultValue: 1 / 120,
      doc: 'Scroll notch to dolly amount.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.scrollSensitivity,
      set: (c, v) => c.scrollSensitivity = v,
    ),
    _smoothingField(0.12),
  ];

  @override
  OrbitCameraController create(PropertyReader props) => OrbitCameraController(
    target: props.vec3('target'),
    distance: props.number('distance'),
    azimuth: props.number('azimuth'),
    polar: props.number('polar'),
    minDistance: props.number('minDistance'),
    maxDistance: _decodeLimit(props.number('maxDistance')),
    minPolar: props.number('minPolar'),
    maxPolar: props.number('maxPolar'),
    rotateSpeed: props.number('rotateSpeed'),
    dollySpeed: props.number('dollySpeed'),
    panSpeed: props.number('panSpeed'),
    scrollSensitivity: props.number('scrollSensitivity'),
    smoothing: props.number('smoothing'),
  );
}

// --- Fly ---

/// Codec for [FlyCameraController], the WASD free-look camera.
class FlyCameraControllerCodec
    extends DeclarativeComponentCodec<FlyCameraController> {
  @override
  String get type => 'flyCameraController';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<FlyCameraController>> get fields => [
    ComponentField(
      ComponentPropertyDef(
        'position',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3(0.0, 2.0, 5.0)),
        doc: 'World-space eye position.',
      ),
      read: (c, _) => Vec3Value(c.position),
      write: (c, v, _) {
        if (v is Vec3Value) c.position = v.value;
      },
    ),
    _poseField(
      'yaw',
      defaultValue: 0.0,
      doc: 'Rotation around world up, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.yaw,
    ),
    _poseField(
      'pitch',
      defaultValue: 0.0,
      doc: 'Look elevation, in radians. Positive looks up.',
      constraints: const [AngleRadians()],
      get: (c) => c.pitch,
    ),
    ComponentField.number(
      'speed',
      defaultValue: 5.0,
      doc: 'Movement speed, in world units per second.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.speed,
      set: (c, v) => c.speed = v,
    ),
    ComponentField.number(
      'boostMultiplier',
      defaultValue: 4.0,
      doc: 'Speed multiplier while the boost key is held.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.boostMultiplier,
      set: (c, v) => c.boostMultiplier = v,
    ),
    ComponentField.number(
      'lookSensitivity',
      defaultValue: 0.005,
      doc: 'Radians of look per logical pixel of drag.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.lookSensitivity,
      set: (c, v) => c.lookSensitivity = v,
    ),
    ComponentField.number(
      'movementSmoothing',
      defaultValue: 0.0,
      doc: 'Seconds for movement to settle, separately from look.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.movementSmoothing,
      set: (c, v) => c.movementSmoothing = v,
    ),
    ComponentField.boolean(
      'moveVertical',
      defaultValue: true,
      doc: 'Whether the rise/fall keys are active.',
      get: (c) => c.moveVertical,
      set: (c, v) => c.moveVertical = v,
    ),
    ComponentField.number(
      'pitchLimit',
      defaultValue: 1.5,
      doc: 'Maximum absolute pitch, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.pitchLimit,
      set: (c, v) => c.pitchLimit = v,
    ),
    _smoothingField(0.0),
  ];

  @override
  FlyCameraController create(PropertyReader props) => FlyCameraController(
    position: props.vec3('position'),
    yaw: props.number('yaw'),
    pitch: props.number('pitch'),
    speed: props.number('speed'),
    boostMultiplier: props.number('boostMultiplier'),
    lookSensitivity: props.number('lookSensitivity'),
    movementSmoothing: props.number('movementSmoothing'),
    moveVertical: props.boolean('moveVertical'),
    pitchLimit: props.number('pitchLimit'),
    smoothing: props.number('smoothing'),
  );
}

// --- Follow ---

/// Codec for [FollowCameraController], the third-person chase camera.
class FollowCameraControllerCodec
    extends DeclarativeComponentCodec<FollowCameraController> {
  @override
  String get type => 'followCameraController';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<FollowCameraController>> get fields => [
    _followTargetField(
      (c) => c.followTarget,
      'The node to follow; absent parks the camera around the origin.',
    ),
    ComponentField.number(
      'distance',
      defaultValue: 9.0,
      doc: 'Resting distance behind the target.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.distance,
      set: (c, v) => c.distance = v,
    ),
    ComponentField.number(
      'lookHeight',
      defaultValue: 1.4,
      doc: 'Height above the target the camera aims at.',
      get: (c) => c.lookHeight,
      set: (c, v) => c.lookHeight = v,
    ),
    _poseField(
      'yaw',
      defaultValue: 0.0,
      doc: 'Rotation around the target, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.yaw,
    ),
    _poseField(
      'pitch',
      defaultValue: 0.42,
      doc: 'Elevation above the target, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.pitch,
    ),
    ComponentField.number(
      'minPitch',
      defaultValue: -0.15,
      doc: 'Lowest elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.minPitch,
      set: (c, v) => c.minPitch = v,
    ),
    ComponentField.number(
      'maxPitch',
      defaultValue: 1.3,
      doc: 'Highest elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.maxPitch,
      set: (c, v) => c.maxPitch = v,
    ),
    ComponentField.number(
      'minDistance',
      defaultValue: 0.5,
      doc: 'Closest the camera may dolly in.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.minDistance,
      set: (c, v) => c.minDistance = v,
    ),
    ComponentField.number(
      'maxDistance',
      defaultValue: 0.0,
      doc: 'Furthest the camera may dolly out, or 0 for no limit.',
      constraints: const [Range.nonNegative()],
      get: (c) => _encodeLimit(c.maxDistance),
      set: (c, v) => c.maxDistance = _decodeLimit(v),
    ),
    ComponentField.number(
      'rotateSpeed',
      defaultValue: math.pi,
      doc: 'Radians of rotation per full drag across the viewport.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.rotateSpeed,
      set: (c, v) => c.rotateSpeed = v,
    ),
    ComponentField.number(
      'dollySpeed',
      defaultValue: 0.15,
      doc: 'Dolly response per unit of scroll.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.dollySpeed,
      set: (c, v) => c.dollySpeed = v,
    ),
    ComponentField.number(
      'scrollSensitivity',
      defaultValue: 1 / 120,
      doc: 'Scroll notch to dolly amount.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.scrollSensitivity,
      set: (c, v) => c.scrollSensitivity = v,
    ),
    // The probe itself is code-provided; these tune whatever it reports.
    ComponentField.number(
      'occlusionPadding',
      defaultValue: 0.2,
      doc: 'How far off an obstruction the camera stops.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.occlusionPadding,
      set: (c, v) => c.occlusionPadding = v,
    ),
    ComponentField.number(
      'minOcclusionDistance',
      defaultValue: 0.6,
      doc: 'Closest the camera may retract to when obstructed.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.minOcclusionDistance,
      set: (c, v) => c.minOcclusionDistance = v,
    ),
    ComponentField.number(
      'occlusionRecoverySpeed',
      defaultValue: 12.0,
      doc: 'World units per second back to full distance once clear.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.occlusionRecoverySpeed,
      set: (c, v) => c.occlusionRecoverySpeed = v,
    ),
    _smoothingField(0.08),
  ];

  @override
  FollowCameraController create(PropertyReader props) {
    final controller = FollowCameraController(
      followTarget: _resolveNode(props, 'followTarget'),
      distance: props.number('distance'),
      lookHeight: props.number('lookHeight'),
      yaw: props.number('yaw'),
      pitch: props.number('pitch'),
      minPitch: props.number('minPitch'),
      maxPitch: props.number('maxPitch'),
      minDistance: props.number('minDistance'),
      maxDistance: _decodeLimit(props.number('maxDistance')),
      rotateSpeed: props.number('rotateSpeed'),
      dollySpeed: props.number('dollySpeed'),
      scrollSensitivity: props.number('scrollSensitivity'),
      smoothing: props.number('smoothing'),
    );
    // Field initializers rather than constructor parameters upstream.
    controller
      ..occlusionPadding = props.number('occlusionPadding')
      ..minOcclusionDistance = props.number('minOcclusionDistance')
      ..occlusionRecoverySpeed = props.number('occlusionRecoverySpeed');
    return controller;
  }
}

// --- First person ---

const _headBobFields = [
  ComponentPropertyDef(
    'amplitude',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.045),
    doc: 'Vertical displacement at full speed, in world units.',
  ),
  ComponentPropertyDef(
    'frequency',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(8.0),
    doc: 'Steps per second at full speed.',
  ),
  ComponentPropertyDef(
    'lateralRatio',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.6),
    doc: 'Sideways displacement as a fraction of the amplitude.',
  ),
  ComponentPropertyDef(
    'rollAmount',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.012),
    doc: 'Roll at the extremes of the sideways swing, in radians.',
  ),
];

HeadBob? _decodeHeadBob(PropertyValue? value) {
  if (value is! MapValue) return null;
  double read(String name, double fallback) => switch (value.values[name]) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => fallback,
  };
  return HeadBob(
    amplitude: read('amplitude', 0.045),
    frequency: read('frequency', 8.0),
    lateralRatio: read('lateralRatio', 0.6),
    rollAmount: read('rollAmount', 0.012),
  );
}

/// Codec for [FirstPersonCameraController], the eyes-of-the-character camera.
class FirstPersonCameraControllerCodec
    extends DeclarativeComponentCodec<FirstPersonCameraController> {
  @override
  String get type => 'firstPersonCameraController';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<FirstPersonCameraController>> get fields => [
    _followTargetField(
      (c) => c.followTarget,
      'The character whose head the camera rides.',
    ),
    ComponentField(
      ComponentPropertyDef(
        'eyeOffset',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3(0.0, 1.7, 0.0)),
        doc: 'Eye position relative to the followed node.',
      ),
      read: (c, _) => Vec3Value(c.eyeOffset),
      write: (c, v, _) {
        if (v is Vec3Value) c.eyeOffset = v.value.clone();
      },
    ),
    _vectorPoseField(
      'position',
      defaultValue: Vector3.zero(),
      doc: 'World-space eye position when there is no followed node.',
      get: (c) => c.position,
    ),
    _poseField(
      'yaw',
      defaultValue: 0.0,
      doc: 'Look rotation around world up, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.yaw,
    ),
    _poseField(
      'pitch',
      defaultValue: 0.0,
      doc: 'Look elevation, in radians. Positive looks up.',
      constraints: const [AngleRadians()],
      get: (c) => c.pitch,
    ),
    ComponentField.number(
      'lookSensitivity',
      defaultValue: 0.005,
      doc: 'Radians of look per logical pixel of drag.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.lookSensitivity,
      set: (c, v) => c.lookSensitivity = v,
    ),
    ComponentField.number(
      'minPitch',
      defaultValue: -1.55,
      doc: 'Lowest look elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.minPitch,
      set: (c, v) => c.minPitch = v,
    ),
    ComponentField.number(
      'maxPitch',
      defaultValue: 1.55,
      doc: 'Highest look elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.maxPitch,
      set: (c, v) => c.maxPitch = v,
    ),
    ComponentField.number(
      'positionSmoothing',
      defaultValue: 0.0,
      doc: 'Seconds for the eye to settle onto the followed node.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.positionSmoothing,
      set: (c, v) => c.positionSmoothing = v,
    ),
    ComponentField.number(
      'recoilRecovery',
      defaultValue: 0.35,
      doc: 'Seconds for additive recoil to decay away.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.recoilRecovery,
      set: (c, v) => c.recoilRecovery = v,
    ),
    ComponentField(
      const ComponentPropertyDef(
        'headBob',
        ComponentPropertyKind.object,
        objectFields: _headBobFields,
        doc: 'Walking head bob, or absent for none.',
      ),
      read: (c, _) {
        final bob = c.headBob;
        if (bob == null) return null;
        return MapValue({
          'amplitude': DoubleValue(bob.amplitude),
          'frequency': DoubleValue(bob.frequency),
          'lateralRatio': DoubleValue(bob.lateralRatio),
          'rollAmount': DoubleValue(bob.rollAmount),
        });
      },
      write: (c, v, _) => c.headBob = _decodeHeadBob(v),
    ),
    _lensField((c) => c.lens, (c, v) => c.lens = v),
    _smoothingField(0.0),
  ];

  @override
  FirstPersonCameraController create(PropertyReader props) =>
      FirstPersonCameraController(
        followTarget: _resolveNode(props, 'followTarget'),
        eyeOffset: props.vec3('eyeOffset'),
        position: props.vec3('position'),
        yaw: props.number('yaw'),
        pitch: props.number('pitch'),
        lookSensitivity: props.number('lookSensitivity'),
        minPitch: props.number('minPitch'),
        maxPitch: props.number('maxPitch'),
        headBob: _decodeHeadBob(props.value('headBob')),
        positionSmoothing: props.number('positionSmoothing'),
        recoilRecovery: props.number('recoilRecovery'),
        smoothing: props.number('smoothing'),
      );
}

// --- RTS ---

const _edgeScrollFields = [
  ComponentPropertyDef(
    'margin',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(24.0),
    doc: 'The band at each edge, in logical pixels, that scrolls.',
  ),
  ComponentPropertyDef(
    'speed',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1.0),
    doc: 'Scroll rate at the very edge, relative to the pan speed.',
  ),
];

const _boundsFields = [
  ComponentPropertyDef(
    'min',
    ComponentPropertyKind.vec3,
    doc: 'Low corner of the pannable region.',
  ),
  ComponentPropertyDef(
    'max',
    ComponentPropertyKind.vec3,
    doc: 'High corner of the pannable region.',
  ),
];

/// Codec for [RtsCameraController], the strategy-game camera.
class RtsCameraControllerCodec
    extends DeclarativeComponentCodec<RtsCameraController> {
  @override
  String get type => 'rtsCameraController';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<RtsCameraController>> get fields => [
    _vectorPoseField(
      'focus',
      defaultValue: Vector3.zero(),
      doc: 'The ground point the camera looks at.',
      get: (c) => c.focus,
    ),
    _poseField(
      'yaw',
      defaultValue: 0.0,
      doc: 'Rotation around the focus, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.yaw,
    ),
    _poseField(
      'pitch',
      defaultValue: 0.9,
      doc: 'Elevation above the ground, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.pitch,
    ),
    _poseField(
      'distance',
      defaultValue: 40.0,
      doc: 'Perspective distance from the focus.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.distance,
    ),
    _poseField(
      'viewHeight',
      defaultValue: 30.0,
      doc: 'Orthographic vertical extent, in world units.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.viewHeight,
    ),
    ComponentField.boolean(
      'orthographic',
      defaultValue: false,
      doc: 'Whether the rig sizes its view by height rather than distance.',
      get: (c) => c.orthographic,
      set: (c, v) => c.orthographic = v,
    ),
    ComponentField.number(
      'orthographicDepth',
      defaultValue: 1000.0,
      doc: 'Depth range of the orthographic lens.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.orthographicDepth,
      set: (c, v) => c.orthographicDepth = v,
    ),
    ComponentField.number(
      'minDistance',
      defaultValue: 5.0,
      doc: 'Closest the camera may zoom in.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.minDistance,
      set: (c, v) => c.minDistance = v,
    ),
    ComponentField.number(
      'maxDistance',
      defaultValue: 400.0,
      doc: 'Furthest the camera may zoom out.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.maxDistance,
      set: (c, v) => c.maxDistance = v,
    ),
    ComponentField.number(
      'minViewHeight',
      defaultValue: 4.0,
      doc: 'Smallest orthographic view height.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.minViewHeight,
      set: (c, v) => c.minViewHeight = v,
    ),
    ComponentField.number(
      'maxViewHeight',
      defaultValue: 400.0,
      doc: 'Largest orthographic view height.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.maxViewHeight,
      set: (c, v) => c.maxViewHeight = v,
    ),
    ComponentField.number(
      'minPitch',
      defaultValue: 0.2,
      doc: 'Shallowest elevation, in radians.',
      constraints: const [AngleRadians()],
      get: (c) => c.minPitch,
      set: (c, v) => c.minPitch = v,
    ),
    ComponentField.number(
      'maxPitch',
      defaultValue: math.pi / 2,
      doc: 'Steepest elevation, in radians. Straight down is the limit.',
      constraints: const [AngleRadians()],
      get: (c) => c.maxPitch,
      set: (c, v) => c.maxPitch = v,
    ),
    ComponentField.number(
      'rotateSpeed',
      defaultValue: math.pi,
      doc: 'Radians of rotation per full drag across the viewport.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.rotateSpeed,
      set: (c, v) => c.rotateSpeed = v,
    ),
    ComponentField.number(
      'pitchSpeed',
      defaultValue: math.pi / 2,
      doc: 'Radians of pitch per full drag across the viewport.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.pitchSpeed,
      set: (c, v) => c.pitchSpeed = v,
    ),
    ComponentField.number(
      'zoomSpeed',
      defaultValue: 0.2,
      doc: 'Zoom response per unit of scroll.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.zoomSpeed,
      set: (c, v) => c.zoomSpeed = v,
    ),
    ComponentField.number(
      'dragPanSpeed',
      defaultValue: 1.0,
      doc: 'Pan distance per drag, relative to the view size.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.dragPanSpeed,
      set: (c, v) => c.dragPanSpeed = v,
    ),
    ComponentField.number(
      'keyboardPanSpeed',
      defaultValue: 1.0,
      doc: 'Pan rate on the movement keys.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.keyboardPanSpeed,
      set: (c, v) => c.keyboardPanSpeed = v,
    ),
    ComponentField.number(
      'scrollSensitivity',
      defaultValue: 1 / 120,
      doc: 'Scroll notch to zoom amount.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.scrollSensitivity,
      set: (c, v) => c.scrollSensitivity = v,
    ),
    ComponentField(
      const ComponentPropertyDef(
        'edgeScroll',
        ComponentPropertyKind.object,
        objectFields: _edgeScrollFields,
        doc: 'Pan when the pointer nears a viewport edge, or absent for none.',
      ),
      read: (c, _) {
        final edge = c.edgeScroll;
        if (edge == null) return null;
        return MapValue({
          'margin': DoubleValue(edge.margin),
          'speed': DoubleValue(edge.speed),
        });
      },
      write: (c, v, _) => c.edgeScroll = _decodeEdgeScroll(v),
    ),
    ComponentField(
      const ComponentPropertyDef(
        'bounds',
        ComponentPropertyKind.object,
        objectFields: _boundsFields,
        doc: 'The region the focus may pan within, or absent for unbounded.',
      ),
      read: (c, _) {
        final bounds = c.bounds;
        if (bounds == null) return null;
        return MapValue({
          'min': Vec3Value(bounds.min.clone()),
          'max': Vec3Value(bounds.max.clone()),
        });
      },
      write: (c, v, _) => c.bounds = _decodeBounds(v),
    ),
    _smoothingField(0.12),
  ];

  @override
  RtsCameraController create(PropertyReader props) => RtsCameraController(
    focus: props.vec3('focus'),
    yaw: props.number('yaw'),
    pitch: props.number('pitch'),
    distance: props.number('distance'),
    viewHeight: props.number('viewHeight'),
    orthographic: props.boolean('orthographic'),
    orthographicDepth: props.number('orthographicDepth'),
    minDistance: props.number('minDistance'),
    maxDistance: props.number('maxDistance'),
    minViewHeight: props.number('minViewHeight'),
    maxViewHeight: props.number('maxViewHeight'),
    minPitch: props.number('minPitch'),
    maxPitch: props.number('maxPitch'),
    rotateSpeed: props.number('rotateSpeed'),
    pitchSpeed: props.number('pitchSpeed'),
    zoomSpeed: props.number('zoomSpeed'),
    dragPanSpeed: props.number('dragPanSpeed'),
    keyboardPanSpeed: props.number('keyboardPanSpeed'),
    scrollSensitivity: props.number('scrollSensitivity'),
    bounds: _decodeBounds(props.value('bounds')),
    edgeScroll: _decodeEdgeScroll(props.value('edgeScroll')),
    smoothing: props.number('smoothing'),
  );
}

EdgeScroll? _decodeEdgeScroll(PropertyValue? value) {
  if (value is! MapValue) return null;
  double read(String name, double fallback) => switch (value.values[name]) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => fallback,
  };
  return EdgeScroll(margin: read('margin', 24.0), speed: read('speed', 1.0));
}

Aabb3? _decodeBounds(PropertyValue? value) {
  if (value is! MapValue) return null;
  final min = value.values['min'];
  final max = value.values['max'];
  if (min is! Vec3Value || max is! Vec3Value) return null;
  return Aabb3.minMax(min.value.clone(), max.value.clone());
}

// --- Dolly ---

const _pathFields = [
  ComponentPropertyDef(
    'waypoints',
    ComponentPropertyKind.list,
    itemDef: ComponentPropertyDef('point', ComponentPropertyKind.vec3),
    doc: 'The control points the spline passes through (at least two).',
  ),
  ComponentPropertyDef(
    'closed',
    ComponentPropertyKind.boolean,
    defaultValue: BoolValue(false),
    doc: 'Whether the path loops back to its first waypoint.',
  ),
];

/// Codec for [DollyCameraController], the camera riding a [CameraPath].
class DollyCameraControllerCodec
    extends DeclarativeComponentCodec<DollyCameraController> {
  @override
  String get type => 'dollyCameraController';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<DollyCameraController>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'path',
        ComponentPropertyKind.object,
        objectFields: _pathFields,
        doc: 'The curve the camera travels along.',
      ),
      read: (c, _) => MapValue({
        'waypoints': ListValue([
          for (final point in c.path.waypoints) Vec3Value(point.clone()),
        ]),
        'closed': BoolValue(c.path.closed),
      }),
      write: (c, v, _) {
        final path = _decodePath(v);
        if (path != null) c.path = path;
      },
    ),
    ComponentField(
      const ComponentPropertyDef(
        'lookTarget',
        ComponentPropertyKind.nodeRef,
        doc: 'A node to keep in frame; takes precedence over the look point.',
      ),
      read: (c, _) => nodeRefOf(c.lookTarget),
    ),
    ComponentField(
      const ComponentPropertyDef(
        'lookPoint',
        ComponentPropertyKind.vec3,
        doc: 'A fixed point to keep in frame when there is no look target.',
      ),
      read: (c, _) {
        final point = c.lookPoint;
        return point == null ? null : Vec3Value(point);
      },
    ),
    ComponentField.number(
      'lookAhead',
      defaultValue: 2.0,
      doc: 'Distance further along the path the camera aims at.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.lookAhead,
      set: (c, v) => c.lookAhead = v,
    ),
    ComponentField.number(
      'speed',
      defaultValue: 4.0,
      doc: 'Travel speed, in world units per second.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.speed,
      set: (c, v) => c.speed = v,
    ),
    ComponentField.boolean(
      'loop',
      defaultValue: false,
      doc: 'Whether the shot restarts when it reaches the end.',
      get: (c) => c.loop,
      set: (c, v) => c.loop = v,
    ),
    ComponentField.boolean(
      'playing',
      defaultValue: true,
      doc: 'Whether the camera is currently travelling.',
      get: (c) => c.playing,
      set: (c, v) => c.playing = v,
    ),
    ComponentField(
      ComponentPropertyDef(
        'up',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3(0.0, 1.0, 0.0)),
        doc: 'The reference up for the camera\'s roll.',
      ),
      read: (c, _) => Vec3Value(c.up.clone()),
      write: (c, v, _) {
        if (v is Vec3Value) c.up = v.value.clone();
      },
    ),
    _lensField((c) => c.lens, (c, v) => c.lens = v),
    _smoothingField(0.0),
  ];

  @override
  DollyCameraController create(PropertyReader props) {
    final path = _decodePath(props.value('path'));
    if (path == null) {
      debugPrint(
        'fscene: dolly camera path missing or malformed (a path needs at '
        'least two waypoints); using a unit line',
      );
    }
    final lookPoint = props.value('lookPoint');
    return DollyCameraController(
      path: path ?? CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, -1.0)),
      lookTarget: _resolveNode(props, 'lookTarget'),
      lookPoint: lookPoint is Vec3Value ? lookPoint.value.clone() : null,
      lookAhead: props.number('lookAhead'),
      speed: props.number('speed'),
      loop: props.boolean('loop'),
      playing: props.boolean('playing'),
      up: props.vec3('up'),
      smoothing: props.number('smoothing'),
    );
  }
}

CameraPath? _decodePath(PropertyValue? value) {
  if (value is! MapValue) return null;
  final raw = value.values['waypoints'];
  if (raw is! ListValue) return null;
  final points = <Vector3>[
    for (final entry in raw.values)
      if (entry is Vec3Value) entry.value.clone(),
  ];
  if (points.length < 2) return null;
  final closed = value.values['closed'];
  return CameraPath(points, closed: closed is BoolValue && closed.value);
}

// --- Cinematics ---

/// The blend curves a document can name. Curves are functions, so they
/// travel as a name rather than as data; anything outside this set stays
/// code-provided and falls back to the default on load.
const _curveNames = <String>[
  'linear',
  'ease',
  'easeIn',
  'easeOut',
  'easeInOut',
  'easeInCubic',
  'easeOutCubic',
  'easeInOutCubic',
  'easeOutBack',
];

const _curvesByName = <String, Curve>{
  'linear': Curves.linear,
  'ease': Curves.ease,
  'easeIn': Curves.easeIn,
  'easeOut': Curves.easeOut,
  'easeInOut': Curves.easeInOut,
  'easeInCubic': Curves.easeInCubic,
  'easeOutCubic': Curves.easeOutCubic,
  'easeInOutCubic': Curves.easeInOutCubic,
  'easeOutBack': Curves.easeOutBack,
};

String _curveName(Curve curve) {
  for (final entry in _curvesByName.entries) {
    if (identical(entry.value, curve)) return entry.key;
  }
  return 'easeInOut';
}

const _blendFields = [
  ComponentPropertyDef(
    'duration',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.75),
    doc: 'Seconds the blend takes. Zero or less is a cut.',
  ),
  ComponentPropertyDef(
    'curve',
    ComponentPropertyKind.string,
    defaultValue: StringValue('easeInOut'),
    options: _curveNames,
    doc: 'Easing applied across the blend.',
  ),
];

MapValue _encodeBlend(CameraBlend blend) => MapValue({
  'duration': DoubleValue(blend.duration),
  'curve': StringValue(_curveName(blend.curve)),
});

CameraBlend? _decodeBlend(PropertyValue? value) {
  if (value is! MapValue) return null;
  final duration = switch (value.values['duration']) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => 0.75,
  };
  final name = switch (value.values['curve']) {
    StringValue(value: final v) => v,
    _ => 'easeInOut',
  };
  return CameraBlend(duration, curve: _curvesByName[name] ?? Curves.easeInOut);
}

const _shakeFields = [
  ComponentPropertyDef(
    'decayRate',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1.2),
    doc: 'Trauma bled off per second.',
  ),
  ComponentPropertyDef(
    'frequency',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(25.0),
    doc: 'Noise frequency; higher is a faster rattle.',
  ),
  ComponentPropertyDef(
    'maxTranslation',
    ComponentPropertyKind.vec3,
    doc: 'Displacement at full trauma, in local units.',
  ),
  ComponentPropertyDef(
    'maxRotation',
    ComponentPropertyKind.vec3,
    doc: 'Pitch/yaw/roll at full trauma, in radians.',
  ),
];

CameraShake? _decodeShake(PropertyValue? value) {
  if (value is! MapValue) return null;
  double read(String name, double fallback) => switch (value.values[name]) {
    DoubleValue(value: final v) => v,
    IntValue(value: final v) => v.toDouble(),
    _ => fallback,
  };
  Vector3 readVec(String name, Vector3 fallback) =>
      switch (value.values[name]) {
        Vec3Value(value: final v) => v.clone(),
        _ => fallback,
      };
  return CameraShake(
    decayRate: read('decayRate', 1.2),
    frequency: read('frequency', 25.0),
    maxTranslation: readVec('maxTranslation', Vector3(0.2, 0.2, 0.1)),
    maxRotation: readVec('maxRotation', Vector3(0.06, 0.06, 0.04)),
  );
}

/// Resolves the node a referenced controller lives on. Controllers are
/// components, and the document has no component reference, so a shot names
/// the node and the codec finds the controller on it — the same way a joint
/// names the node holding the body it attaches to.
T? _componentOn<T extends Component>(RealizeContext context, LocalId id) {
  final node = context.resolveNode?.call(id);
  return node?.getComponent<T>();
}

/// Codec for [CameraDirector]: the shot stack, its default blend, and its
/// shake layer.
///
/// The registered cameras are restored after every node exists, since a
/// director usually names cameras that are realized later in the document.
class CameraDirectorCodec extends DeclarativeComponentCodec<CameraDirector> {
  @override
  String get type => 'cameraDirector';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<CameraDirector>> get fields => [
    ComponentField(
      ComponentPropertyDef(
        'defaultBlend',
        ComponentPropertyKind.object,
        objectFields: _blendFields,
        // Declared so an untouched director serializes empty, like every
        // other component.
        defaultValue: _encodeBlend(_kDefaultBlend),
        doc: 'The blend used when the live camera changes on its own.',
      ),
      read: (c, _) => _encodeBlend(c.defaultBlend),
      write: (c, v, _) {
        final blend = _decodeBlend(v);
        if (blend != null) c.defaultBlend = blend;
      },
    ),
    ComponentField(
      const ComponentPropertyDef(
        'shake',
        ComponentPropertyKind.object,
        objectFields: _shakeFields,
        doc: 'Shake layered over the blended pose, or absent for none.',
      ),
      read: (c, _) {
        final shake = c.shake;
        if (shake == null) return null;
        // Trauma is live state, not configuration: a scene should not load
        // already shaking.
        return MapValue({
          'decayRate': DoubleValue(shake.decayRate),
          'frequency': DoubleValue(shake.frequency),
          'maxTranslation': Vec3Value(shake.maxTranslation.clone()),
          'maxRotation': Vec3Value(shake.maxRotation.clone()),
        });
      },
      write: (c, v, _) => c.shake = _decodeShake(v),
    ),
    ComponentField(
      const ComponentPropertyDef(
        'shots',
        ComponentPropertyKind.list,
        itemDef: ComponentPropertyDef(
          'shot',
          ComponentPropertyKind.object,
          objectFields: [
            ComponentPropertyDef(
              'node',
              ComponentPropertyKind.nodeRef,
              doc: 'The node carrying the camera controller.',
            ),
            ComponentPropertyDef(
              'priority',
              ComponentPropertyKind.number,
              defaultValue: DoubleValue(0),
              doc: 'Higher wins when no explicit blend is running.',
            ),
            ComponentPropertyDef(
              'name',
              ComponentPropertyKind.string,
              doc: 'An optional label for this shot.',
            ),
          ],
        ),
        doc: 'The cameras this director stacks, in registration order.',
      ),
      read: (c, _) {
        final entries = <PropertyValue>[];
        for (final shot in c.registrations) {
          final ref = shot.camera.isAttached
              ? nodeRefOf(shot.camera.node)
              : null;
          if (ref == null) {
            debugPrint(
              'fscene: cameraDirector shot skipped (its controller is not on '
              'a document node, so there is nothing to reference)',
            );
            continue;
          }
          entries.add(
            MapValue({
              'node': ref,
              'priority': DoubleValue(shot.priority),
              if (shot.name != null) 'name': StringValue(shot.name!),
            }),
          );
        }
        return entries.isEmpty ? null : ListValue(entries);
      },
    ),
  ];

  @override
  CameraDirector create(PropertyReader props) {
    final director = CameraDirector(
      defaultBlend: _decodeBlend(props.value('defaultBlend')) ?? _kDefaultBlend,
      shake: _decodeShake(props.value('shake')),
    );
    final raw = props.value('shots');
    if (raw is! ListValue) return director;
    final context = props.context;
    // Deferred: the cameras a director names are usually realized after it.
    context.afterRealize.add(() {
      for (final entry in raw.values) {
        if (entry is! MapValue) continue;
        final ref = entry.values['node'];
        if (ref is! NodeRefValue) continue;
        final camera = _componentOn<CameraController>(context, ref.id);
        if (camera == null) {
          debugPrint(
            'fscene: cameraDirector shot dropped (no camera controller on '
            'node ${ref.id})',
          );
          continue;
        }
        final priority = switch (entry.values['priority']) {
          DoubleValue(value: final v) => v,
          IntValue(value: final v) => v.toDouble(),
          _ => 0.0,
        };
        final name = switch (entry.values['name']) {
          StringValue(value: final v) => v,
          _ => null,
        };
        director.add(camera, priority: priority, name: name);
      }
    });
    return director;
  }
}

const _kDefaultBlend = CameraBlend(0.75);

/// Codec for [CameraSequence]: a shot list played through a director.
///
/// Both the director and each shot's camera are named by the node that
/// carries them, and both are resolved after the whole document is realized.
class CameraSequenceCodec extends DeclarativeComponentCodec<CameraSequence> {
  @override
  String get type => 'cameraSequence';

  @override
  String? get category => 'Cameras';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'camera',
    properties: propertySchema,
  );

  @override
  List<ComponentField<CameraSequence>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'director',
        ComponentPropertyKind.nodeRef,
        doc: 'The node carrying the director this sequence drives.',
      ),
      read: (c, _) => c.director.isAttached ? nodeRefOf(c.director.node) : null,
    ),
    ComponentField.boolean(
      'loop',
      defaultValue: false,
      doc: 'Whether the sequence restarts from the first shot when it ends.',
      get: (c) => c.loop,
      set: (c, v) => c.loop = v,
    ),
    ComponentField.boolean(
      'releaseOnComplete',
      defaultValue: true,
      doc: 'Whether finishing hands the camera back to priority.',
      get: (c) => c.releaseOnComplete,
      set: (c, v) => c.releaseOnComplete = v,
    ),
    ComponentField(
      const ComponentPropertyDef(
        'releaseBlend',
        ComponentPropertyKind.object,
        objectFields: _blendFields,
        doc: 'How to blend when handing back, or absent for the default.',
      ),
      read: (c, _) {
        final blend = c.releaseBlend;
        return blend == null ? null : _encodeBlend(blend);
      },
      write: (c, v, _) => c.releaseBlend = _decodeBlend(v),
    ),
    ComponentField(
      const ComponentPropertyDef(
        'shots',
        ComponentPropertyKind.list,
        itemDef: ComponentPropertyDef(
          'shot',
          ComponentPropertyKind.object,
          objectFields: [
            ComponentPropertyDef(
              'node',
              ComponentPropertyKind.nodeRef,
              doc: 'The node carrying the camera this shot shows.',
            ),
            ComponentPropertyDef(
              'hold',
              ComponentPropertyKind.number,
              defaultValue: DoubleValue(3.0),
              doc: 'Seconds on screen, measured from when its blend starts.',
            ),
            ComponentPropertyDef(
              'blendIn',
              ComponentPropertyKind.object,
              objectFields: _blendFields,
              doc: 'How to arrive, or absent for the director default.',
            ),
          ],
        ),
        doc: 'The cut list, in order.',
      ),
      read: (c, _) {
        final entries = <PropertyValue>[];
        for (final shot in c.shots) {
          final ref = shot.camera.isAttached
              ? nodeRefOf(shot.camera.node)
              : null;
          if (ref == null) {
            debugPrint(
              'fscene: cameraSequence shot skipped (its camera is not on a '
              'document node)',
            );
            continue;
          }
          final blendIn = shot.blendIn;
          entries.add(
            MapValue({
              'node': ref,
              'hold': DoubleValue(shot.hold),
              if (blendIn != null) 'blendIn': _encodeBlend(blendIn),
            }),
          );
        }
        return entries.isEmpty ? null : ListValue(entries);
      },
    ),
  ];

  @override
  CameraSequence create(PropertyReader props) {
    final context = props.context;
    // A sequence cannot exist without a director, and neither it nor the
    // cameras are realized yet, so build against a placeholder and fill both
    // in once the document is complete.
    final placeholder = CameraDirector();
    final sequence = CameraSequence(
      placeholder,
      loop: props.boolean('loop'),
      releaseOnComplete: props.boolean('releaseOnComplete'),
      releaseBlend: _decodeBlend(props.value('releaseBlend')),
    );
    final directorRef = props.value('director');
    final raw = props.value('shots');
    context.afterRealize.add(() {
      if (directorRef is NodeRefValue) {
        final director = _componentOn<CameraDirector>(context, directorRef.id);
        if (director == null) {
          debugPrint(
            'fscene: cameraSequence has no director on node '
            '${directorRef.id}; it will not play',
          );
        } else {
          sequence.director = director;
        }
      }
      if (raw is! ListValue) return;
      final shots = <CameraShot>[];
      for (final entry in raw.values) {
        if (entry is! MapValue) continue;
        final ref = entry.values['node'];
        if (ref is! NodeRefValue) continue;
        final camera = _componentOn<CameraController>(context, ref.id);
        if (camera == null) {
          debugPrint(
            'fscene: cameraSequence shot dropped (no camera controller on '
            'node ${ref.id})',
          );
          continue;
        }
        final hold = switch (entry.values['hold']) {
          DoubleValue(value: final v) => v,
          IntValue(value: final v) => v.toDouble(),
          _ => 3.0,
        };
        shots.add(
          CameraShot(
            camera,
            hold: hold <= 0 ? 3.0 : hold,
            blendIn: _decodeBlend(entry.values['blendIn']),
          ),
        );
      }
      if (shots.isNotEmpty) sequence.setShots(shots);
    });
    return sequence;
  }
}
