import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show ObjectKey;
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/semantics_component.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene.dart';

/// The nominal focus rectangle (logical pixels) for a semantics node whose
/// subtree has no computable bounds (skinned content without a
/// `SemanticsComponent.boundsOverride`), matching the platform minimum
/// touch-target convention.
const double _kUnboundedFocusExtent = 48.0;

/// One projected semantics element, compared across frames to decide when
/// the semantics tree needs a rebuild.
class _SemanticsEntry {
  _SemanticsEntry(
    this.component,
    this.rect,
    this.version,
    this.depth,
    this.readingOrder,
  );

  final SemanticsComponent component;
  final ui.Rect rect;
  final int version;

  /// Distance from the camera to the node's bounds center. Emitted children
  /// are ordered farthest-first (nearest last), so when projected rects
  /// overlap the nearest part wins the reversed hit test that assistive
  /// technology uses for touch exploration.
  final double depth;

  /// The component's registration index, used as a stable reading-order
  /// fallback so traversal order does not follow the depth-driven emission
  /// order.
  final double readingOrder;

  bool matches(_SemanticsEntry other) =>
      identical(component, other.component) &&
      version == other.version &&
      (rect.left - other.rect.left).abs() < 1e-3 &&
      (rect.top - other.rect.top).abs() < 1e-3 &&
      (rect.right - other.rect.right).abs() < 1e-3 &&
      (rect.bottom - other.rect.bottom).abs() < 1e-3;
}

/// Builds and maintains a `SceneView`'s semantics: one synthesized node per
/// mounted [SemanticsComponent] (its bounds projected through the primary
/// view's camera) plus per-frame geometry for each `WidgetComponent`'s
/// hosted subtree.
///
/// The owning view refreshes it from the scene painter after each rendered
/// frame, where the camera and node transforms are current. Everything is
/// gated on [SemanticsBinding.semanticsEnabled], so the projection work
/// costs nothing while no assistive technology runs. Changed snapshots
/// schedule a semantics update on the scene's render object via a
/// post-frame callback (marking during the paint flush is not allowed).
///
/// Not exported; `SceneView` is the only consumer.
class SceneSemanticsCoordinator {
  SceneSemanticsCoordinator(this.scene);

  final Scene scene;

  /// The scene's render object, managed by its attach/detach. Semantics
  /// updates are dropped while there is none.
  RenderObject? renderObject;

  /// The view's ambient reading direction, set by `SceneView` from its
  /// build context. Fills in components that carry text but no explicit
  /// direction.
  ui.TextDirection? ambientTextDirection;

  List<_SemanticsEntry> _entries = const [];
  bool _updateScheduled = false;

  /// Whether the last refresh ran with assistive technology active, so a
  /// flip to disabled clears the tree exactly once.
  bool _wasEnabled = false;

  /// The semantics builder handed to the scene painter. Reads the snapshot
  /// the last refresh produced; the framework calls it whenever the scene's
  /// semantics node is (re)assembled.
  List<CustomPainterSemantics> buildSemantics(ui.Size size) => [
    for (final entry in _entries)
      CustomPainterSemantics(
        key: ObjectKey(entry.component),
        rect: entry.rect,
        properties: entry.component.effectiveProperties(
          ambientTextDirection,
          fallbackSortOrder: entry.readingOrder,
        ),
      ),
  ];

