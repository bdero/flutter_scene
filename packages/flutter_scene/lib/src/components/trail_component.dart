import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/geometry/polyline_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show AlphaMode;
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

// TODO(particles): per-particle trails (a ribbon per particle of a
// ParticleSystem) are a natural follow-up and need per-ribbon particle ids.

/// An engine component that trails a camera-facing ribbon behind its owning
/// node as the node moves, for missiles, sword slashes, tracers, and debris.
///
/// Each frame the component records the node's world position: a new trail
/// point is anchored whenever the node has moved [minVertexDistance] from the
/// last anchor, the newest point continuously follows the node so the head
/// never lags, and points older than [lifetime] expire. The recorded path is
/// rendered as a strip that always faces the camera, with [width] shaped by
/// [widthOverTrail] and tinted by [colorOverTrail] from head (`0`) to tail
/// (`1`).
///
/// Points are recorded in world space, so the ribbon hangs in the world
/// where the node has been rather than dragging along rigidly with it. The
/// strip is an ordinary triangle mesh (the trail gradient rides the vertex
/// colors and its texture coordinates run head to tail along `u`), so it
/// pairs with any standard material; the default is a translucent
/// [UnlitMaterial] weighted fully to the vertex color, drawn without
/// culling. A custom [Material] must also disable culling, since a
/// camera-facing strip's winding flips wherever the path doubles back on
/// itself.
/// {@category Particles}
class TrailComponent extends MeshComponent {
  /// Creates a trail. [maxPoints] bounds the recorded path (oldest points
  /// expire first); [material] defaults to a translucent unlit material
  /// driven by the trail's vertex colors.
  factory TrailComponent({
    double width = 0.25,
    double lifetime = 0.6,
    double minVertexDistance = 0.05,
    int maxPoints = 48,
    ParticleCurve? widthOverTrail,
    ColorGradient? colorOverTrail,
    Material? material,
  }) {
    final geometry = _TrailGeometry(maxPoints);
    final resolved =
        material ??
        (_TrailDefaultMaterial()
          ..alphaMode = AlphaMode.blend
          ..vertexColorWeight = 1.0);
    return TrailComponent._(
      geometry,
      resolved,
      width: width,
      lifetime: lifetime,
      minVertexDistance: minVertexDistance,
      widthOverTrail: widthOverTrail,
      colorOverTrail: colorOverTrail,
    );
  }

  TrailComponent._(
    this._geometry,
    Material material, {
    required this.width,
    required this.lifetime,
    required this.minVertexDistance,
    required this.widthOverTrail,
    required this.colorOverTrail,
  }) : super(Mesh(_geometry, material));

  /// The ribbon's width in world units at curve value `1`.
  double width;

  /// Seconds a recorded point lives before the tail consumes it.
  double lifetime;

  /// World distance the node must move before a new point is anchored.
  double minVertexDistance;

  /// Width multiplier over the trail, head (`0`) to tail (`1`). Defaults to
  /// a taper from full width at the head to zero at the tail.
  ParticleCurve? widthOverTrail;

  /// Color over the trail, head (`0`) to tail (`1`). Defaults to white
  /// fading out toward the tail.
  ColorGradient? colorOverTrail;

  /// Whether new points are recorded. While false the existing ribbon ages
  /// out naturally.
  bool emitting = true;

  /// The recorded path's capacity, fixed at construction.
  int get maxPoints => _geometry.maxPoints;

  final _TrailGeometry _geometry;
  final List<Vector3> _worldPoints = [];
  final List<double> _bornTimes = [];
  double _time = 0.0;
  final Vector4 _scratchColor = Vector4.zero();
  final Matrix4 _scratchInverse = Matrix4.zero();

  /// Forgets the recorded path (the ribbon disappears immediately).
  void clear() {
    _worldPoints.clear();
    _bornTimes.clear();
  }

  @override
  void update(double deltaSeconds) {
    _time += deltaSeconds;
    final world = node.globalTransform.getTranslation();

    if (emitting) {
      if (_worldPoints.isEmpty) {
        _worldPoints.insert(0, world.clone());
        _bornTimes.insert(0, _time);
      } else {
        // The head follows the node continuously; a new anchor is dropped
        // once it has traveled far enough from the previous one.
        _worldPoints.first.setFrom(world);
        _bornTimes[0] = _time;
        final anchored = _worldPoints.length > 1
            ? _worldPoints[1]
            : _worldPoints.first;
        if (_worldPoints.length == 1 ||
            anchored.distanceTo(world) >= minVertexDistance) {
          _worldPoints.insert(0, world.clone());
          _bornTimes.insert(0, _time);
        }
      }
    }

    // Expire by age and by capacity (head stays, tail goes).
    while (_worldPoints.length > _geometry.maxPoints ||
        (_bornTimes.isNotEmpty && _time - _bornTimes.last > lifetime)) {
      _worldPoints.removeLast();
      _bornTimes.removeLast();
      if (_worldPoints.isEmpty) break;
    }

    // Repack into node-local space (the mesh renders under the moving
    // node's transform, but the ribbon must stay pinned in the world).
    _scratchInverse.setFrom(node.globalTransform);
    _scratchInverse.invert();
    _geometry.setTrail(
      _worldPoints,
      _scratchInverse,
      (t) => width * (widthOverTrail?.sample(t) ?? (1.0 - t)),
      (t, out) {
        final gradient = colorOverTrail;
        if (gradient != null) {
          gradient.sample(t, out);
        } else {
          out.setValues(1, 1, 1, 1.0 - t);
        }
        return out;
      },
      _scratchColor,
    );
  }
}

