import 'dart:ui' show Offset, Size;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/services.dart' show KeyEvent;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_pose.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/kit/camera/camera_shake.dart';

/// How a [CameraDirector] moves from one camera to another.
///
/// A blend is a [duration] and a [curve]. A zero duration is a hard cut. The
/// curve is any Flutter [Curve], so the whole of [Curves] is available:
/// [Curves.easeInOut] for a neutral hand-off, [Curves.easeOutCubic] for a
/// snappy arrival, [Curves.linear] for a mechanical camera move.
/// {@category Scene graph}
class CameraBlend {
  /// A blend of [duration] seconds shaped by [curve].
  const CameraBlend(this.duration, {this.curve = Curves.easeInOut});

  /// An instant change with no interpolation.
  const CameraBlend.cut() : duration = 0.0, curve = Curves.linear;

  /// How long the blend takes, in seconds. Zero or less is a cut.
  final double duration;

  /// The easing applied to the blend's progress.
  final Curve curve;

  /// Whether this blend is instant.
  bool get isCut => duration <= 0.0;

  @override
  String toString() => isCut ? 'CameraBlend.cut()' : 'CameraBlend($duration)';
}

/// Holds several cameras and shows a blend of them through one real camera
/// node: the piece that turns a set of camera controllers into cinematics.
///
/// Attach a director to the node carrying the [CameraComponent], then register
/// cameras with it instead of attaching them to nodes of their own. Every
/// registered camera keeps running each frame — a follow camera keeps
/// following, an orbit camera keeps easing — but only the director writes to
/// the real camera node, and what it writes is the interpolation between the
/// outgoing and incoming shots.
///
/// ```dart
/// final director = CameraDirector(defaultBlend: const CameraBlend(1.2));
/// cameraNode.addComponent(director);
///
/// final gameplay = FollowCameraController(followTarget: player);
/// final overTheShoulder = FollowCameraController(followTarget: npc, distance: 3);
/// director.add(gameplay, priority: 10);
/// director.add(overTheShoulder, priority: 0);
///
/// // Later, during a conversation:
/// director.blendTo(overTheShoulder, duration: 0.8, curve: Curves.easeInOutCubic);
/// ```
///
/// ## Which camera is live
///
/// Two mechanisms pick the live camera, and they compose:
///
///  * **Priority.** Absent an explicit selection, the enabled camera with the
///    highest [priority] wins (ties go to the most recently added). This is
///    the ambient rule: raise a cutscene camera's priority to take over,
///    lower it to hand back, and the director blends both ways on its own.
///  * **Selection.** [blendTo], [cutTo], and [select] name a camera outright,
///    overriding priority until [clearSelection].
///
/// ## Blending
///
/// A blend interpolates position, orientation (along the short arc), and the
/// lens. Both cameras keep advancing during it, so blending away from a
/// camera that is tracking a moving character tracks the character all the
/// way through the transition rather than freezing on the frame the blend
/// started. Interrupting a blend is safe: the new blend starts from the live
/// in-between pose, so there is no snap.
///
/// ## The lens
///
/// A camera whose pose carries no [CameraPose.projection] does not touch the
/// lens; the director leaves the [CameraComponent]'s projection alone. When a
/// camera does specify one, the director blends the component's current lens
/// into it (see [CameraProjection.lerpTo]), which is how a shot can pull a
/// dolly zoom or move between a perspective and an orthographic view.
/// {@category Scene graph}
class CameraDirector extends Component implements CameraDirectorBinding {
  /// Creates a director that blends over [defaultBlend] when the live camera
  /// changes on its own (a priority change, or a camera being added or
  /// removed). Explicit [blendTo] calls override it per transition.
  CameraDirector({
    this.defaultBlend = const CameraBlend(0.75),
    this.shake,
    this.onCameraChanged,
  });

  /// The blend used for transitions that do not name their own.
  CameraBlend defaultBlend;

  /// Optional shake layered on top of the blended pose, in camera-local
  /// space. Add trauma with [CameraShake.addTrauma]; the director advances
  /// the decay each frame.
  ///
  /// Shake is applied *after* blending and is never fed back into it, so a
  /// cut during a violent shake does not carry the displacement across.
  CameraShake? shake;

