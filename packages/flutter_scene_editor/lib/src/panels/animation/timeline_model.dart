// Split out of animation_panel.dart; see the owning library there.
part of '../animation_panel.dart';

/// One keyframe position on a timeline lane.
typedef TimelineKey = ({
  LocalId target,
  AnimationProperty property,
  double time,
});

/// One visual row of the timeline canvas: either a node group header or one
/// channel's keyframe lane beneath it. Headers carry only a display title
/// plus the group's channels (for the header-row interpolation control);
/// lanes additionally carry their channel and its keyframe times.
typedef _LaneRow = ({
  bool isHeader,
  String title,
  List<double>? times,
  AnimationChannelSpec? channel,
  List<AnimationChannelSpec>? groupChannels,
});

/// Pure view-state math behind [AnimationTimeline]: how the user's zoom and
/// scroll state maps to a pixel scale and a scrollable range.
///
/// The zoom floor sits below fit-to-clip on purpose — zooming out past fit
/// widens the visible window beyond the clip's end, which is the empty region
/// where keys are placed to grow the animation's duration. Fit itself always
/// stays reachable (and is the default while [zoomPx] is null).
class TimelineViewport {
  const TimelineViewport({
    required this.laneWidth,
    required this.duration,
    this.zoomPx,
    double scroll = 0,
  }) : _scroll = scroll;

  /// Width of the time area in px (pane width minus the label column).
  final double laneWidth;

  /// The clip's duration in seconds (its last keyframe time).
  final double duration;

  /// User-set scale in px/s; null means fit-to-width.
  final double? zoomPx;

  final double _scroll;

  static const double minPxPerSecond = 20;
  static const double maxPxPerSecond = 600;

  double get fitPxPerSecond => laneWidth / (duration > 0 ? duration : 1);

  double get pxPerSecond => (zoomPx ?? fitPxPerSecond).clamp(
    math.min(fitPxPerSecond, minPxPerSecond),
    math.max(fitPxPerSecond, maxPxPerSecond),
  );

  double get maxScroll => math.max(0.0, duration * pxPerSecond - laneWidth);

  double get scroll => _scroll.clamp(0.0, maxScroll);

  /// The scale after multiplying by [factor], held inside the zoom range.
  double scaledBy(double factor) => (pxPerSecond * factor).clamp(
    math.min(fitPxPerSecond, minPxPerSecond),
    math.max(fitPxPerSecond, maxPxPerSecond),
  );

  /// The scroll offset that keeps [anchorTime] centered, at scale [atScale].
  double scrollForAnchor(double anchorTime, double atScale) =>
      (anchorTime * atScale - laneWidth / 2).clamp(
        0.0,
        math.max(0.0, duration * atScale - laneWidth),
      );
}

const double _rulerHeight = 18;
const double _rowHeight = 22;

/// Sanity cap for keyframe times reached by clicking or dragging past the
/// clip's end. The clip's duration is its last keyframe time, so placing a
/// key out here is how the clip grows.
const double _maxKeyTime = 600;

/// The keyframe times of [channel], read out of its timeline payload.
///
/// The decode is cached on the payload's [ByteData] object itself: payloads
/// are immutable snapshots, and document edits produce new `ByteData`
/// objects, so a changed timeline gets a fresh cache entry while stale ones
/// are garbage-collected with the payloads they belong to. The returned list
/// is shared between callers — treat it as read-only.
List<double> channelTimes(
  SceneDocument document,
  AnimationChannelSpec channel,
) {
  final bytes = document.payload(channel.timeline)?.bytes;
  if (bytes == null) return const [];
  final cached = _decodedTimelines[bytes];
  if (cached != null) return cached;
  final Float32List floats;
  if (bytes.offsetInBytes % 4 == 0) {
    floats = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
  } else {
    floats = Uint8List.fromList(
      bytes,
    ).buffer.asFloat32List(0, bytes.lengthInBytes ~/ 4);
  }
  final times = [for (var i = 0; i < floats.length; i++) floats[i]];
  _decodedTimelines[bytes] = times;
  return times;
}

/// Decode cache for [channelTimes], keyed on the payload `ByteData` identity.
/// An [Expando] (rather than a `Map`) keeps entries alive only as long as
/// their payload, so there is nothing to invalidate or leak.
final Expando<List<double>> _decodedTimelines = Expando<List<double>>();
