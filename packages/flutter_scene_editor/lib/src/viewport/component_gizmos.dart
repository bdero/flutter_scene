/// The component gizmo layer: interprets the declarative [GizmoSpec] blocks
/// component schemas carry into viewport overlay drawing and screen-space
/// picking, for live builtin components and schema-only foreign components
/// alike.
///
/// Bindings evaluate per paint against a serialize snapshot of each
/// component (the same property values the inspector edits), so gizmos track
/// inspector edits, slider previews, and transform drags with no sync
/// machinery.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:scene/scene.dart' as doc;
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import 'transform_gizmo.dart' show projectToScreen;

/// The selection accent, matching the engine-side outline highlight color.
const Color _accentColor = Color(0xFFFF8C1A);

/// The muted default gizmo color.
const Color _baseColor = Color(0xCCB9C4CE);

/// Screen size (pixels) one world unit of decorative gizmo geometry (arrows,
/// literal line art) targets, before the primitive's own scalar applies.
const double _decorativePixels = 44.0;

/// Shared gizmo visibility preferences: the master toggle plus per-type
/// hides. Listenable so every viewport tracks menu changes and the host app
/// persists them with the editor settings.
class GizmoPreferences extends ChangeNotifier {
  bool _enabled = true;
  final Set<String> _hiddenTypes = {};

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  /// The component types whose gizmos are hidden (independent of [enabled]).
  Set<String> get hiddenTypes => Set.unmodifiable(_hiddenTypes);

  /// Whether gizmos for [type] currently draw.
  bool isTypeVisible(String type) => _enabled && !_hiddenTypes.contains(type);

  void setTypeHidden(String type, bool hidden) {
    final changed = hidden ? _hiddenTypes.add(type) : _hiddenTypes.remove(type);
    if (changed) notifyListeners();
  }

  /// Seeds from persisted settings without notifying.
  void load({required bool enabled, required Iterable<String> hiddenTypes}) {
    _enabled = enabled;
    _hiddenTypes
      ..clear()
      ..addAll(hiddenTypes);
  }
}

/// Screen geometry the painter produced this frame, tested by the viewport's
/// click-to-select path so picking matches exactly what was drawn.
class ComponentGizmoHitCache {
  final List<_PickEntry> _entries = [];

  static const double _wireSlop = 8.0;
  static const double _iconSlop = 4.0;

  void clear() => _entries.clear();

  void addDisc(doc.LocalId id, Offset center, double radius, double depth) =>
      _entries.add(_PickEntry.disc(id, center, radius, depth));

  void addSegments(
    doc.LocalId id,
    List<(Offset, Offset)> segments,
    double depth,
  ) {
    if (segments.isEmpty) return;
    _entries.add(_PickEntry.segments(id, segments, depth));
  }

  /// The owning node of the nearest gizmo geometry within picking slop of
  /// [position], or null. Nearest wins by screen distance; camera distance
  /// breaks ties.
  doc.LocalId? hitTest(Offset position) {
    doc.LocalId? best;
    var bestScore = double.infinity;
    var bestDepth = double.infinity;
    for (final entry in _entries) {
      final score = entry.score(position);
      if (score == null) continue;
      if (score < bestScore ||
          (score == bestScore && entry.depth < bestDepth)) {
        best = entry.id;
        bestScore = score;
        bestDepth = entry.depth;
      }
    }
    return best;
  }
}

class _PickEntry {
  _PickEntry.disc(this.id, Offset this.center, this.radius, this.depth)
    : segments = null;
  _PickEntry.segments(this.id, List<(Offset, Offset)> this.segments, this.depth)
    : center = null,
      radius = 0;

  final doc.LocalId id;
  final Offset? center;
  final double radius;
  final List<(Offset, Offset)>? segments;
  final double depth;

  /// Screen-distance score when [position] is within slop, else null.
  double? score(Offset position) {
    final center = this.center;
    if (center != null) {
      final distance = (position - center).distance;
      if (distance > radius + ComponentGizmoHitCache._iconSlop) return null;
      return math.max(0, distance - radius);
    }
    var best = double.infinity;
    for (final (a, b) in segments!) {
      final distance = _distToSegment(position, a, b);
      if (distance < best) best = distance;
    }
    return best <= ComponentGizmoHitCache._wireSlop ? best : null;
  }
}

double _distToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-6) return (point - a).distance;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (point - (a + Offset(ab.dx * t, ab.dy * t))).distance;
}

