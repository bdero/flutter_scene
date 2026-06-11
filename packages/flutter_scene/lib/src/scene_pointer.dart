import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:vector_math/vector_math.dart' show Ray;

/// A programmatic pointer into a scene: a crosshair, a gamepad-driven
/// cursor, a VR laser, or the built-in pointer behind automatic widget
/// input.
///
/// The caller decides where the ray comes from ([pointAt] from a screen
/// position, or [pointAlong] for an arbitrary ray); the pointer owns
/// everything downstream: the raycast, widget-surface UV mapping, event
/// forwarding, capture, and hover state. Several pointers coexist, each
/// with independent capture and hover.
///
/// Filtering has two distinct axes:
///
///  * [layerMask] / [where] / [maxDistance] control what the ray HITS (the
///    occlusion set). Defaults hit everything raycastable, so blocking is
///    physically correct out of the box; a wall in front of a panel stops
///    the pointer.
///  * [interactionMask] controls which widget surfaces this pointer may
///    DRIVE. Events forward only when the nearest hit's node carries a
///    [WidgetComponent] and intersects this mask.
///
/// While pressed, the interaction is captured: moves and the release route
/// to the pressed surface even when the ray slides off it (other geometry
/// is ignored until [release]), the standard pointer-capture semantics that
/// keep drags alive at surface edges.
///
/// Hover ([hit], [hoveredWidget], [hoverChanged]) is query state for the
/// caller (crosshair highlights, cursor feedback); it is not forwarded into
/// the widgets (widget-level hover needs MouseTracker integration, a
/// planned follow-up).
/// {@category Picking and input}
class ScenePointer {
  /// Creates a pointer into [scene].
  ScenePointer(
    this.scene, {
    this.layerMask = 0xFFFFFFFF,
    this.interactionMask = 0xFFFFFFFF,
    this.where,
    this.maxDistance = double.infinity,
  });

  /// The scene this pointer casts into.
  final Scene scene;

  /// The occlusion set: layers the ray tests (against [Node.layers]).
  int layerMask;

  /// Which widget surfaces this pointer may drive (against [Node.layers]).
  int interactionMask;

  /// Optional occlusion predicate (exclude the player model, etc.).
  bool Function(Node node)? where;

  /// The pointer's reach, world units.
  double maxDistance;

  static int _nextPointerId = 1;

  /// This pointer's id within each widget surface's forwarding state;
  /// distinct per [ScenePointer] so concurrent pointers never share
  /// capture.
  final int pointerId = _nextPointerId++;

  SceneRaycastHit? _hit;
  WidgetComponent? _hovered;
  WidgetComponent? _captured;
  Offset _lastUv = Offset.zero;
  Offset? _pressUv;
  double _pressTravel = 0.0;

  /// Notifies when [hoveredWidget] changes.
  final ChangeNotifier hoverChanged = _HoverNotifier();

  /// The latest raycast hit (from the occlusion set), or null when the ray
  /// misses everything in range.
  SceneRaycastHit? get hit => _hit;

  /// The widget component the pointer is over (nearest hit, interaction
  /// mask passed), or null. While pressed this stays the captured surface.
  WidgetComponent? get hoveredWidget => _captured ?? _hovered;

  /// Whether a press is in progress.
  bool get isPressed => _captured != null;

  /// UV-space distance traveled between the last press and now (or the
  /// release), for click-versus-drag discrimination.
  double get pressTravel => _pressTravel;

  /// Points along the ray leaving [camera] through [screenPosition] inside
  /// a view of [viewSize] logical pixels.
  void pointAt(
    Offset screenPosition, {
    required Camera camera,
    required Size viewSize,
  }) => pointAlong(camera.screenPointToRay(screenPosition, viewSize));

  /// Points along [ray] (world space; direction need not be normalized).
  void pointAlong(Ray ray) {
    final captured = _captured;
    if (captured != null) {
      // Captured: route to the pressed surface regardless of occluders.
      // When the ray leaves the surface entirely, hold the last UV so the
      // interaction stays stable at the edge.
      final node = captured.isAttached ? captured.node : null;
      if (node == null) {
        cancel();
        return;
      }
      final hit = raycastNode(
        node,
        ray,
        includeInvisible: true,
        layerMask: 0xFFFFFFFF,
      );
      if (hit?.uv != null) {
        _lastUv = Offset(hit!.uv!.x, hit.uv!.y);
      }
      final pressUv = _pressUv;
      if (pressUv != null) {
        _pressTravel = (_lastUv - pressUv).distance;
      }
      captured.controller.pointerMove(_lastUv, pointer: pointerId);
      _hit = hit;
      return;
    }

    final hit = scene.raycast(
      ray,
      maxDistance: maxDistance,
      layerMask: layerMask,
      where: where,
    );
    _hit = hit;
    WidgetComponent? hovered;
    if (hit != null && (hit.node.layers & interactionMask) != 0) {
      hovered = hit.node.getComponent<WidgetComponent>();
      if (hit.uv != null) {
        _lastUv = Offset(hit.uv!.x, hit.uv!.y);
      }
    }
    if (!identical(hovered, _hovered)) {
      _hovered = hovered;
      (hoverChanged as _HoverNotifier).fire();
    }
  }

  /// Presses at the current pointer location. Forwards a pointer-down when
  /// the pointer is over a widget surface; otherwise the press is blocked
  /// (it landed on world geometry or empty space).
  void press() {
    if (_captured != null) return;
    final target = _hovered;
    if (target == null) return;
    _captured = target;
    _pressUv = _lastUv;
    _pressTravel = 0.0;
    target.controller.pointerDown(_lastUv, pointer: pointerId);
  }

  /// Releases the current press at the pointer's location.
  void release() {
    final captured = _captured;
    if (captured == null) return;
    _captured = null;
    _pressUv = null;
    captured.controller.pointerUp(_lastUv, pointer: pointerId);
  }

  /// Cancels the current press without completing it.
  void cancel() {
    final captured = _captured;
    if (captured == null) return;
    _captured = null;
    _pressUv = null;
    captured.controller.pointerCancel(pointer: pointerId);
  }

  /// Scrolls at the pointer's location by [scrollDelta] logical pixels,
  /// driving scrollables in the hovered widget surface.
  void scroll(Offset scrollDelta) {
    final target = hoveredWidget;
    if (target == null) return;
    target.controller.pointerScroll(_lastUv, scrollDelta);
  }
}

class _HoverNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}
