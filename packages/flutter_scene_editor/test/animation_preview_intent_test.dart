// Pins the animation preview control's application order: select (only on
// change) -> stop -> loop -> speed -> seek -> play/pause. This is the
// contract the MCP `control_animation_preview` tool documents.
import 'package:flutter_scene_editor/src/controller/animation_preview_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

class _RecordingTarget implements AnimationPreviewTarget {
  final List<String> calls = [];
  LocalId? _loaded;
  bool playing = false;

  @override
  LocalId? get previewAnimationId => _loaded;

  @override
  void selectPreviewAnimation(LocalId id) {
    _loaded = id;
    calls.add('select');
  }

  @override
  void stopPreview() => calls.add('stop');

  @override
  void setPreviewLoop(bool loop) => calls.add('loop:$loop');

  @override
  void setPreviewSpeed(double speed) => calls.add('speed:$speed');

  @override
  void seekPreview(double time) => calls.add('seek:$time');

  @override
  void playPreview() {
    playing = true;
    calls.add('play');
  }

  @override
  void pausePreview() {
    playing = false;
    calls.add('pause');
  }
}

LocalId _id(int n) => LocalId.parse('000000800000${n.toString().padLeft(2, '0')}');

void main() {
  test('applies every field in the documented order', () {
    final target = _RecordingTarget();
    applyAnimationPreviewRequest(
      target,
      animationId: _id(1),
      loop: false,
      speed: 2.0,
      seek: 0.5,
      playing: true,
    );
    expect(target.calls, [
      'select',
      'loop:false',
      'speed:2.0',
      'seek:0.5',
      'play',
    ]);
    expect(target.playing, isTrue);
  });

  test('does not re-select the already-loaded animation', () {
    final target = _RecordingTarget()..selectPreviewAnimation(_id(1));
    target.calls.clear();
    applyAnimationPreviewRequest(target, animationId: _id(1), seek: 0.25);
    expect(target.calls, ['seek:0.25']);
  });

  test('stop lands before seek so one call can reset and reposition', () {
    final target = _RecordingTarget()..selectPreviewAnimation(_id(2));
    target.calls.clear();
    applyAnimationPreviewRequest(target, stop: true, seek: 1.5, playing: false);
    expect(target.calls, ['stop', 'seek:1.5', 'pause']);
    expect(target.playing, isFalse);
  });

  test('an empty request touches nothing', () {
    final target = _RecordingTarget();
    applyAnimationPreviewRequest(target);
    expect(target.calls, isEmpty);
  });
}
