/// Commands for authoring a document's animations.
///
/// An [AnimationSpec] is a list of channels, each pairing a target node and a
/// property with two float payloads: the keyframe times and the keyframe
/// values. Every edit here rewrites those payloads (and, where the channel
/// list itself changes, the animation entry), so retiming a key, editing its
/// value, and adding or removing keys are all ordinary change records and
/// undo comes for free.
///
/// Payload sharing is the one wrinkle. A glTF import can point several
/// channels at one sampler input, so a payload about to be rewritten is
/// cloned first whenever anything else still references it; the channel then
/// points at the clone and the original is left untouched for its other
/// readers.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scene/scene.dart' hide NodeChange;

import 'change.dart';
import 'command.dart';
import 'params.dart';

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------

AnimationSpec _requireAnimation(CommandContext ctx, LocalId id) =>
    ctx.document.animations[id] ??
    (throw CommandException('Animation not found: ${id.toToken()}'));

AnimationChannelSpec _requireChannel(AnimationSpec animation, int index) {
  if (index < 0 || index >= animation.channels.length) {
    throw CommandException(
      'Channel $index is out of range for animation "${animation.name}", '
      'which has ${animation.channels.length}',
    );
  }
  return animation.channels[index];
}

/// The floats of payload [id], or an empty list when it is absent or holds no
/// bytes. A copy, so callers can edit it freely.
Float32List _floats(SceneDocument document, LocalId id) {
  final bytes = document.payload(id)?.bytes;
  if (bytes == null || bytes.lengthInBytes < 4) return Float32List(0);
  final view = Float32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
  return Float32List.fromList(view);
}

/// How many floats one keyframe of [property] occupies.
///
/// Fixed for the transform channels. A `weights` channel carries one weight
/// per morph target, so its stride is only knowable from the data: the value
/// count divided by the key count.
int _componentsPerKey(
  AnimationProperty property,
  int keyCount,
  int valueCount,
) => switch (property) {
  AnimationProperty.translation || AnimationProperty.scale => 3,
  AnimationProperty.rotation => 4,
  AnimationProperty.weights => keyCount == 0 ? 0 : valueCount ~/ keyCount,
};

/// Whether anything other than [channel]'s [timeline]-or-[keyframes] slot
/// still points at payload [id].
///
/// A shared payload cannot be rewritten in place: a glTF import can hand
/// several channels the same sampler input, and skins and geometry hold
/// payloads too.
bool _isShared(
  SceneDocument document,
  LocalId payloadId,
  AnimationSpec animation,
  int channelIndex,
  bool isTimeline,
) {
  var uses = 0;
  for (final spec in document.animations.values) {
    for (var i = 0; i < spec.channels.length; i++) {
      final channel = spec.channels[i];
      final self =
          spec.id == animation.id &&
          i == channelIndex &&
          (isTimeline ? channel.timeline : channel.keyframes) == payloadId;
      if (channel.timeline == payloadId && !(self && isTimeline)) uses++;
      if (channel.keyframes == payloadId && !(self && !isTimeline)) uses++;
    }
  }
  if (uses > 0) return true;
  for (final skin in document.skins.values) {
    if (skin.inverseBindMatrices == payloadId) return true;
  }
  return false;
}

/// A payload rewrite plus, when the payload had to be cloned to avoid
/// disturbing another reader, the id the channel should point at instead.
typedef _PayloadWrite = ({LocalId id, ChangeRecord record});

_PayloadWrite _writeFloats(
  CommandContext ctx,
  LocalId payloadId,
  Float32List values, {
  required bool clone,
}) {
  final id = clone ? ctx.document.newId() : payloadId;
  return (
    id: id,
    record: ChangeRecord(
      targetId: id,
      slot: ChangeSlot.poolPayload,
      oldValue: PayloadChange(clone ? null : ctx.document.payload(payloadId)),
      newValue: PayloadChange(
        PayloadSpec(
          id,
          encoding: PayloadEncoding.floats,
          length: values.length,
          bytes: Uint8List.view(
            values.buffer,
            values.offsetInBytes,
            values.lengthInBytes,
          ),
        ),
      ),
    ),
  );
}

/// Replaces [animation]'s channel at [index] with [channel].
ChangeRecord _replaceChannel(
  AnimationSpec animation,
  int index,
  AnimationChannelSpec channel,
) {
  final channels = [...animation.channels];
  channels[index] = channel;
  return ChangeRecord(
    targetId: animation.id,
    slot: ChangeSlot.poolAnimation,
    oldValue: AnimationChange(animation),
    newValue: AnimationChange(
      AnimationSpec(animation.id, name: animation.name, channels: channels),
    ),
  );
}

