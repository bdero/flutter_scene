part of '../animation.dart';

class _ChannelBinding {
  AnimationChannel channel;
  Node node;

  _ChannelBinding(this.channel, this.node);
}

/// An instance of an [Animation] that has been bound to a specific [Node].
class AnimationClip {
  final Animation _animation;
  final List<_ChannelBinding> _bindings = [];

  double _playbackTime = 0;
  double get playbackTime => _playbackTime;
  set playbackTime(double timeInSeconds) {
    seek(timeInSeconds);
  }

  double playbackTimeScale = 1;

  double _weight = 1;
  double get weight => _weight;
  set weight(double value) {
    _weight = clampDouble(value, 0, 1);
  }

  bool playing = false;

  bool loop = false;

  AnimationClip(this._animation, Node bindTarget) {
    _bindToTarget(bindTarget);
  }

  void play() {
    playing = true;
  }

  void pause() {
    playing = false;
  }

  void stop() {
    playing = false;
    seek(0);
  }

  void seek(double time) {
    _playbackTime = clampDouble(time, 0, _animation.endTime);
  }

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