/// The editor's named component glyph set, shared by the viewport gizmos and
/// the component picker. A schema icon that is not a known name renders as
/// text (an emoji hint), so foreign components still get a presence.
IconData? componentGlyph(String? name) => switch (name) {
  'light-sun' => Icons.wb_sunny_outlined,
  'light-point' => Icons.lightbulb_outline,
  'light-spot' => Icons.highlight,
  'light-area' => Icons.wb_iridescent_outlined,
  'camera' => Icons.videocam_outlined,
  'audio' => Icons.volume_up_outlined,
  'audio-listener' => Icons.hearing_outlined,
  'environment' => Icons.blur_on_outlined,
  'particles' => Icons.grain,
  'physics' => Icons.animation_outlined,
  'light' => Icons.light_mode_outlined,
  'path' => Icons.route_outlined,
  'grid' => Icons.grid_on_outlined,
  'animator' => Icons.account_tree_outlined,
  'scatter' => Icons.forest_outlined,
  'component' => Icons.settings_input_component_outlined,
  _ => null,
};

/// Cross-repaint state for the gizmo painter: component serialize snapshots
/// (collider codecs run their full shape encoding, so re-serializing every
/// orbit-drag repaint is real cost) and laid-out icon text. Owned by the
/// viewport state; snapshots invalidate on document or preview changes and
/// survive pure camera movement.
class ComponentGizmoRenderCache {
  final Map<Component, Map<String, doc.PropertyValue>> _snapshots = {};
  final Map<(String, int, double), TextPainter> _iconText = {};

  /// Drops the property snapshots (a commit or preview changed component
  /// state). Laid-out icon text is content-keyed and stays.
  void invalidate() => _snapshots.clear();

  Map<String, doc.PropertyValue> _propertiesFor(
    Component component,
    ComponentCodec codec,
    SerializeContext scratch,
  ) => _snapshots[component] ??=
      codec.serialize(component, scratch)?.properties ?? const {};

  TextPainter _textFor(String text, TextStyle style, Color color, double size) {
    return _iconText[(text, color.toARGB32(), size)] ??= TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
  }
}

/// Paints every visible component gizmo and fills [hits] with the projected
/// geometry for click-to-select. One painter per viewport, re-run on view
/// epoch bumps (exactly like the transform gizmo and environment-volume
/// overlays). Wire strokes batch into one path per color/width and icons
/// draw last (on top of wires), so a repaint issues a handful of draw calls
/// rather than one per segment.
class ComponentGizmoPainter extends CustomPainter {
  ComponentGizmoPainter({
    required this.controller,
    required this.camera,
    required this.preferences,
    required this.hits,
    required this.cache,
  });

  final EditorController controller;
  final Camera camera;
  final GizmoPreferences preferences;
  final ComponentGizmoHitCache hits;
  final ComponentGizmoRenderCache cache;

  late Size _size;
  late Canvas _canvas;
  late SerializeContext _scratch;
  late vm.Matrix4 _viewProjection;

  // Batched geometry for this paint: stroked segments per (color, width),
  // filled arrow heads per color, icons deferred to draw above the wires.
  final Map<(int, double), Path> _strokes = {};
  final Map<int, Path> _fills = {};
  final List<(GizmoIcon, ComponentCodec, Offset, Color, bool)> _icons = [];

  static const double _wireWidth = 1.5;
  static const double _arrowWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    if (!preferences.enabled) return;
    _canvas = canvas;
    _size = size;
    _viewProjection = camera.getViewTransform(size);
    _strokes.clear();
    _fills.clear();
    _icons.clear();
    // Serialize snapshots write scratch resources (collider payloads, copied
    // environment refs) into a throwaway document, discarded per paint.
    _scratch = SerializeContext(doc.SceneDocument());
    _visit(controller.scene.root);
    for (final entry in _strokes.entries) {
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = Color(entry.key.$1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = entry.key.$2
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final entry in _fills.entries) {
      canvas.drawPath(entry.value, Paint()..color = Color(entry.key));
    }
    for (final (primitive, codec, center, color, selected) in _icons) {
      _paintIcon(primitive, codec, center, color, selected);
    }
  }

  void _addStroke(Offset a, Offset b, Color color, double width) {
    (_strokes[(color.toARGB32(), width)] ??= Path())
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
  }