/// Rewrites one channel's times and values together, cloning either payload
/// first when something else still reads it, and repointing the channel when
/// a clone happened.
List<ChangeRecord> _rewriteChannel(
  CommandContext ctx,
  AnimationSpec animation,
  int channelIndex,
  Float32List times,
  Float32List values,
) {
  final channel = animation.channels[channelIndex];
  final timeWrite = _writeFloats(
    ctx,
    channel.timeline,
    times,
    clone: _isShared(
      ctx.document,
      channel.timeline,
      animation,
      channelIndex,
      true,
    ),
  );
  final valueWrite = _writeFloats(
    ctx,
    channel.keyframes,
    values,
    clone: _isShared(
      ctx.document,
      channel.keyframes,
      animation,
      channelIndex,
      false,
    ),
  );
  final records = [timeWrite.record, valueWrite.record];
  if (timeWrite.id != channel.timeline || valueWrite.id != channel.keyframes) {
    records.add(
      _replaceChannel(
        animation,
        channelIndex,
        AnimationChannelSpec(
          target: channel.target,
          targetName: channel.targetName,
          property: channel.property,
          timeline: timeWrite.id,
          keyframes: valueWrite.id,
        ),
      ),
    );
  }
  return records;
}

/// Sorts [times] ascending, permuting [values] (in blocks of [stride]) to
/// match, so a retimed key keeps its own value.
(Float32List, Float32List) _sortByTime(
  Float32List times,
  Float32List values,
  int stride,
) {
  final order = List<int>.generate(times.length, (i) => i)
    ..sort((a, b) => times[a].compareTo(times[b]));
  var sorted = true;
  for (var i = 0; i < order.length; i++) {
    if (order[i] != i) {
      sorted = false;
      break;
    }
  }
  if (sorted) return (times, values);

  final outTimes = Float32List(times.length);
  final outValues = Float32List(order.length * stride);
  for (var i = 0; i < order.length; i++) {
    outTimes[i] = times[order[i]];
    for (var c = 0; c < stride; c++) {
      outValues[i * stride + c] = values[order[i] * stride + c];
    }
  }
  return (outTimes, outValues);
}

/// The interpolated value of a channel at [time], as [stride] floats.
///
/// Linear between the bracketing keys, clamped at both ends. Rotation keys
/// interpolate componentwise and are renormalized, which is not a true slerp
/// but is what a sampled key needs: the result only has to sit on the curve
/// the resolver draws closely enough that inserting a key does not visibly
/// move the pose.
Float32List _sampleAt(
  Float32List times,
  Float32List values,
  int stride,
  AnimationProperty property,
  double time,
) {
  final out = Float32List(stride);
  if (times.isEmpty || stride == 0) return out;
  if (time <= times.first) {
    out.setRange(0, stride, values, 0);
    return out;
  }
  if (time >= times.last) {
    out.setRange(0, stride, values, (times.length - 1) * stride);
    return out;
  }
  var next = 1;
  while (next < times.length && times[next] < time) {
    next++;
  }
  final previous = next - 1;
  final span = times[next] - times[previous];
  final t = span <= 0 ? 0.0 : (time - times[previous]) / span;
  for (var c = 0; c < stride; c++) {
    final a = values[previous * stride + c];
    final b = values[next * stride + c];
    out[c] = a + (b - a) * t;
  }
  if (property == AnimationProperty.rotation) {
    var lengthSquared = 0.0;
    for (final v in out) {
      lengthSquared += v * v;
    }
    if (lengthSquared > 0) {
      final inverse = 1.0 / math.sqrt(lengthSquared);
      for (var c = 0; c < stride; c++) {
        out[c] *= inverse;
      }
    }
  }
  return out;
}

/// Decodes a base64 float32 blob parameter.
Float32List _requireFloats(Map<String, Object?> params, String key) {
  final bytes = base64Decode(requireString(params, key));
  if (bytes.lengthInBytes % 4 != 0) {
    throw CommandException(
      '"$key" must be a whole number of 32-bit floats, got '
      '${bytes.lengthInBytes} bytes',
    );
  }
  return Float32List.fromList(
    Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 4),
  );
}

String _encodeFloats(Float32List values) => base64Encode(
  Uint8List.view(values.buffer, values.offsetInBytes, values.lengthInBytes),
);

