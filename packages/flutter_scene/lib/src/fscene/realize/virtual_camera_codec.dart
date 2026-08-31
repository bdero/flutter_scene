/// The codec for [VirtualCamera]: a shot that can be authored rather than only
/// assembled in code.
///
/// A virtual camera is two polymorphic parts — a [CameraBody] and a
/// [CameraAim] — and the document form follows that shape rather than
/// flattening it. Each is a tagged union, so the inspector shows a kind
/// picker and only the fields that kind actually has, and a saved document
/// carries only the chosen variant's values. Flat `bodyRadius` /
/// `bodyDeadZone` columns would have needed every field of every kind
/// declared at once, most of them meaningless at any given moment.
///
/// One consequence worth knowing: switching kind in the inspector replaces
/// the variant's contents, so the previous kind's tuning is not kept
/// underneath. That matches what the document holds — there is nowhere to
/// keep it — and it is why the defaults for each kind are chosen to be usable
/// as they land.
library;

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/virtual_camera.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/fscene/realize/property_map.dart';
import 'package:flutter_scene/src/fscene/realize/ref_read.dart';
import 'package:flutter_scene/src/node.dart';

// --- Body <-> property value ---

/// Damping, everywhere it appears, is seconds-to-settle per axis.
const _dampingDoc =
    'Seconds to close the remaining distance, per world axis. Zero snaps. '
    'Damping the axes differently is what lets a camera keep its distance '
    'while it catches up sideways.';

final Map<String, List<ComponentPropertyDef>> _bodyVariants = {
  'transposer': [
    ComponentPropertyDef(
      'offset',
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(Vector3(0, 2, -6)),
      doc: 'Where the camera sits relative to the target.',
    ),
    const ComponentPropertyDef(
      'binding',
      ComponentPropertyKind.string,
      defaultValue: StringValue('lockToTargetWithWorldUp'),
      options: ['worldSpace', 'lockToTargetWithWorldUp', 'lockToTarget'],
      doc:
          'Which axes the offset is measured in. World space keeps the '
          'camera\'s bearing while the target turns; locking with world up is '
          'the usual third-person follow; locking outright rolls with the '
          'target.',
    ),
    ComponentPropertyDef(
      'damping',
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(Vector3.all(0.3)),
      doc: _dampingDoc,
      constraints: const [Range.nonNegative()],
    ),
  ],
  'framingTransposer': [
    const ComponentPropertyDef(
      'distance',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(8),
      doc: 'How far behind the target the camera sits.',
      constraints: [Range.nonNegative(), SoftRange(1, 30)],
    ),
    const ComponentPropertyDef(
      'height',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(2),
      doc: 'How far above the target it sits.',
    ),
    const ComponentPropertyDef(
      'deadZone',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(0.6),
      doc:
          'How far the target may move, in world units, before the camera '
          'follows at all. This is what stops the shot answering every twitch.',
      constraints: [Range.nonNegative(), SoftRange(0, 5)],
    ),
    ComponentPropertyDef(
      'damping',
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(Vector3.all(0.4)),
      doc: _dampingDoc,
      constraints: const [Range.nonNegative()],
    ),
  ],
  'orbital': [
    const ComponentPropertyDef(
      'radius',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(6),
      doc: 'How far out the camera orbits.',
      constraints: [Range.nonNegative(), SoftRange(1, 30)],
    ),
    const ComponentPropertyDef(
      'height',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(2),
      doc: 'How far above the target it rides.',
    ),
    const ComponentPropertyDef(
      'heading',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(0),
      doc:
          'Where on the orbit it starts, in radians about world up. Gameplay '
          'drives this afterwards.',
      constraints: [AngleRadians()],
    ),
    ComponentPropertyDef(
      'damping',
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(Vector3.all(0.25)),
      doc: _dampingDoc,
      constraints: const [Range.nonNegative()],
    ),
  ],
};

