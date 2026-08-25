/// The animation authoring commands: creating and renaming animations, and
/// editing their keyframes.
///
/// An [AnimationSpec] drives channels; each channel carries one (target node,
/// property) pair and references two binary payloads: the keyframe times and
/// the keyframe values (float32s, one vec3 or quat per keyframe). Commands
/// never edit payloads or channel lists in place; they replace whole pool
/// entries through [PayloadChange] and [AnimationChange] records, so undo,
/// redo, and agent parity hold like any other edit.
library;

import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'change.dart';
import 'command.dart';
import 'params.dart';

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------

AnimationSpec _requireAnimation(CommandContext ctx, LocalId id) =>
    ctx.document.animations[id] ??
    (throw CommandException('Animation not found: ${id.toToken()}'));

LocalId _requireAnimationId(Map<String, Object?> params, String key) {
  final token = requireString(params, key);
  try {
    return LocalId.parse(token);
  } catch (_) {
    throw CommandException('Param $key is not a valid animation id: $token');
  }
}

AnimationProperty _requireProperty(Map<String, Object?> params) {
  final name = requireString(params, 'property');
  final property = AnimationProperty.values.where((p) => p.name == name);
  if (property.isEmpty) {
    throw CommandException(
      'Unknown animation property "$name" '
      '(translation, rotation, or scale)',
    );
  }
  return property.first;
}

/// The values-per-keyframe stride of [property] (morph-weight channels are
/// authored through imported models, not these commands).
int _strideOf(AnimationProperty property) =>
    property == AnimationProperty.rotation ? 4 : 3;

/// A channel's keyframes parsed out of the document's payloads: sorted times
/// and one fixed-stride value list per time.
class _KeyframeData {
  _KeyframeData(this.times, this.values);

  final List<double> times;
  final List<List<double>> values;
}

const double _timeEpsilon = 1e-4;

/// Reads [channel]'s keyframes from [document]. Returns empty data when the
/// payloads are missing, which authors as a fresh channel on next write.
_KeyframeData _readKeyframes(SceneDocument document, AnimationChannelSpec c) {
  final times = document.payload(c.timeline)?.bytes;
  final values = document.payload(c.keyframes)?.bytes;
  if (times == null || values == null) return _KeyframeData([], []);
  final stride = _strideOf(c.property);
  Float32List floats(Uint8List bytes) {
    if (bytes.offsetInBytes % 4 == 0) {
      return bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
    }
    return Uint8List.fromList(
      bytes,
    ).buffer.asFloat32List(0, bytes.lengthInBytes ~/ 4);
  }

  final timesIn = floats(times);
  final valuesIn = floats(values);
  return _KeyframeData(
    [for (var i = 0; i < timesIn.length; i++) timesIn[i]],
    [
      for (var i = 0; i * stride + stride <= valuesIn.length; i++)
        [for (var j = 0; j < stride; j++) valuesIn[i * stride + j]],
    ],
  );
}

/// Encodes [data] back into the two payload byte blobs.
(Uint8List, Uint8List) _encodeKeyframes(_KeyframeData data) {
  final stride = data.values.isEmpty ? 3 : data.values.first.length;
  final timesOut = Float32List(data.times.length);
  for (var i = 0; i < data.times.length; i++) {
    timesOut[i] = data.times[i];
  }
  final valuesOut = Float32List(data.values.length * stride);
  var o = 0;
  for (final value in data.values) {
    for (final component in value) {
      valuesOut[o++] = component;
    }
  }
  return (timesOut.buffer.asUint8List(), valuesOut.buffer.asUint8List());
}

/// The channel of [animation] driving [property] of [target], or null.
AnimationChannelSpec? _channelOf(
  AnimationSpec animation,
  LocalId target,
  AnimationProperty property,
) {
  for (final channel in animation.channels) {
    if (channel.target == target && channel.property == property) {
      return channel;
    }
  }
  return null;
}

/// The node's current local transform decomposed, so a keyframe can capture
/// the pose being edited without the caller passing values explicitly.
TrsTransform _currentTrs(NodeSpec node) {
  final transform = node.transform;
  if (transform is TrsTransform) return transform;
  final decomposition = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();
  transform.toMatrix4().decompose(decomposition, rotation, scale);
  return TrsTransform(
    translation: decomposition,
    rotation: rotation,
    scale: scale,
  );
}