/// Base64-encodes [values] as float32, the shape the value parameters take.
String encodeAnimationValues(List<double> values) =>
    _encodeFloats(Float32List.fromList(values));

// ---------------------------------------------------------------------------
// Commands.
// ---------------------------------------------------------------------------

/// Creates an empty animation.
final createAnimation = CommandEntry(
  name: 'createAnimation',
  doc: 'Create an empty animation clip.',
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
    final name = optionalString(params, 'name') ?? 'Animation';
    return Transaction(
      name: 'Create animation',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolAnimation,
          oldValue: const AnimationChange(null),
          newValue: AnimationChange(AnimationSpec(id, name: name)),
        ),
      ],
    );
  },
);

/// Deletes an animation. Its payloads are left in the pool; an unreferenced
/// payload is dropped by the document's own pruning on save.
final deleteAnimation = CommandEntry(
  name: 'deleteAnimation',
  doc: 'Delete an animation clip.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
  ],
  execute: (ctx, params) {
    final id = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, id);
    return Transaction(
      name: 'Delete animation',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolAnimation,
          oldValue: AnimationChange(animation),
          newValue: const AnimationChange(null),
        ),
      ],
    );
  },
);

/// Renames an animation.
final renameAnimation = CommandEntry(
  name: 'renameAnimation',
  doc: "Set an animation clip's name.",
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
    final id = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, id);
    return Transaction(
      name: 'Rename animation',
      records: [
        ChangeRecord(
          targetId: id,
          slot: ChangeSlot.poolAnimation,
          oldValue: AnimationChange(animation),
          newValue: AnimationChange(
            AnimationSpec(
              id,
              name: requireString(params, 'name'),
              channels: [...animation.channels],
            ),
          ),
        ),
      ],
    );
  },
);

/// Adds an empty channel driving one property of one node.
final addAnimationChannel = CommandEntry(
  name: 'addAnimationChannel',
  doc: 'Add an empty channel driving one property of one node.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'nodeId', type: ParamType.nodeRef, label: 'Target'),
    ParamSpec(
      name: 'property',
      type: ParamType.string,
      label: 'Property',
      description: 'translation, rotation, scale, or weights.',
    ),
  ],
  execute: (ctx, params) {
    final animationId = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, animationId);
    final nodeId = requireNodeId(params, 'nodeId');
    final node = ctx.document.node(nodeId);
    if (node == null) {
      throw CommandException('Node not found: ${nodeId.toToken()}');
    }
    final propertyName = requireString(params, 'property');
    final property = AnimationProperty.values.where(
      (p) => p.name == propertyName,
    );
    if (property.isEmpty) {
      throw CommandException(
        'Unknown animation property "$propertyName"; expected one of '
        '${AnimationProperty.values.map((p) => p.name).join(', ')}',
      );
    }
    final timelineId = ctx.document.newId();
    final keyframesId = ctx.document.newId();
    return Transaction(
      name: 'Add animation channel',
      records: [
        ChangeRecord(
          targetId: timelineId,
          slot: ChangeSlot.poolPayload,
          oldValue: const PayloadChange(null),
          newValue: PayloadChange(
            PayloadSpec(
              timelineId,
              encoding: PayloadEncoding.floats,
              length: 0,
              bytes: Uint8List(0),
            ),
          ),
        ),
        ChangeRecord(
          targetId: keyframesId,
          slot: ChangeSlot.poolPayload,
          oldValue: const PayloadChange(null),
          newValue: PayloadChange(
            PayloadSpec(
              keyframesId,
              encoding: PayloadEncoding.floats,
              length: 0,
              bytes: Uint8List(0),
            ),
          ),
        ),
        ChangeRecord(
          targetId: animationId,
          slot: ChangeSlot.poolAnimation,
          oldValue: AnimationChange(animation),
          newValue: AnimationChange(
            AnimationSpec(
              animationId,
              name: animation.name,
              channels: [
                ...animation.channels,
                AnimationChannelSpec(
                  target: nodeId,
                  targetName: node.name.isEmpty ? null : node.name,
                  property: property.first,
                  timeline: timelineId,
                  keyframes: keyframesId,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  },
);

/// Removes a channel from an animation.
final removeAnimationChannel = CommandEntry(
  name: 'removeAnimationChannel',
  doc: 'Remove one channel from an animation.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'channel', type: ParamType.integer, label: 'Channel'),
  ],
  execute: (ctx, params) {
    final animationId = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, animationId);
    final index = requireInt(params, 'channel');
    _requireChannel(animation, index);
    final channels = [...animation.channels]..removeAt(index);
    return Transaction(
      name: 'Remove animation channel',
      records: [
        ChangeRecord(
          targetId: animationId,
          slot: ChangeSlot.poolAnimation,
          oldValue: AnimationChange(animation),
          newValue: AnimationChange(
            AnimationSpec(
              animationId,
              name: animation.name,
              channels: channels,
            ),
          ),
        ),
      ],
    );
  },
);

/// Moves one keyframe along the time axis.
final setAnimationKeyTime = CommandEntry(
  name: 'setAnimationKeyTime',
  doc: "Move one keyframe of one channel to a new time, in seconds.",
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'channel', type: ParamType.integer, label: 'Channel'),
    ParamSpec(name: 'key', type: ParamType.integer, label: 'Key'),
    ParamSpec(name: 'time', type: ParamType.number, label: 'Time'),
  ],
  execute: (ctx, params) {
    final animationId = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, animationId);
    final channelIndex = requireInt(params, 'channel');
    final channel = _requireChannel(animation, channelIndex);
    final keyIndex = requireInt(params, 'key');

    final times = _floats(ctx.document, channel.timeline);
    final values = _floats(ctx.document, channel.keyframes);
    if (keyIndex < 0 || keyIndex >= times.length) {
      throw CommandException(
        'Key $keyIndex is out of range for a ${times.length}-key channel',
      );
    }
    final time = requireDouble(params, 'time');
    times[keyIndex] = time < 0 ? 0 : time;

    // A key dragged past its neighbours reorders the timeline; the resolvers
    // require it non-decreasing, so re-sort and carry each key's value with
    // it rather than leaving values behind at the old index.
    final stride = _componentsPerKey(
      channel.property,
      times.length,
      values.length,
    );
    final (sortedTimes, sortedValues) = _sortByTime(times, values, stride);

    return Transaction(
      name: 'Move keyframe',
      records: _rewriteChannel(
        ctx,
        animation,
        channelIndex,
        sortedTimes,
        sortedValues,
      ),
    );
  },
);