  /// Recomputes the semantics snapshot against the primary view. Called by
  /// the scene painter after each rendered frame; [camera] is the primary
  /// view's camera (null when no view renders to the screen) and [viewArea]
  /// is the sub-rectangle of the scene's box that view draws into.
  void refreshAfterRender(Camera? camera, ui.Rect viewArea) {
    final enabled =
        SemanticsBinding.instance.semanticsEnabled &&
        camera != null &&
        !viewArea.isEmpty;
    if (!enabled) {
      if (_wasEnabled) {
        _wasEnabled = false;
        if (_entries.isNotEmpty) {
          _entries = const [];
          _scheduleSemanticsUpdate();
        }
        _refreshWidgetSurfaces(null, viewArea);
      }
      return;
    }
    _wasEnabled = true;

    final components = scene.renderScene.semanticsComponents;
    final entries = <_SemanticsEntry>[];
    for (var i = 0; i < components.length; i++) {
      final component = components[i];
      if (!component.enabled) continue;
      final node = component.node;
      if (!_chainVisible(node)) continue;
      final rect = _projectFocusRect(component, node, camera, viewArea);
      if (rect == null) continue;
      if (component.occlusionHiding &&
          _isNodeOccluded(
            node,
            camera,
            boundsOverride: component.boundsOverride,
          )) {
        continue;
      }
      entries.add(
        _SemanticsEntry(
          component,
          rect,
          component.version,
          _cameraDepth(component, node, camera),
          i.toDouble(),
        ),
      );
    }

    // Emit farthest-first so the nearest overlapping part wins the reversed
    // hit test; reading order stays put via each entry's readingOrder sort
    // key. A stable sort keeps registration order between equal depths.
    _mergeSortByDepthDescending(entries);

    if (!_entriesMatch(entries)) {
      _entries = entries;
      _scheduleSemanticsUpdate();
    }

    _refreshWidgetSurfaces(camera, viewArea);
  }

  // Distance from the camera to the node's bounds center (or origin when the
  // subtree is unbounded), the key for depth ordering.
  double _cameraDepth(SemanticsComponent component, Node node, Camera camera) {
    final bounds = component.boundsOverride ?? node.combinedLocalBounds;
    final vm.Vector3 center;
    if (bounds == null) {
      center = node.globalTransform.getTranslation();
    } else {
      final world = vm.Aabb3.copy(bounds)..transform(node.globalTransform);
      center = world.center;
    }
    return center.distanceTo(camera.position);
  }

  // A stable descending-by-depth sort. `List.sort` is not guaranteed stable,
  // and stability matters so equal-depth parts keep registration order (and
  // the emission order does not jitter frame to frame).
  static void _mergeSortByDepthDescending(List<_SemanticsEntry> entries) {
    if (entries.length < 2) return;
    final sorted = List<_SemanticsEntry>.of(entries);
    final buffer = List<_SemanticsEntry?>.filled(entries.length, null);
    for (var width = 1; width < sorted.length; width *= 2) {
      for (var lo = 0; lo < sorted.length; lo += width * 2) {
        final mid = (lo + width).clamp(0, sorted.length);
        final hi = (lo + width * 2).clamp(0, sorted.length);
        var i = lo, j = mid, k = lo;
        while (i < mid && j < hi) {
          // `>=` keeps the left (earlier) entry first on ties: stable.
          buffer[k++] = sorted[i].depth >= sorted[j].depth
              ? sorted[i++]
              : sorted[j++];
        }
        while (i < mid) {
          buffer[k++] = sorted[i++];
        }
        while (j < hi) {
          buffer[k++] = sorted[j++];
        }
      }
      for (var x = 0; x < sorted.length; x++) {
        sorted[x] = buffer[x]!;
      }
    }
    for (var x = 0; x < entries.length; x++) {
      entries[x] = sorted[x];
    }
  }

  bool _entriesMatch(List<_SemanticsEntry> entries) {
    if (entries.length != _entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (!entries[i].matches(_entries[i])) return false;
    }
    return true;
  }