/// Encodes [body] as a tagged map keyed on its kind.
MapValue encodeCameraBody(CameraBody body) => switch (body) {
  FramingTransposerBody() => MapValue({
    'kind': const StringValue('framingTransposer'),
    'distance': DoubleValue(body.distance),
    'height': DoubleValue(body.height),
    'deadZone': DoubleValue(body.deadZone),
    'damping': Vec3Value(body.damping.clone()),
  }),
  OrbitalBody() => MapValue({
    'kind': const StringValue('orbital'),
    'radius': DoubleValue(body.radius),
    'height': DoubleValue(body.height),
    'heading': DoubleValue(body.heading),
    'damping': Vec3Value(body.damping.clone()),
  }),
  TransposerBody() => MapValue({
    'kind': const StringValue('transposer'),
    'offset': Vec3Value(body.offset.clone()),
    'binding': StringValue(body.binding.name),
    'damping': Vec3Value(body.damping.clone()),
  }),
  // A body written in game code has no document form. Saying so as the
  // default transposer is better than writing a kind nothing can read back.
  _ => MapValue({
    'kind': const StringValue('transposer'),
    'offset': Vec3Value(Vector3(0, 2, -6)),
    'binding': const StringValue('lockToTargetWithWorldUp'),
    'damping': Vec3Value(Vector3.all(0.3)),
  }),
};

/// Decodes a [CameraBody] from [value]; anything unrecognized is a transposer,
/// which is the body most shots want.
CameraBody decodeCameraBody(PropertyValue? value) {
  final map = propertyMapOf(value);
  return switch (map.stringAt('kind', 'transposer')) {
    'framingTransposer' => FramingTransposerBody(
      distance: map.numberAt('distance', 8),
      height: map.numberAt('height', 2),
      deadZone: map.numberAt('deadZone', 0.6),
      damping: map.vec3At('damping', Vector3.all(0.4)),
    ),
    'orbital' => OrbitalBody(
      radius: map.numberAt('radius', 6),
      height: map.numberAt('height', 2),
      heading: map.numberAt('heading', 0),
      damping: map.vec3At('damping', Vector3.all(0.25)),
    ),
    _ => TransposerBody(
      offset: map.vec3At('offset', Vector3(0, 2, -6)),
      binding: _binding(map.stringAt('binding', '')),
      damping: map.vec3At('damping', Vector3.all(0.3)),
    ),
  };
}

CameraBinding _binding(String name) {
  for (final value in CameraBinding.values) {
    if (value.name == name) return value;
  }
  return CameraBinding.lockToTargetWithWorldUp;
}

// --- Aim <-> property value ---

final Map<String, List<ComponentPropertyDef>> _aimVariants = {
  'hardLookAt': const <ComponentPropertyDef>[],
  'composer': const [
    ComponentPropertyDef(
      'deadZoneDegrees',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(4),
      doc:
          'How far off centre, in degrees, the target may drift before the '
          'camera turns at all.',
      constraints: [Range.nonNegative(), SoftRange(0, 45)],
    ),
    ComponentPropertyDef(
      'damping',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(0.35),
      doc: 'Seconds to bring the target back once it is outside.',
      constraints: [Range.nonNegative(), SoftRange(0, 2)],
    ),
  ],
  'fixed': [
    ComponentPropertyDef(
      'rotation',
      ComponentPropertyKind.vec4,
      defaultValue: Vec4Value(Vector4(0, 0, 0, 1)),
      doc: 'The orientation held every frame, as a quaternion (x, y, z, w).',
    ),
  ],
};

/// Encodes [aim] as a tagged map keyed on its kind.
MapValue encodeCameraAim(CameraAim aim) => switch (aim) {
  ComposerAim() => MapValue({
    'kind': const StringValue('composer'),
    'deadZoneDegrees': DoubleValue(aim.deadZoneDegrees),
    'damping': DoubleValue(aim.damping),
  }),
  FixedAim() => MapValue({
    'kind': const StringValue('fixed'),
    'rotation': Vec4Value(
      Vector4(aim.rotation.x, aim.rotation.y, aim.rotation.z, aim.rotation.w),
    ),
  }),
  // Hard look-at has nothing to tune, and so does a code-provided aim.
  _ => MapValue({'kind': const StringValue('hardLookAt')}),
};

