part of '../animation.dart';

class _ChannelBinding {
  AnimationChannel channel;
  Node node;

  _ChannelBinding(this.channel, this.node);
}

/// An instance of an [Animation] that has been bound to a specific [Node].
///
/// Create one with [Node.createAnimationClip]. Each clip carries its own
/// [playing], [playbackTime], [playbackTimeScale], [weight], and [loop]
/// state, so the same [Animation] can be played at different speeds and
/// blends across multiple subtrees.
///
/// Multiple clips on the same node are blended by an internal
/// [AnimationPlayer] that normalizes their weights when the sum exceeds
/// `1`.
class AnimationClip {
  final Animation _animation;
  final List<_ChannelBinding> _bindings = [];

  double _playbackTime = 0;

  /// The current playback position in seconds, in `[0, Animation.endTime]`.
  ///
  /// Assigning is equivalent to calling [seek].
  double get playbackTime => _playbackTime;
  set playbackTime(double timeInSeconds) {
    seek(timeInSeconds);
  }

  /// Speed multiplier applied to delta times when [advance] is called.
  ///
  /// `1` is real-time; `2` plays the clip at double speed; negative
  /// values play in reverse.
  double playbackTimeScale = 1;

  double _weight = 1;

  /// Blend weight in `[0, 1]`, used by [AnimationPlayer] to mix this
  /// clip with other concurrently playing clips on the same node.
  ///
  /// Assignments are clamped to the valid range.
  double get weight => _weight;
  set weight(double value) {
    _weight = clampDouble(value, 0, 1);
  }

  /// Whether [advance] should integrate elapsed time into [playbackTime].
  ///
  /// Toggle indirectly with [play], [pause], or [stop].
  bool playing = false;

  /// Whether the clip should wrap around at the end of the animation
  /// (or the beginning, when playing in reverse) instead of pausing.
  bool loop = false;

  /// Binds [_animation] to the node subtree rooted at [bindTarget].
  ///
  /// Only channels whose [BindKey.nodeName] is found in the subtree are
  /// retained; missing nodes are silently ignored.
  AnimationClip(this._animation, Node bindTarget) {
    _bindToTarget(bindTarget);
  }

  /// Starts (or resumes) playback. Equivalent to setting [playing] to
  /// `true`.
  void play() {
    playing = true;
  }

  /// Pauses playback at the current [playbackTime].
  void pause() {
    playing = false;
  }

  /// Pauses playback and seeks back to the beginning.
  void stop() {
    playing = false;
    seek(0);
  }

  /// Seeks back to the beginning and starts playing.
  ///
  /// Useful for non-looping clips that were left paused at their end
  /// after a previous play, where the natural game-loop pattern of
  /// `clip.playing = someCondition` doesn't trigger a fresh play.
  /// Equivalent to `seek(0); play();`.
  void replay() {
    seek(0);
    playing = true;
  }

  /// Seeks to [time] (clamped to `[0, Animation.endTime]`) and starts
  /// playing.
  ///
  /// Equivalent to `seek(time); play();`.
  void gotoAndPlay(double time) {
    seek(time);
    playing = true;
  }

  /// Sets [playbackTime] to [time] (clamped to `[0, Animation.endTime]`).
  void seek(double time) {
    _playbackTime = clampDouble(time, 0, _animation.endTime);
  }

  /// Advances [playbackTime] by [deltaTime] seconds (scaled by
  /// [playbackTimeScale]).
  ///
  /// No-op when the clip is not [playing] or `deltaTime <= 0`. Handles
  /// looping behavior: if [loop] is `false`, playback clamps and pauses
  /// at the boundaries; if `true`, it wraps around.
  void advance(double deltaTime) {
    if (!playing || deltaTime <= 0) {
      return;
    }
    deltaTime *= playbackTimeScale;
    _playbackTime += deltaTime;

    // Handle looping behavior.

    if (_animation.endTime == 0) {
      _playbackTime = 0;
      return;
    }
    if (!loop && (_playbackTime < 0 || _playbackTime > _animation.endTime)) {
      // If looping is disabled, clamp to the end (or beginning, if playing in
      // reverse) and pause.
      pause();
      _playbackTime = clampDouble(_playbackTime, 0, _animation.endTime);
    } else if ( /* loop && */ _playbackTime > _animation.endTime) {
      // If looping is enabled and we ran off the end, loop to the beginning.
      _playbackTime = _playbackTime.abs() % _animation.endTime;
    } else if ( /* loop && */ _playbackTime < 0) {
      // If looping is enabled and we ran off the beginning, loop to the end.
      _playbackTime =
          _animation.endTime - (_playbackTime.abs() % _animation.endTime);
    }
  }

  void _bindToTarget(Node target) {
    final channels = _animation.channels;
    _bindings.clear();
    for (var channel in channels) {
      Node channelTarget;
      if (channel.bindTarget.nodeName == target.name) {
        channelTarget = target;
      }
      Node? result = target.getChildByName(channel.bindTarget.nodeName);
      if (result != null) {
        channelTarget = result;
      } else {
        continue;
      }
      _bindings.add(_ChannelBinding(channel, channelTarget));
    }
  }

  /// Evaluates each bound channel at [playbackTime] and accumulates the
  /// result into [transformDecomps].
  ///
  /// Called once per frame by [AnimationPlayer.update]. [weightMultiplier]
  /// is the player-wide normalization applied when concurrent clips'
  /// weights sum to more than `1`.
  void applyToBindings(
    Map<Node, AnimationTransforms> transformDecomps,
    double weightMultiplier,
  ) {
    for (var binding in _bindings) {
      final transforms = transformDecomps[binding.node];
      if (transforms == null) {
        continue;
      }
      binding.channel.resolver.apply(
        transforms,
        _playbackTime,
        _weight * weightMultiplier,
      );
    }
  }
}