/// The default trail material: translucent unlit, drawn without culling. A
/// camera-facing strip's winding flips with the path direction relative to
/// the view (hairpins, direction reversals), so back-face culling would
/// blink segments in and out as the emitter turns.
class _TrailDefaultMaterial extends UnlitMaterial {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);
    pass.setCullMode(gpu.CullMode.none);
  }
}

/// The trail's strip geometry: a fixed-topology two-vertices-per-point
/// ribbon whose positions are expanded toward the camera at bind time (the
/// bind arguments carry the camera), with widths, colors, and points fed by
/// [TrailComponent.update].
class _TrailGeometry extends MeshGeometry {
  _TrailGeometry(this.maxPoints)
    : assert(maxPoints >= 2),
      super.fromArrays(
        positions: Float32List(maxPoints * 6),
        normals: _initialNormals(maxPoints),
        texCoords: _stripTexCoords(maxPoints),
        colors: Float32List(maxPoints * 8),
        indices: _stripIndices(maxPoints),
        storage: GeometryStorage.updatable,
      );

  final int maxPoints;

  // The strip's winding flips with the view, so the material-less passes
  // (selection mask) must not cull it either.
  @override
  bool get isDoubleSided => true;

  final List<Vector3> _localPoints = [];
  final List<double> _widths = [];
  bool _live = false;

  static Float32List _initialNormals(int maxPoints) {
    final normals = Float32List(maxPoints * 6);
    for (var i = 0; i < maxPoints * 2; i++) {
      normals[i * 3 + 2] = 1.0;
    }
    return normals;
  }

  static Float32List _stripTexCoords(int maxPoints) {
    final uv = Float32List(maxPoints * 4);
    for (var i = 0; i < maxPoints; i++) {
      final u = maxPoints > 1 ? i / (maxPoints - 1) : 0.0;
      uv[i * 4] = u;
      uv[i * 4 + 1] = 0.0;
      uv[i * 4 + 2] = u;
      uv[i * 4 + 3] = 1.0;
    }
    return uv;
  }

  static List<int> _stripIndices(int maxPoints) {
    final indices = <int>[];
    for (var i = 0; i < maxPoints - 1; i++) {
      final a = i * 2;
      indices.addAll([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
    }
    return indices;
  }

  /// Replaces the trail path: [worldPoints] head-first, transformed by
  /// [worldToLocal], with per-point widths and colors from the callbacks
  /// (evaluated at the head-to-tail fraction).
  void setTrail(
    List<Vector3> worldPoints,
    Matrix4 worldToLocal,
    double Function(double t) widthAt,
    Vector4 Function(double t, Vector4 out) colorAt,
    Vector4 scratchColor,
  ) {
    _live = worldPoints.length >= 2;
    _localPoints.clear();
    _widths.clear();
    final colors = Float32List(maxPoints * 8);
    if (!_live) {
      // Degenerate: everything collapses to a zero-width point.
      final anchor = worldPoints.isEmpty
          ? Vector3.zero()
          : (worldToLocal.transform3(worldPoints.first.clone()));
      for (var i = 0; i < maxPoints; i++) {
        _localPoints.add(anchor);
        _widths.add(0.0);
      }
      updateColors(colors);
      return;
    }
    final live = worldPoints.length;
    for (var i = 0; i < maxPoints; i++) {
      final clamped = math.min(i, live - 1);
      final t = live > 1 ? clamped / (live - 1) : 0.0;
      _localPoints.add(worldToLocal.transform3(worldPoints[clamped].clone()));
      // Points beyond the live tail collapse to zero width.
      _widths.add(i < live ? widthAt(t) : 0.0);
      final color = colorAt(t, scratchColor);
      final o = i * 8;
      colors[o] = color.x;
      colors[o + 1] = color.y;
      colors[o + 2] = color.z;
      colors[o + 3] = i < live ? color.w : 0.0;
      colors[o + 4] = color.x;
      colors[o + 5] = color.y;
      colors[o + 6] = color.z;
      colors[o + 7] = i < live ? color.w : 0.0;
    }
    updateColors(colors);
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    if (_localPoints.length == maxPoints) {
      // Expand toward the camera in local space (the points' space), so
      // bring the world camera position into it.
      final inverse = Matrix4.inverted(modelTransform);
      final localCamera = inverse.transform3(cameraPosition.clone());
      final expanded = expandPolyline(
        _localPoints,
        widths: _widths,
        widthMode: PolylineWidthMode.worldUnits,
        diskPoints: const [],
        drawStart: 0.0,
        drawEnd: 1.0,
        viewProjection: cameraTransform,
        cameraPosition: localCamera,
        viewportSize: const ui.Size(1, 1),
      );
      updatePositions(expanded.positions);
      updateNormals(expanded.normals);
    }
    super.bind(
      pass,
      transientsBuffer,
      modelTransform,
      cameraTransform,
      cameraPosition,
      shaderOverride: shaderOverride,
    );
  }
}