  /// Called when the live camera changes, with the outgoing and incoming
  /// cameras (either may be null). Fired at the *start* of a blend.
  void Function(CameraController? from, CameraController? to)? onCameraChanged;

  static const double _maxFrameSeconds = 0.1;

  final List<_Shot> _shots = <_Shot>[];

  CameraController? _live;
  CameraController? _fromCamera;
  CameraPose? _fromFrozen;
  CameraBlend _blend = const CameraBlend.cut();
  CameraBlend? _pendingBlend;
  CameraController? _selected;
  bool _hasSelection = false;
  double _elapsed = 0.0;
  CameraProjection? _ambientLens;

  CameraPose _basePose = CameraPose.identity;
  CameraPose _pose = CameraPose.identity;
  _DirectorInput? _input;

  /// The pose the director last wrote to its node, shake included.
  CameraPose get pose => _pose;

  /// The camera currently being shown (the blend's destination).
  CameraController? get activeCamera => _live;

  /// Every registered camera, in registration order.
  Iterable<CameraController> get cameras => _shots.map((shot) => shot.camera);

  /// Every registration, in order, with the priority and name [add] was given.
  ///
  /// [cameras] drops both, which is enough to drive a blend but not enough to
  /// write the shot list back out. Read this to serialize or inspect a
  /// director; change it through [add], [remove], and [setPriority].
  Iterable<({CameraController camera, double priority, String? name})>
  get registrations => _shots.map(
    (shot) => (camera: shot.camera, priority: shot.priority, name: shot.name),
  );

  /// Whether a blend is in progress.
  bool get isBlending => _fromCamera != null || _fromFrozen != null;

  /// How far the current blend has progressed, `0` to `1`. Reads `1` when
  /// nothing is blending.
  double get blendProgress {
    if (!isBlending) return 1.0;
    if (_blend.duration <= 0.0) return 1.0;
    return (_elapsed / _blend.duration).clamp(0.0, 1.0);
  }

  /// A controller that forwards every input hook to whichever camera is live,
  /// so one [CameraControls] wrapper keeps working as the shot changes:
  ///
  /// ```dart
  /// CameraControls(controller: director.input, child: SceneView(scene: scene))
  /// ```
  ///
  /// It is a forwarder, not a camera: do not register it with a director or
  /// attach it to a node.
  CameraController get input => _input ??= _DirectorInput(this);

  /// Registers [camera] at [priority], optionally under a [name] for
  /// [byName].
  ///
  /// The camera is advanced once immediately so its pose is valid to blend
  /// from or to on this very frame. Registering the first camera is always a
  /// cut, since there is nothing to blend from.
  void add(CameraController camera, {double priority = 0.0, String? name}) {
    assert(
      !_shots.any((shot) => identical(shot.camera, camera)),
      'That CameraController is already registered with this director.',
    );
    assert(
      camera is! _DirectorInput,
      'CameraDirector.input is an input forwarder, not a camera. Register the '
      'real controllers instead.',
    );
    camera.bindDirector(this);
    camera.warmUp();
    _shots.add(_Shot(camera, priority, name));
  }

  /// Removes [camera]. Returns whether it was registered.
  ///
  /// Removing the live camera hands over to whatever priority selects next,
  /// blending with [defaultBlend]. Removing the camera a blend is coming
  /// *from* freezes that side rather than snapping.
  bool remove(CameraController camera) {
    final index = _shots.indexWhere((shot) => identical(shot.camera, camera));
    if (index < 0) return false;
    _shots.removeAt(index);
    camera.bindDirector(null);
    if (identical(_fromCamera, camera)) {
      _fromFrozen = _basePose;
      _fromCamera = null;
    }
    if (identical(_selected, camera)) {
      _selected = null;
      _hasSelection = false;
    }
    return true;
  }

  /// Removes every camera. The node keeps whatever pose it last had.
  void clear() {
    for (final shot in _shots) {
      shot.camera.bindDirector(null);
    }
    _shots.clear();
    _selected = null;
    _hasSelection = false;
    _fromCamera = null;
    _fromFrozen = null;
    _live = null;
  }