  void _visit(Node node) {
    for (final component in node.getComponents<Component>()) {
      if (!component.enabled) continue;
      final codec = controller.codecForLiveComponent(component);
      final gizmo = codec?.schema.gizmo;
      if (codec == null || gizmo == null) continue;
      if (!preferences.isTypeVisible(codec.schema.type)) continue;
      _draw(node, component, codec, gizmo);
    }
    for (final child in node.children) {
      _visit(child);
    }
  }

  void _draw(
    Node node,
    Component component,
    ComponentCodec codec,
    GizmoSpec gizmo,
  ) {
    final sourceId = controller.sourceIdForLiveNode(node);
    final selected =
        sourceId != null && controller.selection.contains(sourceId);
    final snapshot = _Snapshot(
      codec,
      cache._propertiesFor(component, codec, _scratch),
    );
    final transform = node.globalTransform;
    final origin = transform.getTranslation();
    final originScreen = projectToScreen(origin, camera, _size);
    final depth = (camera.position - origin).length;
    // Normalized rotation frame for decorative primitives (scale stripped),
    // sized so one unit spans a constant screen length.
    final decorativeScale = _decorativeWorldScale(origin, originScreen);
    final basis = [
      for (var axis = 0; axis < 3; axis++) _normalizedAxis(transform, axis),
    ];

    final segments = <(Offset, Offset)>[];
    for (final primitive in gizmo.primitives) {
      if (primitive.visibility == GizmoVisibility.selected && !selected) {
        continue;
      }
      final when = primitive.when;
      if (when != null && !snapshot.matches(when)) continue;
      final color = _colorOf(primitive, selected, snapshot);
      switch (primitive) {
        case GizmoIcon():
          if (originScreen != null && sourceId != null) {
            _icons.add((primitive, codec, originScreen, color, selected));
            hits.addDisc(sourceId, originScreen, primitive.size / 2, depth);
          }
        case GizmoArrow():
          final length = snapshot.scalar(primitive.length);
          if (length == null || originScreen == null) break;
          final direction = _boundAxis(
            snapshot,
            basis,
            primitive.axisBind,
            primitive.axis,
          );
          if (direction == null) break;
          _drawArrow(
            origin,
            direction,
            length * decorativeScale,
            originScreen,
            color,
            segments,
          );
        case GizmoLines():
          final points = primitive.points;
          for (var i = 0; i + 5 < points.length; i += 6) {
            final a =
                origin +
                _frameVector(
                  basis,
                  points[i],
                  points[i + 1],
                  points[i + 2],
                ).scaled(decorativeScale);
            final b =
                origin +
                _frameVector(
                  basis,
                  points[i + 3],
                  points[i + 4],
                  points[i + 5],
                ).scaled(decorativeScale);
            _strokeWorldSegment(a, b, color, segments);
          }
        case GizmoWireSphere():
          final radius = _inflated(
            snapshot.scalar(primitive.radius),
            snapshot.scalar(primitive.inflate),
          );
          if (radius == null || radius <= 0) break;
          final center = _listVector(primitive.center);
          for (var axis = 0; axis < 3; axis++) {
            final (u, v) = _axisPlane(axis);
            _strokeLocalCircle(
              transform,
              center,
              u,
              v,
              radius,
              color,
              segments,
            );
          }
        case GizmoWireBox():
          vm.Vector3? half = primitive.halfExtentsBind != null
              ? snapshot.vector(primitive.halfExtentsBind!)
              : _listVector(primitive.halfExtents ?? const [0.5, 0.5, 0.5]);
          if (half == null) break;
          final inflate = snapshot.scalar(primitive.inflate);
          if (inflate == null) break;
          half = half + vm.Vector3.all(inflate);
          _strokeLocalBox(
            transform,
            _listVector(primitive.center),
            half,
            color,
            segments,
          );
        case GizmoWireRect():
          final width = snapshot.scalar(primitive.width);
          final height = snapshot.scalar(primitive.height);
          if (width == null || height == null) break;
          final normal = _listVector(primitive.axis)..normalize();
          final (u, v) = _perpendicular(normal);
          final corners = [
            u * (width / 2) + v * (height / 2),
            u * (-width / 2) + v * (height / 2),
            u * (-width / 2) + v * (-height / 2),
            u * (width / 2) + v * (-height / 2),
          ];
          for (var i = 0; i < 4; i++) {
            _strokeWorldSegment(
              transform.transformed3(corners[i]),
              transform.transformed3(corners[(i + 1) % 4]),
              color,
              segments,
            );
          }
        case GizmoWireCircle():
          final radius = snapshot.scalar(primitive.radius);
          if (radius == null || radius <= 0) break;
          final normal = _listVector(primitive.axis)..normalize();
          final (u, v) = _perpendicular(normal);
          _strokeLocalCircle(
            transform,
            vm.Vector3.zero(),
            u,
            v,
            radius,
            color,
            segments,
          );
        case GizmoWireCone():
          final angle = snapshot.scalar(primitive.angle);
          var range = snapshot.scalar(primitive.range);
          if (angle == null || range == null) break;
          // Unranged (infinite) cones draw a representative reach.
          if (range <= 0) range = decorativeScale * 3;
          var axis = _listVector(primitive.axis);
          if (primitive.axisBind != null) {
            axis = snapshot.vector(primitive.axisBind!) ?? axis;
          }
          if (axis.length2 < 1e-12) break;
          axis.normalize();
          final (u, v) = _perpendicular(axis);
          final radius = math.tan(angle.clamp(0, math.pi / 2 - 0.01)) * range;
          final base = axis * range;
          _strokeLocalCircle(transform, base, u, v, radius, color, segments);
          for (final spoke in [u, -u, v, -v]) {
            _strokeWorldSegment(
              transform.transformed3(vm.Vector3.zero()),
              transform.transformed3(base + spoke * radius),
              color,
              segments,
            );
          }
        case GizmoWireCapsule():
          final radius = snapshot.scalar(primitive.radius);
          final halfHeight = snapshot.scalar(primitive.halfHeight);
          if (radius == null || halfHeight == null || radius <= 0) break;
          final axis = _listVector(primitive.axis)..normalize();
          final (u, v) = _perpendicular(axis);
          final top = axis * halfHeight;
          _strokeLocalCircle(transform, top, u, v, radius, color, segments);
          _strokeLocalCircle(transform, -top, u, v, radius, color, segments);
          for (final side in [u, -u, v, -v]) {
            _strokeWorldSegment(
              transform.transformed3(top + side * radius),
              transform.transformed3(-top + side * radius),
              color,
              segments,
            );
          }
          // Hemispherical cap arcs in the two axis planes.
          for (final side in [u, v]) {
            _strokeLocalArc(
              transform,
              top,
              side,
              axis,
              radius,
              color,
              segments,
            );
            _strokeLocalArc(
              transform,
              -top,
              side,
              -axis,
              radius,
              color,
              segments,
            );
          }
        case GizmoWireCylinder():
          final radius = snapshot.scalar(primitive.radius);
          final halfHeight = snapshot.scalar(primitive.halfHeight);
          if (radius == null || halfHeight == null || radius <= 0) break;
          final axis = _listVector(primitive.axis)..normalize();
          final (u, v) = _perpendicular(axis);
          final top = axis * halfHeight;
          _strokeLocalCircle(transform, top, u, v, radius, color, segments);
          _strokeLocalCircle(transform, -top, u, v, radius, color, segments);
          for (final side in [u, -u, v, -v]) {
            _strokeWorldSegment(
              transform.transformed3(top + side * radius),
              transform.transformed3(-top + side * radius),
              color,
              segments,
            );
          }
        case GizmoFrustum():
          final fovY = snapshot.scalar(primitive.fovY);
          final near = snapshot.scalar(primitive.near);
          final far = snapshot.scalar(primitive.far);
          if (fovY == null || near == null || far == null) break;
          final aspect = primitive.aspect == null
              ? (_size.height > 0 ? _size.width / _size.height : 1.0)
              : snapshot.scalar(primitive.aspect!);
          if (aspect == null) break;
          _strokeFrustum(
            origin,
            basis,
            fovY,
            near,
            far,
            aspect,
            color,
            segments,
          );
      }
    }
    if (sourceId != null) hits.addSegments(sourceId, segments, depth);
  }