  void _scheduleSemanticsUpdate() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      final ro = renderObject;
      if (ro != null && ro.attached) {
        ro.markNeedsSemanticsUpdate();
      }
    }, debugLabel: 'SceneView.semanticsUpdate');
  }

  static bool _chainVisible(Node node) {
    for (Node? current = node; current != null; current = current.parent) {
      if (!current.visible) return false;
    }
    return true;
  }

  /// Projects the component's focus bounds to a rectangle in the scene
  /// box's coordinates, or null when the node is entirely behind the
  /// camera.
  ui.Rect? _projectFocusRect(
    SemanticsComponent component,
    Node node,
    Camera camera,
    ui.Rect viewArea,
  ) {
    final bounds = component.boundsOverride ?? node.combinedLocalBounds;
    if (bounds == null) {
      // No computable bounds (skinned content without an override): a
      // nominal-size rectangle at the node origin keeps the element
      // focusable somewhere sensible.
      final screen = camera.worldToScreen(
        node.globalTransform.getTranslation(),
        viewArea.size,
      );
      if (screen == null) return null;
      return ui.Rect.fromCenter(
        center: screen + viewArea.topLeft,
        width: _kUnboundedFocusExtent,
        height: _kUnboundedFocusExtent,
      );
    }
    final world = vm.Aabb3.copy(bounds)..transform(node.globalTransform);
    return projectAabbToArea(world, camera, viewArea);
  }

  /// Whether other scene geometry sits between the camera and the node's
  /// bounds center. A single center-point sample, conservative and cheap;
  /// the node's own subtree never counts as an occluder.
  bool _isNodeOccluded(Node node, Camera camera, {vm.Aabb3? boundsOverride}) {
    final bounds = boundsOverride ?? node.combinedLocalBounds;
    final vm.Vector3 center;
    if (bounds == null) {
      center = node.globalTransform.getTranslation();
    } else {
      final world = vm.Aabb3.copy(bounds)..transform(node.globalTransform);
      center = world.center;
    }
    final origin = camera.position;
    final toCenter = center - origin;
    final distance = toCenter.length;
    if (distance <= 1e-6) return false;
    final hit = scene.raycast(
      vm.Ray.originDirection(origin, toCenter / distance),
      maxDistance: distance,
      where: (candidate) => !_inSubtree(candidate, node),
    );
    return hit != null && hit.distance < distance - 1e-4;
  }

  static bool _inSubtree(Node candidate, Node root) {
    for (Node? current = candidate; current != null; current = current.parent) {
      if (identical(current, root)) return true;
    }
    return false;
  }

  /// Pushes each widget surface's semantics geometry (or hides it) into its
  /// hosting render object. With a null [camera] every surface is hidden
  /// (assistive technology inactive, or no screen view this frame).
  void _refreshWidgetSurfaces(Camera? camera, ui.Rect viewArea) {
    for (final entry in scene.renderScene.widgetComponents) {
      if (entry is! WidgetComponent) continue;
      vm.Matrix4? transform;
      if (camera != null &&
          entry.enabled &&
          _chainVisible(entry.node) &&
          !(entry.occlusionHiding && _isNodeOccluded(entry.node, camera))) {
        transform = _widgetSurfaceTransform(entry, camera, viewArea);
      }
      // The render layer speaks Flutter's 64-bit matrices; convert at the
      // boundary (both are column-major).
      entry.controller.internalUpdateSemantics(
        transform == null ? null : Matrix4.fromList(transform.storage),
      );
    }
  }

  /// The transform mapping the hosted subtree's logical coordinates onto
  /// the scene box, or null when the surface has no usable on-screen
  /// placement this frame.
  vm.Matrix4? _widgetSurfaceTransform(
    WidgetComponent component,
    Camera camera,
    ui.Rect viewArea,
  ) {
    final node = component.node;
    if (component.ownsQuadSurface) {
      return _quadSurfaceTransform(component, node, camera, viewArea);
    }
    // Custom geometry or bind-only surfaces have no single plane to map
    // exactly; fit the widget rectangle onto the projected node bounds.
    // TODO(scene-semantics): exact per-surface mapping for custom widget
    // geometry (project through the surface's UV parameterization instead
    // of its AABB).
    final bounds = node.combinedLocalBounds;
    if (bounds == null) return null;
    final world = vm.Aabb3.copy(bounds)..transform(node.globalTransform);
    final rect = projectAabbToArea(world, camera, viewArea);
    if (rect == null || rect.isEmpty) return null;
    final size = component.size;
    return vm.Matrix4.identity()
      ..setEntry(0, 0, rect.width / size.width)
      ..setEntry(1, 1, rect.height / size.height)
      ..setEntry(0, 3, rect.left)
      ..setEntry(1, 3, rect.top);
  }

  /// The exact projective transform for a component-owned quad surface:
  /// widget logical space onto the quad's local plane, through the node's
  /// world transform and the camera, into scene-box coordinates.
  vm.Matrix4? _quadSurfaceTransform(
    WidgetComponent component,
    Node node,
    Camera camera,
    ui.Rect viewArea,
  ) {
    final size = component.size;
    final quadHeight = component.worldHeight;
    final quadWidth = quadHeight * (size.width / size.height);

    // Widget space (origin top-left, y down) onto the quad's local plane.
    // The quad's UVs mirror u across x and run v top-down (see
    // WidgetComponent's quad geometry), so widget (0, 0) lands on the local
    // (+halfWidth, +halfHeight) corner.
    final localFromWidget = vm.Matrix4.identity()
      ..setEntry(0, 0, -quadWidth / size.width)
      ..setEntry(0, 3, quadWidth / 2)
      ..setEntry(1, 1, -quadHeight / size.height)
      ..setEntry(1, 3, quadHeight / 2);

    final clipFromWidget = camera
        .getViewTransform(viewArea.size)
        .multiplied(node.globalTransform)
        .multiplied(localFromWidget);

    // Reject the mapping when any widget corner reaches the camera plane;
    // the homography is degenerate there and the surface is unreadable
    // anyway.
    for (final corner in [
      vm.Vector4(0, 0, 0, 1),
      vm.Vector4(size.width, 0, 0, 1),
      vm.Vector4(0, size.height, 0, 1),
      vm.Vector4(size.width, size.height, 0, 1),
    ]) {
      final clip = clipFromWidget.transform(corner);
      if (clip.w <= 0) return null;
    }

    // Homogeneous clip-to-screen: the perspective divide is deferred to the
    // consumers of the semantics transform chain, which handle full
    // projective matrices.
    final screenFromClip = vm.Matrix4.identity()
      ..setEntry(0, 0, viewArea.width / 2)
      ..setEntry(0, 3, viewArea.width / 2 + viewArea.left)
      ..setEntry(1, 1, -viewArea.height / 2)
      ..setEntry(1, 3, viewArea.height / 2 + viewArea.top);

    return screenFromClip.multiplied(clipFromWidget);
  }
}