  /// The camera registered under [name], or null.
  CameraController? byName(String name) {
    for (final shot in _shots) {
      if (shot.name == name) return shot.camera;
    }
    return null;
  }

  /// The priority [camera] was registered at, or null when it is not
  /// registered.
  double? priorityOf(CameraController camera) {
    for (final shot in _shots) {
      if (identical(shot.camera, camera)) return shot.priority;
    }
    return null;
  }

  /// Changes [camera]'s priority, optionally naming the [blend] to use if
  /// this hands the shot over.
  void setPriority(
    CameraController camera,
    double priority, {
    CameraBlend? blend,
  }) {
    for (final shot in _shots) {
      if (identical(shot.camera, camera)) {
        shot.priority = priority;
        if (blend != null) _pendingBlend = blend;
        return;
      }
    }
    assert(
      false,
      'That CameraController is not registered with this director.',
    );
  }

  /// Blends to [camera] over [duration] seconds, overriding priority until
  /// [clearSelection].
  ///
  /// Omitting [duration] and [curve] uses [defaultBlend].
  void blendTo(CameraController camera, {double? duration, Curve? curve}) {
    select(
      camera,
      blend: duration == null && curve == null
          ? null
          : CameraBlend(
              duration ?? defaultBlend.duration,
              curve: curve ?? defaultBlend.curve,
            ),
    );
  }

  /// Switches to [camera] instantly, overriding priority until
  /// [clearSelection].
  void cutTo(CameraController camera) =>
      select(camera, blend: const CameraBlend.cut());

  /// Selects [camera] explicitly, or passes control back to priority when
  /// [camera] is null (the same as [clearSelection]).
  ///
  /// A camera that is not registered yet is registered on the spot at a
  /// priority below every other camera, so a one-off cinematic shot needs
  /// only the one call: it shows while it is selected, and
  /// [clearSelection] hands back to whatever gameplay camera was running.
  void select(CameraController? camera, {CameraBlend? blend}) {
    if (camera != null &&
        !_shots.any((shot) => identical(shot.camera, camera))) {
      add(camera, priority: double.negativeInfinity);
    }
    _selected = camera;
    _hasSelection = camera != null;
    if (blend != null) _pendingBlend = blend;
  }

  /// Drops an explicit selection so priority decides again, blending with
  /// [blend] (or [defaultBlend]) into whichever camera takes over.
  void clearSelection({CameraBlend? blend}) => select(null, blend: blend);

  /// Finishes any blend in progress immediately, landing on the live camera.
  void snap() {
    _fromCamera = null;
    _fromFrozen = null;
    _elapsed = 0.0;
  }

  @override
  void update(double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, _maxFrameSeconds);

    // Every registered camera advances, live or not, so a camera that is
    // blended *to* arrives already tracking rather than snapping into place.
    for (final shot in _shots) {
      if (shot.camera.enabled) shot.camera.step(dt);
    }

    final desired = _resolveLive();
    if (!identical(desired, _live)) _beginTransition(desired);

    final live = _live;
    if (live == null) return;