/// Builds a [PayloadSpec] holding [bytes] as float32 data under [id].
PayloadSpec _floatsPayload(LocalId id, Uint8List bytes) => PayloadSpec(
  id,
  encoding: PayloadEncoding.floats,
  length: bytes.lengthInBytes,
  bytes: bytes,
);

/// Upserts [value] at [time] into [data], keeping times sorted. An existing
/// keyframe within [_timeEpsilon] of [time] is replaced.
void _upsert(_KeyframeData data, double time, List<double> value) {
  var index = data.times.indexWhere((t) => (t - time).abs() <= _timeEpsilon);
  if (index >= 0) {
    data.values[index] = value;
    return;
  }
  index = data.times.indexWhere((t) => t > time);
  if (index < 0) index = data.times.length;
  data.times.insert(index, time);
  data.values.insert(index, value);
}

/// Drops the keyframe nearest [time] (within [_timeEpsilon]); returns false
/// when none matches.
bool _removeAt(_KeyframeData data, double time) {
  final index = data.times.indexWhere((t) => (t - time).abs() <= _timeEpsilon);
  if (index < 0) return false;
  data.times.removeAt(index);
  data.values.removeAt(index);
  return true;
}

bool _payloadDiffers(PayloadSpec? payload, Uint8List bytes) {
  final existing = payload?.bytes;
  if (existing == null) return true;
  if (existing.lengthInBytes != bytes.lengthInBytes) return true;
  for (var i = 0; i < bytes.lengthInBytes; i++) {
    if (existing[i] != bytes[i]) return true;
  }
  return false;
}

/// Builds the change records rewriting [animation]'s channel for
/// (target, property) to carry [data], reusing the channel's payload ids when
/// it exists and minting fresh ones otherwise. Returns the records plus the
/// rewritten spec.
(List<ChangeRecord>, AnimationSpec) _writeChannel(
  CommandContext ctx,
  AnimationSpec animation,
  LocalId target,
  String? targetName,
  AnimationProperty property,
  _KeyframeData data,
) {
  final existing = _channelOf(animation, target, property);
  final (timesBytes, valuesBytes) = _encodeKeyframes(data);

  // Payload ids are minted up front; unused ones are simply never recorded
  // (an allocator mint costs nothing and keeps the flow branch-light).
  final spareTimelineId = ctx.document.newId();
  final spareKeyframesId = ctx.document.newId();
  final LocalId timelineId;
  final LocalId keyframesId;

  final records = <ChangeRecord>[];
  if (existing == null) {
    timelineId = spareTimelineId;
    keyframesId = spareKeyframesId;
    records.addAll([
      ChangeRecord(
        targetId: timelineId,
        slot: ChangeSlot.poolPayload,
        oldValue: const PayloadChange(null),
        newValue: PayloadChange(_floatsPayload(timelineId, timesBytes)),
      ),
      ChangeRecord(
        targetId: keyframesId,
        slot: ChangeSlot.poolPayload,
        oldValue: const PayloadChange(null),
        newValue: PayloadChange(_floatsPayload(keyframesId, valuesBytes)),
      ),
    ]);
  } else {
    timelineId = existing.timeline;
    keyframesId = existing.keyframes;
    if (_payloadDiffers(ctx.document.payload(timelineId), timesBytes)) {
      records.add(
        ChangeRecord(
          targetId: timelineId,
          slot: ChangeSlot.poolPayload,
          oldValue: PayloadChange(ctx.document.payload(timelineId)),
          newValue: PayloadChange(_floatsPayload(timelineId, timesBytes)),
        ),
      );
    }
    if (_payloadDiffers(ctx.document.payload(keyframesId), valuesBytes)) {
      records.add(
        ChangeRecord(
          targetId: keyframesId,
          slot: ChangeSlot.poolPayload,
          oldValue: PayloadChange(ctx.document.payload(keyframesId)),
          newValue: PayloadChange(_floatsPayload(keyframesId, valuesBytes)),
        ),
      );
    }
  }

  final channels = [
    for (final c in animation.channels)
      if (c.target != target || c.property != property) c,
    AnimationChannelSpec(
      target: target,
      targetName: targetName,
      property: property,
      timeline: timelineId,
      keyframes: keyframesId,
    ),
  ];
  final updated = AnimationSpec(animation.id, name: animation.name)
    ..channels.addAll(channels);
  records.add(
    ChangeRecord(
      targetId: animation.id,
      slot: ChangeSlot.poolAnimation,
      oldValue: AnimationChange(animation),
      newValue: AnimationChange(updated),
    ),
  );
  return (records, updated);
}