  // --- primitive helpers ---------------------------------------------------

  void _paintIcon(
    GizmoIcon primitive,
    ComponentCodec codec,
    Offset center,
    Color color,
    bool selected,
  ) {
    final size = primitive.size;
    _canvas.drawCircle(
      center,
      size / 2,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    if (selected) {
      _canvas.drawCircle(
        center,
        size / 2 + 1.5,
        Paint()
          ..color = _accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final name = primitive.glyph ?? codec.schema.icon;
    final glyph = componentGlyph(name);
    final String text;
    final TextStyle style;
    if (glyph != null) {
      text = String.fromCharCode(glyph.codePoint);
      style = TextStyle(
        fontFamily: glyph.fontFamily,
        package: glyph.fontPackage,
        fontSize: size * 0.68,
        color: color,
      );
    } else if (name != null && name.isNotEmpty) {
      text = name;
      style = TextStyle(fontSize: size * 0.58);
    } else {
      text = String.fromCharCode(Icons.circle_outlined.codePoint);
      style = TextStyle(
        fontFamily: Icons.circle_outlined.fontFamily,
        fontSize: size * 0.6,
        color: color,
      );
    }
    final painter = cache._textFor(text, style, color, size);
    painter.paint(
      _canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _drawArrow(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double length,
    Offset originScreen,
    Color color,
    List<(Offset, Offset)> segments,
  ) {
    final tipWorld = origin + direction * length;
    final tip = projectToScreen(tipWorld, camera, _size);
    if (tip == null) return;
    _addStroke(originScreen, tip, color, _arrowWidth);
    segments.add((originScreen, tip));
    final dir = tip - originScreen;
    final len = dir.distance;
    if (len < 1e-3) return;
    final norm = dir / len;
    final perp = Offset(-norm.dy, norm.dx);
    final base = tip - norm * math.min(10, len * 0.3);
    (_fills[color.toARGB32()] ??= Path())
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + perp.dx * 3.5, base.dy + perp.dy * 3.5)
      ..lineTo(base.dx - perp.dx * 3.5, base.dy - perp.dy * 3.5)
      ..close();
  }

  // Batches a world-space segment for stroking, clipping against the
  // camera's eye plane so a segment reaching behind the camera draws its
  // visible part instead of vanishing (frustum far corners, large boxes up
  // close).
  // TODO(gizmo-xray): GizmoPrimitive.xray is carried through the schema but
  // not honored here; the v1 painter draws everything on top. It applies
  // once depth-aware drawing exists (the custom-pass upgrade path).
  void _strokeWorldSegment(
    vm.Vector3 a,
    vm.Vector3 b,
    Color color,
    List<(Offset, Offset)> segments,
  ) {
    var clipA = _clipOf(a);
    var clipB = _clipOf(b);
    const nearW = 0.01;
    if (clipA.w <= nearW && clipB.w <= nearW) return;
    if (clipA.w <= nearW || clipB.w <= nearW) {
      final t = (nearW - clipA.w) / (clipB.w - clipA.w);
      final clipped = vm.Vector4(
        clipA.x + (clipB.x - clipA.x) * t,
        clipA.y + (clipB.y - clipA.y) * t,
        clipA.z + (clipB.z - clipA.z) * t,
        nearW,
      );
      if (clipA.w <= nearW) {
        clipA = clipped;
      } else {
        clipB = clipped;
      }
    }
    final sa = _screenOf(clipA);
    final sb = _screenOf(clipB);
    _addStroke(sa, sb, color, _wireWidth);
    segments.add((sa, sb));
  }

  vm.Vector4 _clipOf(vm.Vector3 point) =>
      _viewProjection.transform(vm.Vector4(point.x, point.y, point.z, 1));

  Offset _screenOf(vm.Vector4 clip) => Offset(
    (clip.x / clip.w * 0.5 + 0.5) * _size.width,
    (1 - (clip.y / clip.w * 0.5 + 0.5)) * _size.height,
  );

  void _strokeLocalCircle(
    vm.Matrix4 transform,
    vm.Vector3 center,
    vm.Vector3 u,
    vm.Vector3 v,
    double radius,
    Color color,
    List<(Offset, Offset)> segments,
  ) {
    const steps = 40;
    vm.Vector3? previous;
    for (var i = 0; i <= steps; i++) {
      final angle = i / steps * 2 * math.pi;
      final point = transform.transformed3(
        center +
            u * (math.cos(angle) * radius) +
            v * (math.sin(angle) * radius),
      );
      if (previous != null) {
        _strokeWorldSegment(previous, point, color, segments);
      }
      previous = point;
    }
  }

  /// A semicircular arc in the plane of [side] and [bulge], from `center +
  /// side*radius` through `center + bulge*radius` to `center - side*radius`.
  void _strokeLocalArc(
    vm.Matrix4 transform,
    vm.Vector3 center,
    vm.Vector3 side,
    vm.Vector3 bulge,
    double radius,
    Color color,
    List<(Offset, Offset)> segments,
  ) {
    const steps = 20;
    vm.Vector3? previous;
    for (var i = 0; i <= steps; i++) {
      final angle = i / steps * math.pi;
      final point = transform.transformed3(
        center +
            side * (math.cos(angle) * radius) +
            bulge * (math.sin(angle) * radius),
      );
      if (previous != null) {
        _strokeWorldSegment(previous, point, color, segments);
      }
      previous = point;
    }
  }

  // --- math helpers --------------------------------------------------------

  double _decorativeWorldScale(vm.Vector3 origin, Offset? originScreen) {
    if (originScreen == null) return 0;
    // Pixels one world unit spans at the origin: sample all three axes and
    // take the largest usable projection (handles orthographic cameras too).
    var pixelsPerUnit = 0.0;
    for (var axis = 0; axis < 3; axis++) {
      final probe = vm.Vector3.zero()..[axis] = 1;
      final projected = projectToScreen(origin + probe, camera, _size);
      if (projected == null) continue;
      final distance = (projected - originScreen).distance;
      if (distance > pixelsPerUnit) pixelsPerUnit = distance;
    }
    if (pixelsPerUnit < 1e-3) return 0;
    return _decorativePixels / pixelsPerUnit;
  }

  Color _colorOf(GizmoPrimitive primitive, bool selected, _Snapshot snapshot) {
    if (selected && primitive is! GizmoIcon) return _accentColor;
    final color = primitive.color;
    if (color == null) return _baseColor;
    final bind = color.bind;
    if (bind == null) {
      return Color.fromARGB(
        (color.a.clamp(0.0, 1.0) * 255).round(),
        (color.r.clamp(0.0, 1.0) * 255).round(),
        (color.g.clamp(0.0, 1.0) * 255).round(),
        (color.b.clamp(0.0, 1.0) * 255).round(),
      );
    }
    final bound = snapshot.color(bind);
    return bound ?? _baseColor;
  }

  static vm.Vector3 _normalizedAxis(vm.Matrix4 transform, int axis) {
    final direction = vm.Vector3(
      transform.entry(0, axis),
      transform.entry(1, axis),
      transform.entry(2, axis),
    );
    if (direction.length2 < 1e-12) {
      return vm.Vector3.zero()..[axis] = 1;
    }
    return direction..normalize();
  }

  static vm.Vector3 _listVector(List<double> components) => vm.Vector3(
    components.isNotEmpty ? components[0] : 0,
    components.length > 1 ? components[1] : 0,
    components.length > 2 ? components[2] : 0,
  );

  static vm.Vector3 _localDirection(List<vm.Vector3> basis, List<double> axis) {
    final local = _listVector(axis);
    if (local.length2 < 1e-12) return basis[2];
    local.normalize();
    return _frameVector(basis, local.x, local.y, local.z);
  }

  /// A world direction from a bound (or literal) node-local axis, or null
  /// when the bound vector is degenerate.
  static vm.Vector3? _boundAxis(
    _Snapshot snapshot,
    List<vm.Vector3> basis,
    String? axisBind,
    List<double> axis,
  ) {
    if (axisBind == null) return _localDirection(basis, axis);
    final bound = snapshot.vector(axisBind);
    if (bound == null || bound.length2 < 1e-12) return null;
    bound.normalize();
    return _frameVector(basis, bound.x, bound.y, bound.z);
  }

  static vm.Vector3 _frameVector(
    List<vm.Vector3> basis,
    double x,
    double y,
    double z,
  ) => basis[0] * x + basis[1] * y + basis[2] * z;

  static (vm.Vector3, vm.Vector3) _axisPlane(int axis) {
    final u = vm.Vector3.zero()..[(axis + 1) % 3] = 1;
    final v = vm.Vector3.zero()..[(axis + 2) % 3] = 1;
    return (u, v);
  }

  // In-plane basis for the plane normal to [axis], oriented so the default
  // +Z normal maps u to local +X and v to local +Y (the engine's area-light
  // width/height convention).
  static (vm.Vector3, vm.Vector3) _perpendicular(vm.Vector3 axis) {
    final helper = axis.x.abs() < 0.9
        ? vm.Vector3(1, 0, 0)
        : vm.Vector3(0, 1, 0);
    final v = axis.cross(helper)..normalize();
    final u = v.cross(axis)..normalize();
    return (u, v);
  }

  static double? _inflated(double? base, double? inflate) =>
      base == null || inflate == null ? null : base + inflate;

  void _strokeLocalBox(
    vm.Matrix4 transform,
    vm.Vector3 center,
    vm.Vector3 half,
    Color color,
    List<(Offset, Offset)> segments,
  ) {
    final corners = [
      for (var c = 0; c < 8; c++)
        transform.transformed3(
          center +
              vm.Vector3(
                (c & 1) == 0 ? -half.x : half.x,
                (c & 2) == 0 ? -half.y : half.y,
                (c & 4) == 0 ? -half.z : half.z,
              ),
        ),
    ];
    for (var a = 0; a < 8; a++) {
      for (final bit in const [1, 2, 4]) {
        final b = a | bit;
        if (b == a) continue;
        _strokeWorldSegment(corners[a], corners[b], color, segments);
      }
    }
  }

  void _strokeFrustum(
    vm.Vector3 origin,
    List<vm.Vector3> basis,
    double fovY,
    double near,
    double far,
    double aspect,
    Color color,
    List<(Offset, Offset)> segments,
  ) {
    final tanHalf = math.tan((fovY / 2).clamp(0.001, math.pi / 2 - 0.001));
    List<vm.Vector3> plane(double depth) {
      final halfHeight = tanHalf * depth;
      final halfWidth = halfHeight * aspect;
      return [
        for (final (sx, sy) in const [(1, 1), (-1, 1), (-1, -1), (1, -1)])
          origin + _frameVector(basis, sx * halfWidth, sy * halfHeight, depth),
      ];
    }

    final nearPlane = plane(near);
    final farPlane = plane(far);
    for (var i = 0; i < 4; i++) {
      _strokeWorldSegment(
        nearPlane[i],
        nearPlane[(i + 1) % 4],
        color,
        segments,
      );
      _strokeWorldSegment(farPlane[i], farPlane[(i + 1) % 4], color, segments);
      _strokeWorldSegment(nearPlane[i], farPlane[i], color, segments);
    }
  }

  @override
  bool shouldRepaint(ComponentGizmoPainter old) => true;
}

/// One component's serialize snapshot, with dotted-path reads. The snapshot
/// is exactly what the codec would persist (delta form), overlaid on the
/// schema defaults.
class _Snapshot {
  _Snapshot(this._codec, this._properties);

  final ComponentCodec _codec;
  final Map<String, doc.PropertyValue> _properties;

  doc.PropertyValue? valueAt(String path) {
    final segments = path.split('.');
    var value =
        _properties[segments.first] ??
        _codec.schema.property(segments.first)?.defaultValue;
    for (var i = 1; i < segments.length; i++) {
      final map = value;
      if (map is! doc.MapValue) return null;
      value = map.values[segments[i]];
    }
    return value;
  }

  bool matches(GizmoCondition condition) {
    return switch (valueAt(condition.path)) {
      doc.StringValue(:final value) => value == condition.equals,
      doc.BoolValue(:final value) => '$value' == condition.equals,
      doc.IntValue(:final value) => '$value' == condition.equals,
      _ => false,
    };
  }

  double? scalar(GizmoScalar scalar) {
    final bind = scalar.bind;
    if (bind == null) return scalar.value;
    return switch (valueAt(bind)) {
      doc.DoubleValue(:final value) => value * scalar.scale,
      doc.IntValue(:final value) => value * scalar.scale,
      _ => null,
    };
  }

  vm.Vector3? vector(String path) => switch (valueAt(path)) {
    doc.Vec3Value(:final value) => value.clone(),
    _ => null,
  };

  Color? color(String path) {
    double clampChannel(double channel) => channel.clamp(0.0, 1.0);
    final value = valueAt(path);
    final (double r, double g, double b, double a)? rgba = switch (value) {
      doc.Vec3Value(:final value) => (value.x, value.y, value.z, 1.0),
      doc.Vec4Value(:final value) => (value.x, value.y, value.z, value.w),
      doc.ColorValue() => (value.r, value.g, value.b, value.a),
      _ => null,
    };
    if (rgba == null) return null;
    return Color.fromARGB(
      (clampChannel(rgba.$4) * 255).round(),
      (clampChannel(rgba.$1) * 255).round(),
      (clampChannel(rgba.$2) * 255).round(),
      (clampChannel(rgba.$3) * 255).round(),
    );
  }
}