/// Decodes a [CameraAim] from [value]; anything unrecognized is a hard
/// look-at.
CameraAim decodeCameraAim(PropertyValue? value) {
  final map = propertyMapOf(value);
  return switch (map.stringAt('kind', 'hardLookAt')) {
    'composer' => ComposerAim(
      deadZoneDegrees: map.numberAt('deadZoneDegrees', 4),
      damping: map.numberAt('damping', 0.35),
    ),
    'fixed' => FixedAim(
      rotation: map.quaternionAt('rotation', Quaternion.identity()),
    ),
    _ => HardLookAtAim(),
  };
}

// --- The codec ---

/// Codec for [VirtualCamera], the authorable shot.
class VirtualCameraCodec extends DeclarativeComponentCodec<VirtualCamera> {
  @override
  String get type => 'virtualCamera';

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
  List<ComponentField<VirtualCamera>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'follow',
        ComponentPropertyKind.nodeRef,
        doc:
            'The node the body positions against. Absent leaves the camera '
            'wherever it last was.',
      ),
      read: (c, _) => nodeRefOf(c.follow),
    ),
    ComponentField(
      const ComponentPropertyDef(
        'lookAt',
        ComponentPropertyKind.nodeRef,
        doc:
            'The node the aim points at, usually the same node as follow. '
            'Absent holds the current rotation.',
      ),
      read: (c, _) => nodeRefOf(c.lookAt),
    ),
    ComponentField.number(
      'priority',
      defaultValue: 0.0,
      doc:
          'What the director sorts by; the highest goes live. Raising a '
          'camera\'s own priority is how a shot takes over.',
      constraints: const [SoftRange(-10, 20)],
      get: (c) => c.priority,
      set: (c, v) => c.priority = v,
    ),
    ComponentField(
      ComponentPropertyDef(
        'body',
        ComponentPropertyKind.union,
        defaultValue: encodeCameraBody(TransposerBody()),
        doc: 'Where the camera stands.',
        unionVariants: _bodyVariants,
      ),
      read: (c, _) => encodeCameraBody(c.body),
      write: (c, v, _) => c.body = decodeCameraBody(v),
    ),
    ComponentField(
      ComponentPropertyDef(
        'aim',
        ComponentPropertyKind.union,
        defaultValue: encodeCameraAim(HardLookAtAim()),
        doc: 'Where the camera points.',
        unionVariants: _aimVariants,
      ),
      read: (c, _) => encodeCameraAim(c.aim),
      write: (c, v, _) => c.aim = decodeCameraAim(v),
    ),
    ComponentField.number(
      'smoothing',
      defaultValue: 0.0,
      doc:
          'Extra settle time applied to the finished pose, on top of the '
          'body\'s own damping. Usually zero: damp the body instead, so the '
          'aim is not smoothed twice.',
      constraints: const [Range.nonNegative(), SoftRange(0, 1)],
      get: (c) => c.smoothing,
      set: (c, v) => c.smoothing = v,
    ),
  ];

  @override
  VirtualCamera create(PropertyReader props) => VirtualCamera(
    follow: _resolveNode(props, 'follow'),
    lookAt: _resolveNode(props, 'lookAt'),
    body: decodeCameraBody(props.value('body')),
    aim: decodeCameraAim(props.value('aim')),
    priority: props.number('priority'),
    smoothing: props.number('smoothing'),
  );
}

Node? _resolveNode(PropertyReader props, String name) {
  final id = props.nodeId(name);
  if (id == null) return null;
  return props.context.resolveNode?.call(id);
}