/// The records dropping [animation]'s pool entry along with every payload its
/// channels reference (each channel owns its payloads exclusively).
List<ChangeRecord> _removalRecords(
  SceneDocument document,
  AnimationSpec animation,
) {
  final records = [
    ChangeRecord(
      targetId: animation.id,
      slot: ChangeSlot.poolAnimation,
      oldValue: AnimationChange(animation),
      newValue: const AnimationChange(null),
    ),
  ];
  final dropped = <LocalId>{};
  for (final channel in animation.channels) {
    for (final id in [channel.timeline, channel.keyframes]) {
      if (!dropped.add(id)) continue;
      records.add(
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolPayload,
          oldValue: PayloadChange(document.payload(id)),
          newValue: const PayloadChange(null),
        ),
      );
    }
  }
  return records;
}

/// The records dropping one emptied channel of [animation] (its exclusive
/// payloads go with it). Returns null when it was the animation's only
/// channel, in which case the whole animation goes.
List<ChangeRecord>? _pruneChannelRecords(
  SceneDocument document,
  AnimationSpec animation,
  AnimationChannelSpec channel,
) {
  if (animation.channels.length > 1) {
    final updated = AnimationSpec(animation.id, name: animation.name)
      ..channels.addAll([
        for (final c in animation.channels)
          if (c.target != channel.target || c.property != channel.property) c,
      ]);
    return [
      ChangeRecord(
        targetId: animation.id,
        slot: ChangeSlot.poolAnimation,
        oldValue: AnimationChange(animation),
        newValue: AnimationChange(updated),
      ),
    ];
  }
  return null;
}

// ---------------------------------------------------------------------------
// Commands.
// ---------------------------------------------------------------------------

final createAnimation = CommandEntry(
  name: 'createAnimation',
  doc: 'Create an empty animation.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'name',
      type: ParamType.string,
      label: 'Name',
      required: false,
      defaultValue: 'Animation',
    ),
  ],
  execute: (ctx, params) {
    final id = ctx.document.newId();
    final spec = AnimationSpec(
      id,
      name: optionalString(params, 'name') ?? 'Animation',
    );
    return Transaction(
      name: 'Create animation',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolAnimation,
          oldValue: const AnimationChange(null),
          newValue: AnimationChange(spec),
        ),
      ],
    );
  },
);

final deleteAnimation = CommandEntry(
  name: 'deleteAnimation',
  doc: 'Delete an animation and its keyframe payloads.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
  ],
  execute: (ctx, params) {
    final id = _requireAnimationId(params, 'animationId');
    final animation = _requireAnimation(ctx, id);
    return Transaction(
      name: 'Delete animation',
      records: _removalRecords(ctx.document, animation),
    );
  },
);

final renameAnimation = CommandEntry(
  name: 'renameAnimation',
  doc: 'Rename an animation.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'name', type: ParamType.string, label: 'Name'),
  ],
  execute: (ctx, params) {
    final id = _requireAnimationId(params, 'animationId');
    final animation = _requireAnimation(ctx, id);
    final updated = AnimationSpec(id, name: requireString(params, 'name'))
      ..channels.addAll(animation.channels);
    return Transaction(
      name: 'Rename animation',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolAnimation,
          oldValue: AnimationChange(animation),
          newValue: AnimationChange(updated),
        ),
      ],
    );
  },
);