/// Replaces one keyframe's value.
final setAnimationKeyValue = CommandEntry(
  name: 'setAnimationKeyValue',
  doc:
      "Replace one keyframe's value. The value is base64-encoded little-endian "
      'float32: three floats for translation and scale, four (x, y, z, w) for '
      'rotation, one per morph target for weights.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'channel', type: ParamType.integer, label: 'Channel'),
    ParamSpec(name: 'key', type: ParamType.integer, label: 'Key'),
    ParamSpec(name: 'value', type: ParamType.string, label: 'Value'),
  ],
  execute: (ctx, params) {
    final animationId = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, animationId);
    final channelIndex = requireInt(params, 'channel');
    final channel = _requireChannel(animation, channelIndex);
    final keyIndex = requireInt(params, 'key');

    final times = _floats(ctx.document, channel.timeline);
    final values = _floats(ctx.document, channel.keyframes);
    if (keyIndex < 0 || keyIndex >= times.length) {
      throw CommandException(
        'Key $keyIndex is out of range for a ${times.length}-key channel',
      );
    }
    final stride = _componentsPerKey(
      channel.property,
      times.length,
      values.length,
    );
    final value = _requireFloats(params, 'value');
    if (value.length != stride) {
      throw CommandException(
        'A ${channel.property.name} keyframe takes $stride floats, got '
        '${value.length}',
      );
    }
    values.setRange(keyIndex * stride, (keyIndex + 1) * stride, value);

    return Transaction(
      name: 'Set keyframe value',
      records: _rewriteChannel(ctx, animation, channelIndex, times, values),
    );
  },
);