/// Projects a world-space AABB through [camera] into [viewArea] (a
/// sub-rectangle of the scene box, in its coordinates) and returns the
/// bounding rectangle of the eight projected corners.
///
/// Returns null when the box is entirely behind the camera plane. When the
/// box crosses the camera plane its projection is unbounded, so the whole
/// [viewArea] is returned as the conservative answer.
ui.Rect? projectAabbToArea(vm.Aabb3 world, Camera camera, ui.Rect viewArea) {
  final viewSize = viewArea.size;
  final viewProjection = camera.getViewTransform(viewSize);
  final min = world.min;
  final max = world.max;
  var anyBehind = false;
  var anyInFront = false;
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (var i = 0; i < 8; i++) {
    final corner = vm.Vector4(
      (i & 1) == 0 ? min.x : max.x,
      (i & 2) == 0 ? min.y : max.y,
      (i & 4) == 0 ? min.z : max.z,
      1,
    );
    final clip = viewProjection.transform(corner);
    if (clip.w <= 0) {
      anyBehind = true;
      continue;
    }
    anyInFront = true;
    final x = (clip.x / clip.w + 1) / 2 * viewSize.width;
    final y = (1 - clip.y / clip.w) / 2 * viewSize.height;
    if (x < left) left = x;
    if (y < top) top = y;
    if (x > right) right = x;
    if (y > bottom) bottom = y;
  }
  if (!anyInFront) return null;
  if (anyBehind) return viewArea;
  return ui.Rect.fromLTRB(
    left + viewArea.left,
    top + viewArea.top,
    right + viewArea.left,
    bottom + viewArea.top,
  );
}