final setAnimationKeyframe = CommandEntry(
  name: 'setAnimationKeyframe',
  doc:
      'Add or update one keyframe of an animation channel. Omitted value '
      'components capture the target node\'s current transform. Rotation '
      'accepts a "rotation" quaternion or a "rotationEuler" '
      '{yaw, pitch, roll} object in degrees.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'property', type: ParamType.string, label: 'Property'),
    ParamSpec(name: 'time', type: ParamType.number, label: 'Time'),
    ParamSpec(
      name: 'translation',
      type: ParamType.vec3,
      label: 'Translation',
      required: false,
    ),
    ParamSpec(
      name: 'rotation',
      type: ParamType.quaternion,
      label: 'Rotation',
      required: false,
    ),
    ParamSpec(
      name: 'rotationEuler',
      type: ParamType.euler,
      label: 'Rotation (Euler)',
      required: false,
      description:
          'Rotation as {yaw, pitch, roll} in DEGREES (yaw around Y, pitch '
          'around X, roll around Z). Pass either this or "rotation", not '
          'both.',
    ),
    ParamSpec(
      name: 'scale',
      type: ParamType.vec3,
      label: 'Scale',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final animation = _requireAnimation(
      ctx,
      _requireAnimationId(params, 'animationId'),
    );
    final nodeId = requireNodeId(params, 'nodeId');
    final node =
        ctx.document.node(nodeId) ??
        (throw CommandException('Node not found: ${nodeId.toToken()}'));
    final property = _requireProperty(params);
    if (property == AnimationProperty.weights) {
      throw CommandException('Morph-weight keyframes are not authorable here');
    }
    final time = requireDouble(params, 'time');
    if (time.isNegative || time.isNaN) {
      throw CommandException('Keyframe time must be a non-negative number');
    }

    // An omitted component captures the pose currently on the node.
    final value = _keyValue(params, property, _currentTrs(node));

    final channel = _channelOf(animation, nodeId, property);
    final data = channel == null
        ? _KeyframeData([], [])
        : _readKeyframes(ctx.document, channel);
    _upsert(data, time, value);
    final (records, _) = _writeChannel(
      ctx,
      animation,
      nodeId,
      node.name,
      property,
      data,
    );
    return Transaction(name: 'Set keyframe', records: records);
  },
);

/// Resolves one keyframe's stored value from its param map: the explicitly
/// given components (quaternion or Euler degrees for rotation), falling back
/// to the captured [trs] pose per component.
List<double> _keyValue(
  Map<String, Object?> key,
  AnimationProperty property,
  TrsTransform trs,
) {
  if (property == AnimationProperty.weights) {
    throw CommandException('Morph-weight keyframes are not authorable here');
  }
  final quaternion = optionalQuaternion(key, 'rotation');
  final euler = optionalEuler(key, 'rotationEuler');
  if (quaternion != null && euler != null) {
    throw const CommandException(
      'Pass either "rotation" or "rotationEuler", not both',
    );
  }
  return switch (property) {
    AnimationProperty.translation => [
      ...(optionalVec3(key, 'translation') ?? trs.translation).storage,
    ],
    AnimationProperty.rotation => [
      ...((quaternion ?? euler) ?? trs.rotation).storage,
    ],
    AnimationProperty.scale => [
      ...(optionalVec3(key, 'scale') ?? trs.scale).storage,
    ],
    AnimationProperty.weights => const [],
  };
}

final setAnimationKeyframes = CommandEntry(
  name: 'setAnimationKeyframes',
  doc:
      'Add or update several keyframes of one animation channel in a single '
      'undoable step. Each entry of "keys" carries a "time" plus optional '
      '"translation", "rotation" ({x, y, z, w}), "rotationEuler" '
      '({yaw, pitch, roll} degrees), or "scale"; omitted components capture '
      'the target node\'s current transform.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'property', type: ParamType.string, label: 'Property'),
    ParamSpec(
      name: 'keys',
      type: ParamType.objectList,
      label: 'Keys',
      description:
          'One {time, translation?, rotation?, rotationEuler?, scale?} '
          'object per keyframe; times need not be sorted.',
    ),
  ],
  execute: (ctx, params) {
    final animation = _requireAnimation(
      ctx,
      _requireAnimationId(params, 'animationId'),
    );
    final nodeId = requireNodeId(params, 'nodeId');
    final node =
        ctx.document.node(nodeId) ??
        (throw CommandException('Node not found: ${nodeId.toToken()}'));
    final property = _requireProperty(params);
    final keysParam = params['keys'];
    if (keysParam is! List || keysParam.isEmpty) {
      throw const CommandException(
        '"keys" must be a non-empty list of keyframe objects',
      );
    }
    final trs = _currentTrs(node);

    final channel = _channelOf(animation, nodeId, property);
    final data = channel == null
        ? _KeyframeData([], [])
        : _readKeyframes(ctx.document, channel);
    for (final entry in keysParam) {
      if (entry is! Map) {
        throw const CommandException('Every key must be an object');
      }
      final key = Map<String, Object?>.from(entry);
      final time = requireDouble(key, 'time');
      if (time.isNegative || time.isNaN) {
        throw CommandException('Keyframe time must be a non-negative number');
      }
      _upsert(data, time, _keyValue(key, property, trs));
    }
    final (records, _) = _writeChannel(
      ctx,
      animation,
      nodeId,
      node.name,
      property,
      data,
    );
    return Transaction(name: 'Set keyframes', records: records);
  },
);

