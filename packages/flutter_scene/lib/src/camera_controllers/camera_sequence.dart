import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/camera_director.dart';
import 'package:flutter_scene/src/components/component.dart';

/// One shot in a [CameraSequence]: a camera, how long to stay on it, and how
/// to get there.
/// {@category Scene graph}
class CameraShot {
  /// Creates a shot that holds [camera] for [hold] seconds, arriving with
  /// [blendIn] (or the director's default blend).
  const CameraShot(this.camera, {this.hold = 3.0, this.blendIn})
    : assert(hold > 0, 'A shot must be held for a positive time.');

  /// The camera this shot shows.
  final CameraController camera;

  /// How long the shot lasts, in seconds, measured from the moment the blend
  /// into it *starts*. A two-second shot with a one-second blend in front of
  /// it is on screen alone for one second, which is what makes a cut list
  /// add up to the running time you wrote down.
  final double hold;

  /// How to arrive at this shot. Null uses the director's
  /// [CameraDirector.defaultBlend].
  final CameraBlend? blendIn;
}

/// Plays a list of [CameraShot]s through a [CameraDirector]: a cutscene, an
/// attract-mode loop, a replay.
///
/// The sequence is only a clock. It decides *when* to change shots and asks
/// the director to make the change; the director still owns the blending, so
/// a sequence composes with everything else the director does — a shot can be
/// interrupted, priority can steal the camera back, and gameplay cameras keep
/// tracking underneath.
///
/// Attach it to any node in the scene (the camera node is the obvious one) so
/// it ticks:
///
/// ```dart
/// final sequence = CameraSequence(director, shots: [
///   CameraShot(establishing, hold: 4.0),
///   CameraShot(overTheShoulder, hold: 3.0, blendIn: const CameraBlend(1.0)),
///   CameraShot(closeUp, hold: 2.0, blendIn: const CameraBlend.cut()),
/// ])..onComplete = () => print('scene over');
/// cameraNode.addComponent(sequence);
/// sequence.play();
/// ```
///
/// When the last shot ends the sequence releases the camera by clearing the
/// director's selection, so whatever gameplay camera had priority takes back
/// over on its own. Set [releaseOnComplete] false to stay parked on the final
/// shot instead.
/// {@category Scene graph}
class CameraSequence extends Component {
  /// Creates a sequence driving [director].
  CameraSequence(
    this.director, {
    List<CameraShot>? shots,
    this.loop = false,
    this.releaseOnComplete = true,
    this.releaseBlend,
    this.onComplete,
    this.onShotChanged,
  }) : _shots = <CameraShot>[...?shots];

  /// The director this sequence drives.
  ///
  /// Assignable so a sequence can be pointed at a director that did not exist
  /// when it was built — which is the normal case when both are loaded from a
  /// document, where the sequence may be realized first. Changing it while a
  /// sequence is playing leaves the outgoing director holding the camera;
  /// [stop] first if that matters.
  CameraDirector director;

  /// Whether the sequence restarts from the first shot when it ends.
  bool loop;

  /// Whether finishing hands the camera back to priority. Ignored when
  /// [loop] is set, since a looping sequence never finishes.
  bool releaseOnComplete;

  /// How to blend when handing the camera back. Null uses the director's
  /// default.
  CameraBlend? releaseBlend;

  /// Called when the last shot ends (never, when [loop] is set).
  void Function()? onComplete;

  /// Called as each shot begins, with its index.
  void Function(int index, CameraShot shot)? onShotChanged;

  final List<CameraShot> _shots;

  int _index = -1;
  double _elapsed = 0.0;
  bool _playing = false;

  /// The shots, in order.
  List<CameraShot> get shots => List<CameraShot>.unmodifiable(_shots);

  /// The index of the shot on screen, or `-1` before [play].
  int get currentIndex => _index;

  /// The shot on screen, or null when the sequence is not running.
  CameraShot? get currentShot =>
      _index >= 0 && _index < _shots.length ? _shots[_index] : null;

  /// Whether the sequence is advancing.
  bool get isPlaying => _playing;

  /// How long the whole sequence runs, in seconds.
  double get totalDuration => _shots.fold(0.0, (sum, shot) => sum + shot.hold);

  /// Appends a shot.
  void add(
    CameraController camera, {
    double hold = 3.0,
    CameraBlend? blendIn,
  }) => _shots.add(CameraShot(camera, hold: hold, blendIn: blendIn));

  /// Replaces the shot list. Stops the sequence if it was running.
  void setShots(List<CameraShot> shots) {
    stop();
    _shots
      ..clear()
      ..addAll(shots);
  }

  /// Starts from [from] (the first shot by default).
  void play({int from = 0}) {
    if (_shots.isEmpty) return;
    _playing = true;
    _index = -1;
    _elapsed = 0.0;
    _enter(from.clamp(0, _shots.length - 1));
  }

  /// Holds on the current shot without ending the sequence.
  void pause() => _playing = false;

  /// Resumes after [pause].
  void resume() {
    if (_index >= 0) _playing = true;
  }

  /// Ends the sequence immediately, releasing the camera if
  /// [releaseOnComplete] is set.
  void stop() {
    if (_index < 0 && !_playing) return;
    _playing = false;
    _index = -1;
    _elapsed = 0.0;
    if (releaseOnComplete) director.clearSelection(blend: releaseBlend);
  }

  /// Cuts to the next shot early, ending the sequence if there is none.
  void skip() {
    if (!_playing) return;
    if (_index + 1 < _shots.length) {
      _enter(_index + 1);
    } else {
      _finish();
    }
  }

  void _enter(int index) {
    _index = index;
    _elapsed = 0.0;
    final shot = _shots[index];
    director.select(shot.camera, blend: shot.blendIn);
    onShotChanged?.call(index, shot);
  }

  void _finish() {
    _playing = false;
    _index = -1;
    _elapsed = 0.0;
    if (releaseOnComplete) director.clearSelection(blend: releaseBlend);
    onComplete?.call();
  }

  @override
  void update(double deltaSeconds) {
    if (!_playing || _index < 0) return;
    _elapsed += deltaSeconds;
    // A while loop, not an if: a shot shorter than the frame interval (or a
    // long stall) must not leave the sequence lagging a shot behind. The
    // budget stops a list of zero-length shots (only reachable with asserts
    // off) from spinning forever; it advances at most one full pass.
    var budget = _shots.length + 1;
    while (_playing &&
        _index >= 0 &&
        _elapsed >= _shots[_index].hold &&
        budget-- > 0) {
      final carry = _elapsed - _shots[_index].hold;
      if (_index + 1 < _shots.length) {
        _enter(_index + 1);
        _elapsed = carry;
      } else if (loop) {
        _enter(0);
        _elapsed = carry;
      } else {
        _finish();
      }
    }
  }
}