    _basePose = _evaluateBlend(live, dt);
    _pose = _applyShake(_basePose, dt);
    _pose.applyTo(node);
    _applyLens(_pose.projection);
  }

  /// The camera priority selects: the explicit selection when there is one,
  /// otherwise the enabled camera with the highest priority (ties to the
  /// most recently added).
  CameraController? _resolveLive() {
    if (_hasSelection) {
      final selected = _selected;
      if (selected != null && selected.enabled) return selected;
    }
    _Shot? best;
    for (final shot in _shots) {
      if (!shot.camera.enabled) continue;
      if (best == null || shot.priority >= best.priority) best = shot;
    }
    return best?.camera;
  }

  void _beginTransition(CameraController? next) {
    final previous = _live;
    final blend = _pendingBlend ?? defaultBlend;
    _pendingBlend = null;

    if (previous == null || next == null || blend.isCut) {
      // Nothing to blend from (or an explicit cut): land immediately.
      _fromCamera = null;
      _fromFrozen = null;
    } else if (isBlending) {
      // Interrupting a blend. The outgoing side is a pose that belongs to no
      // single camera, so freeze it; anything else would snap back to the
      // camera we were already leaving.
      _fromFrozen = _basePose;
      _fromCamera = null;
    } else {
      // Blend live, so the outgoing camera keeps tracking its subject
      // throughout the transition.
      _fromCamera = previous;
      _fromFrozen = null;
    }
    _blend = blend;
    _elapsed = 0.0;
    _ambientLens = _cameraComponent?.projection;
    _live = next;
    onCameraChanged?.call(previous, next);
  }

  CameraPose _evaluateBlend(CameraController live, double dt) {
    final target = live.pose;
    final from = _fromFrozen ?? _fromCamera?.pose;
    if (from == null) return target;

    _elapsed += dt;
    final raw = _blend.duration <= 0.0
        ? 1.0
        : (_elapsed / _blend.duration).clamp(0.0, 1.0);
    if (raw >= 1.0) {
      _fromCamera = null;
      _fromFrozen = null;
      return target;
    }
    // Fill a missing lens on either side with the lens the camera already had
    // when the blend started, so "this shot does not drive the lens" reads as
    // "leave it where it is" rather than as a jump.
    final ambient = _ambientLens;
    final a = from.projection == null && ambient != null
        ? from.copyWith(projection: ambient)
        : from;
    final b = target.projection == null && ambient != null
        ? target.copyWith(projection: ambient)
        : target;
    return a.lerpTo(b, _blend.curve.transform(raw));
  }

  CameraPose _applyShake(CameraPose base, double dt) {
    final generator = shake;
    if (generator == null) return base;
    final offset = generator.update(dt);
    if (offset.translation.length2 < 1e-12 &&
        offset.rotationEuler.length2 < 1e-12) {
      return base;
    }
    final euler = offset.rotationEuler;
    return base
        .translatedLocal(offset.translation)
        .rotatedLocal(Quaternion.euler(euler.y, euler.x, euler.z));
  }

  CameraComponent? get _cameraComponent =>
      isAttached ? node.getComponent<CameraComponent>() : null;

  void _applyLens(CameraProjection? lens) {
    if (lens == null) return;
    final component = _cameraComponent;
    if (component == null) return;
    if (identical(component.projection, lens)) return;
    component.projection = lens;
  }

  @override
  void onDetach() {
    // The director no longer drives anything, so let its cameras go back to
    // driving their own nodes if they have them.
    for (final shot in _shots) {
      shot.camera.bindDirector(null);
    }
  }

  @override
  void onAttach() {
    for (final shot in _shots) {
      shot.camera.bindDirector(this);
    }
  }
}

class _Shot {
  _Shot(this.camera, this.priority, this.name);

  final CameraController camera;
  double priority;
  final String? name;
}

/// Forwards input to a director's live camera. Not a camera itself: it never
/// produces a pose and is never registered.
class _DirectorInput extends CameraController {
  _DirectorInput(this.director);

  final CameraDirector director;

  CameraController? get _target => director.activeCamera;

  @override
  set viewportSize(Size value) {
    super.viewportSize = value;
    // Every camera needs the view size, not just the live one: a camera
    // blended to mid-drag must already know how to scale pixel input.
    for (final camera in director.cameras) {
      camera.viewportSize = value;
    }
  }

  @override
  void handleDragUpdate(Offset delta) => _target?.handleDragUpdate(delta);

  @override
  void handleSecondaryDragUpdate(Offset delta) =>
      _target?.handleSecondaryDragUpdate(delta);

  @override
  void handleScaleUpdate(double scaleFactor, Offset focalDelta) =>
      _target?.handleScaleUpdate(scaleFactor, focalDelta);

  @override
  void handleScroll(double scrollDelta) => _target?.handleScroll(scrollDelta);

  @override
  bool handleKeyEvent(KeyEvent event) =>
      _target?.handleKeyEvent(event) ?? false;

  @override
  void releaseInput() {
    // Release everything, not just the live camera: a key held through a cut
    // would otherwise stick on the camera that was live when it went down.
    for (final camera in director.cameras) {
      camera.releaseInput();
    }
  }

  @override
  void update(double deltaSeconds) {}
}