final removeAnimationKeyframe = CommandEntry(
  name: 'removeAnimationKeyframe',
  doc:
      'Remove the keyframe at (or nearest) [time] from an animation channel. '
      'Removing a channel\'s last keyframe removes the channel.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'property', type: ParamType.string, label: 'Property'),
    ParamSpec(name: 'time', type: ParamType.number, label: 'Time'),
  ],
  execute: (ctx, params) {
    final document = ctx.document;
    final animation = _requireAnimation(
      ctx,
      _requireAnimationId(params, 'animationId'),
    );
    final nodeId = requireNodeId(params, 'nodeId');
    final property = _requireProperty(params);
    final time = requireDouble(params, 'time');
    final channel =
        _channelOf(animation, nodeId, property) ??
        (throw CommandException(
          'No ${property.name} channel on ${nodeId.toToken()}',
        ));
    final data = _readKeyframes(document, channel);
    if (!_removeAt(data, time)) {
      throw CommandException('No keyframe at $time s');
    }
    if (data.times.isEmpty) {
      return Transaction(
        name: 'Remove keyframe',
        records:
            _pruneChannelRecords(document, animation, channel) ??
            _removalRecords(document, animation),
      );
    }
    final (records, _) = _writeChannel(
      ctx,
      animation,
      nodeId,
      channel.targetName,
      property,
      data,
    );
    return Transaction(name: 'Remove keyframe', records: records);
  },
);

final moveAnimationKeyframe = CommandEntry(
  name: 'moveAnimationKeyframe',
  doc: 'Move one keyframe of an animation channel to a new time.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Node'),
    ParamSpec(name: 'property', type: ParamType.string, label: 'Property'),
    ParamSpec(name: 'fromTime', type: ParamType.number, label: 'From'),
    ParamSpec(name: 'toTime', type: ParamType.number, label: 'To'),
  ],
  execute: (ctx, params) {
    final animation = _requireAnimation(
      ctx,
      _requireAnimationId(params, 'animationId'),
    );
    final nodeId = requireNodeId(params, 'nodeId');
    final property = _requireProperty(params);
    final fromTime = requireDouble(params, 'fromTime');
    final toTime = requireDouble(params, 'toTime');
    if (toTime.isNegative || toTime.isNaN) {
      throw CommandException('Keyframe time must be a non-negative number');
    }
    final channel =
        _channelOf(animation, nodeId, property) ??
        (throw CommandException(
          'No ${property.name} channel on ${nodeId.toToken()}',
        ));
    final data = _readKeyframes(ctx.document, channel);
    final index = data.times.indexWhere(
      (t) => (t - fromTime).abs() <= _timeEpsilon,
    );
    if (index < 0) {
      throw CommandException('No keyframe at $fromTime s');
    }
    final value = data.values[index];
    _removeAt(data, fromTime);
    _upsert(data, toTime, value);
    final (records, _) = _writeChannel(
      ctx,
      animation,
      nodeId,
      channel.targetName,
      property,
      data,
    );
    return Transaction(name: 'Move keyframe', records: records);
  },
);

/// The animation authoring commands.
final List<CommandEntry> animationCommands = [
  createAnimation,
  deleteAnimation,
  renameAnimation,
  setAnimationKeyframe,
  setAnimationKeyframes,
  removeAnimationKeyframe,
  moveAnimationKeyframe,
];
