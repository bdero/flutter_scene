/// The Animation panel's pure model: decoding a clip's channels out of the
/// document, and the timeline arithmetic the sheet is drawn and hit-tested
/// with.
///
/// Kept apart from the panel widget because none of it needs a GPU, a live
/// scene, or a controller: it turns a [SceneDocument] and a few numbers into
/// what to draw and what the pointer landed on, which is the half worth
/// pinning with tests.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scene/scene.dart';

/// One channel of a clip, decoded from its two float payloads.
class AnimationTrack {
  AnimationTrack({
    required this.channelIndex,
    required this.targetName,
    required this.property,
    required this.times,
    required this.values,
    required this.stride,
  });

  /// This channel's index in the clip, which is how the animation commands
  /// address it.
  final int channelIndex;

  /// The name of the node the channel drives, for the row label.
  final String targetName;

  final AnimationProperty property;

  /// Keyframe times, seconds, non-decreasing.
  final Float32List times;

  /// Keyframe values, [stride] floats per key.
  final Float32List values;

  /// Floats per keyframe: 3 for translation and scale, 4 for rotation, one
  /// per morph target for weights.
  ///
  /// Zero for a weights channel with no keys yet, which has no width to read
  /// off its data.
  final int stride;

  double get endTime => times.isEmpty ? 0 : times.last;

  double valueAt(int key, int component) => values[key * stride + component];
}

/// A clip's channels, grouped by the node they drive.
class AnimationTimeline {
  AnimationTimeline({
    required this.id,
    required this.name,
    required this.tracks,
  });

  final LocalId id;
  final String name;
  final List<AnimationTrack> tracks;

  /// The last keyframe time across every channel.
  double get endTime =>
      tracks.fold(0.0, (longest, t) => math.max(longest, t.endTime));

  /// Target names in first-appearance order, so the sheet's rows follow the
  /// channel order the clip was authored or imported with rather than an
  /// alphabetical one that would shuffle on every re-import.
  List<String> get targets {
    final seen = <String>[];
    for (final track in tracks) {
      if (!seen.contains(track.targetName)) seen.add(track.targetName);
    }
    return seen;
  }

  List<AnimationTrack> tracksFor(String target) => [
    for (final track in tracks)
      if (track.targetName == target) track,
  ];

  /// Every keyframe time in the clip, sorted and de-duplicated, for the
  /// previous/next key jumps and for a group row's summary markers.
  List<double> get keyTimes {
    final times = <double>{};
    for (final track in tracks) {
      times.addAll(track.times);
    }
    return times.toList()..sort();
  }
}

/// Decodes [spec]'s channels out of [document].
AnimationTimeline buildAnimationTimeline(
  SceneDocument document,
  AnimationSpec spec,
) {
  final tracks = <AnimationTrack>[];
  for (var i = 0; i < spec.channels.length; i++) {
    final channel = spec.channels[i];
    final times = payloadFloats(document, channel.timeline);
    final values = payloadFloats(document, channel.keyframes);
    tracks.add(
      AnimationTrack(
        channelIndex: i,
        targetName:
            document.node(channel.target)?.name ??
            channel.targetName ??
            channel.target.toToken(),
        property: channel.property,
        times: times,
        values: values,
        stride: keyStride(channel.property, times.length, values.length),
      ),
    );
  }
  return AnimationTimeline(id: spec.id, name: spec.name, tracks: tracks);
}

/// The floats of payload [id], or an empty list when it is absent or empty.
///
/// A view rather than a copy: this runs on every rebuild of the panel, and
/// nothing here writes to it.
Float32List payloadFloats(SceneDocument document, LocalId id) {
  final bytes = document.payload(id)?.bytes;
  if (bytes == null || bytes.lengthInBytes < 4) return Float32List(0);
  return Float32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
}

/// Floats per keyframe for [property]. A weights channel's width is only
/// knowable from its data, so it needs the counts.
int keyStride(AnimationProperty property, int keyCount, int valueCount) =>
    switch (property) {
      AnimationProperty.translation || AnimationProperty.scale => 3,
      AnimationProperty.rotation => 4,
      AnimationProperty.weights => keyCount == 0 ? 0 : valueCount ~/ keyCount,
    };

/// Rounds [seconds] to the nearest sample, so a key dragged with the pointer
/// lands on a whole frame instead of between two.
double snapToSamples(double seconds, int sampleRate) =>
    sampleRate <= 0 ? seconds : (seconds * sampleRate).round() / sampleRate;

/// Seconds between the ruler's labelled ticks at this zoom.
///
/// Walks a 1-2-5 ladder until a tick is at least [minimumPixels] apart from
/// the next, so labels never collide and the numbers stay round at every
/// zoom. Zoomed far enough in the ladder bottoms out at one tick per sample,
/// since a finer division would label times that cannot be keyed.
double majorTickStep({
  required double pixelsPerSecond,
  required int sampleRate,
  double minimumPixels = 60,
}) {
  if (pixelsPerSecond <= 0) return 1;
  final frame = sampleRate > 0 ? 1 / sampleRate : 1 / 60;
  final target = minimumPixels / pixelsPerSecond;
  if (target <= frame) return frame;
  final decade = math
      .pow(10, (math.log(target) / math.ln10).floorToDouble())
      .toDouble();
  for (final multiple in const [1.0, 2.0, 5.0]) {
    if (decade * multiple >= target) return decade * multiple;
  }
  return decade * 10;
}

/// A ruler label: `m:ss`, with hundredths appended once the ticks are finer
/// than a second.
String formatTimelineLabel(double seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds - minutes * 60;
  final whole = rest.floor();
  final fraction = rest - whole;
  final hundredths = (fraction * 100).round();
  final decimals = hundredths == 0
      ? ''
      : '.${hundredths.toString().padLeft(2, '0')}';
  return '$minutes:${whole.toString().padLeft(2, '0')}$decimals';
}

/// The index of the key nearest [seconds] within [grabPixels] of it, or null.
///
/// Distance is measured in pixels rather than seconds so the grab radius
/// stays the same size on screen at every zoom.
int? nearestKeyIndex(
  Float32List times,
  double seconds, {
  required double pixelsPerSecond,
  double grabPixels = 6,
}) {
  var best = -1;
  var bestDistance = double.infinity;
  for (var i = 0; i < times.length; i++) {
    final distance = (times[i] - seconds).abs() * pixelsPerSecond;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best >= 0 && bestDistance <= grabPixels ? best : null;
}

/// The next keyframe time after [from] (or before it, backwards), clamped to
/// the ends so the transport keeps working at either edge. Null when there
/// are no keys at all.
double? adjacentKeyTime(
  List<double> sortedTimes,
  double from, {
  required bool forward,
}) {
  if (sortedTimes.isEmpty) return null;
  const epsilon = 1e-6;
  if (forward) {
    for (final time in sortedTimes) {
      if (time > from + epsilon) return time;
    }
    return sortedTimes.last;
  }
  for (final time in sortedTimes.reversed) {
    if (time < from - epsilon) return time;
  }
  return sortedTimes.first;
}