/// Inserts a keyframe at a time, sampling the channel's current curve when no
/// explicit value is given.
final insertAnimationKey = CommandEntry(
  name: 'insertAnimationKey',
  doc:
      'Insert a keyframe into a channel at a time, in seconds. Without a '
      'value the channel is sampled at that time, so the pose does not move. '
      'A key already at that time is replaced.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'channel', type: ParamType.integer, label: 'Channel'),
    ParamSpec(name: 'time', type: ParamType.number, label: 'Time'),
    ParamSpec(
      name: 'value',
      type: ParamType.string,
      label: 'Value',
      description:
          'Base64 float32, as setAnimationKeyValue takes. Omitted samples '
          'the existing curve.',
      required: false,
    ),
  ],
  execute: (ctx, params) {
    final animationId = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, animationId);
    final channelIndex = requireInt(params, 'channel');
    final channel = _requireChannel(animation, channelIndex);
    final rawTime = requireDouble(params, 'time');
    final time = rawTime < 0 ? 0.0 : rawTime;

    final times = _floats(ctx.document, channel.timeline);
    final values = _floats(ctx.document, channel.keyframes);
    var stride = _componentsPerKey(
      channel.property,
      times.length,
      values.length,
    );

    final explicit = params['value'] == null
        ? null
        : _requireFloats(params, 'value');
    if (stride == 0) {
      // An empty weights channel has no stride to read off the data, so the
      // first key has to declare it.
      if (explicit == null || explicit.isEmpty) {
        throw CommandException(
          'The first keyframe of an empty ${channel.property.name} channel '
          'needs an explicit value, which is what fixes its width',
        );
      }
      stride = explicit.length;
    }
    final value =
        explicit ?? _sampleAt(times, values, stride, channel.property, time);
    if (value.length != stride) {
      throw CommandException(
        'A ${channel.property.name} keyframe takes $stride floats, got '
        '${value.length}',
      );
    }

    // Replace rather than duplicate an existing key at the same time: two
    // keys at one time make the resolver's span zero.
    final existing = times.indexWhere((t) => (t - time).abs() < 1e-6);
    final Float32List outTimes;
    final Float32List outValues;
    if (existing >= 0) {
      outTimes = times;
      outValues = values;
      outValues.setRange(existing * stride, (existing + 1) * stride, value);
    } else {
      var insertAt = times.length;
      for (var i = 0; i < times.length; i++) {
        if (times[i] > time) {
          insertAt = i;
          break;
        }
      }
      outTimes = Float32List(times.length + 1);
      outValues = Float32List((times.length + 1) * stride);
      outTimes.setRange(0, insertAt, times);
      outValues.setRange(0, insertAt * stride, values);
      outTimes[insertAt] = time;
      outValues.setRange(insertAt * stride, (insertAt + 1) * stride, value);
      for (var i = insertAt; i < times.length; i++) {
        outTimes[i + 1] = times[i];
        for (var c = 0; c < stride; c++) {
          outValues[(i + 1) * stride + c] = values[i * stride + c];
        }
      }
    }

    return Transaction(
      name: 'Insert keyframe',
      records: _rewriteChannel(
        ctx,
        animation,
        channelIndex,
        outTimes,
        outValues,
      ),
    );
  },
);

/// Removes one keyframe.
final deleteAnimationKey = CommandEntry(
  name: 'deleteAnimationKey',
  doc: 'Remove one keyframe from a channel.',
  category: 'Animation',
  paramSchema: const [
    ParamSpec(
      name: 'animationId',
      type: ParamType.resourceRef,
      label: 'Animation',
    ),
    ParamSpec(name: 'channel', type: ParamType.integer, label: 'Channel'),
    ParamSpec(name: 'key', type: ParamType.integer, label: 'Key'),
  ],
  execute: (ctx, params) {
    final animationId = requireResourceId(params, 'animationId');
    final animation = _requireAnimation(ctx, animationId);
    final channelIndex = requireInt(params, 'channel');
    final channel = _requireChannel(animation, channelIndex);
    final keyIndex = requireInt(params, 'key');

    final times = _floats(ctx.document, channel.timeline);
    final values = _floats(ctx.document, channel.keyframes);
    if (keyIndex < 0 || keyIndex >= times.length) {
      throw CommandException(
        'Key $keyIndex is out of range for a ${times.length}-key channel',
      );
    }
    final stride = _componentsPerKey(
      channel.property,
      times.length,
      values.length,
    );

    final outTimes = Float32List(times.length - 1);
    final outValues = Float32List((times.length - 1) * stride);
    var write = 0;
    for (var i = 0; i < times.length; i++) {
      if (i == keyIndex) continue;
      outTimes[write] = times[i];
      for (var c = 0; c < stride; c++) {
        outValues[write * stride + c] = values[i * stride + c];
      }
      write++;
    }

    return Transaction(
      name: 'Delete keyframe',
      records: _rewriteChannel(
        ctx,
        animation,
        channelIndex,
        outTimes,
        outValues,
      ),
    );
  },
);

/// The animation authoring commands, registered alongside the built-ins.
final List<CommandEntry> animationCommands = [
  createAnimation,
  deleteAnimation,
  renameAnimation,
  addAnimationChannel,
  removeAnimationChannel,
  setAnimationKeyTime,
  setAnimationKeyValue,
  insertAnimationKey,
  deleteAnimationKey,
];
