import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/depth_raster.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';
import 'package:flutter_scene/src/render/view_sizing.dart';
import 'package:flutter_scene/src/shaders.dart';

/// How a [PolylineGeometry]'s width is measured.
/// {@category Geometry}
enum PolylineWidthMode {
  /// The width is a constant number of screen pixels at every distance,
  /// so a route line keeps the same on-screen thickness as the camera
  /// zooms.
  screenPixels,

  /// The width is a fixed distance in scene units, so the line looks
  /// thinner the further it is from the camera.
  worldUnits,
}

/// How a [PolylineGeometry] finishes its two end points.
/// {@category Geometry}
enum PolylineCap {
  /// The strip ends flat at the end point.
  butt,

  /// A half-disk rounds the end off to the line's half-width.
  round,
}

/// A repeating dash-and-gap pattern for a [PolylineGeometry], measured
/// in scene units along the line's arc length.
/// {@category Geometry}
class DashPattern {
  /// Creates a dash pattern; both lengths must be positive.
  const DashPattern({
    required this.dashLength,
    required this.gapLength,
    this.cap = PolylineCap.butt,
  }) : assert(dashLength > 0, 'dashLength must be positive'),
       assert(gapLength > 0, 'gapLength must be positive');

  /// The drawn length of each dash.
  final double dashLength;

  /// The undrawn length between dashes.
  final double gapLength;

  /// How each dash's two ends are finished. [PolylineCap.round] caps
  /// every dash with a camera-facing disk; the default is flat ends.
  final PolylineCap cap;
}

// Triangle-fan segments in a round cap disk.
const int _diskSegments = 16;

/// Floats per polyline vertex: position, previous, and next (3 each), shape
/// (4), arcs (3), texture coordinates (2), and color (4).
const int polylineVertexFloats = 22;

// TODO(polyline-joins): add rounded corner joins.
/// A thick, camera-facing line through a list of points.
///
/// `PolylineGeometry` draws a triangle strip that always faces the camera,
/// which suits navigation routes and other overlay lines. The strip is
/// expanded on the GPU for whichever camera renders it, so every view of a
/// scene sees the line facing it and nothing needs updating per frame.
///
/// Pair it with any material, and use [perVertexColor] for gradient or
/// distance-fade effects. Texture `u` runs across the line and `v` is the
/// distance along it. The points are in the geometry's local space and the
/// owning node's transform places the whole line.
///
/// [PolylineCap.round] adds a camera-facing disk at each end point,
/// [drawStart]/[drawEnd] trim the line or animate it drawing on, and a
/// [DashPattern] breaks it into dashes, which its own cap can round.
/// Corners use an averaged direction, which stays smooth on a finely
/// sampled curve but can pinch on a very sharp turn.
/// {@category Geometry}
class PolylineGeometry extends Geometry {
  /// Creates a polyline through [points] (at least two).
  ///
  /// [width] is measured per [widthMode]. [perVertexWidth] overrides it
  /// per point for tapering, and [perVertexColor] sets a color per
  /// point for gradients. [cap] selects rounded or flat ends, and
  /// [dash] breaks the line into dashes.
  factory PolylineGeometry(
    List<Vector3> points, {
    double width = 8.0,
    PolylineWidthMode widthMode = PolylineWidthMode.screenPixels,
    PolylineCap cap = PolylineCap.butt,
    DashPattern? dash,
    List<double>? perVertexWidth,
    List<Vector4>? perVertexColor,
  }) {
    if (points.length < 2) {
      throw ArgumentError('A polyline needs at least two points');
    }
    final inputCount = points.length;
    if (perVertexWidth != null && perVertexWidth.length != inputCount) {
      throw ArgumentError('perVertexWidth must have one entry per point');
    }
    if (perVertexColor != null && perVertexColor.length != inputCount) {
      throw ArgumentError('perVertexColor must have one entry per point');
    }
    var working = <Vector3>[for (final p in points) p.clone()];
    var workingWidths = perVertexWidth != null
        ? List<double>.of(perVertexWidth)
        : List<double>.filled(inputCount, width);
    var workingColors = <Vector4>[
      for (var i = 0; i < inputCount; i++)
        perVertexColor?[i] ?? Vector4(1.0, 1.0, 1.0, 1.0),
    ];

    // Dashes resample the line into dash segments joined by zero-width
    // gap points, so the gap regions draw nothing.
    var dashCapIndices = const <int>[];
    if (dash != null) {
      final dashed = resampleDashed(
        working,
        workingWidths,
        workingColors,
        dash,
      );
      working = dashed.points;
      workingWidths = dashed.widths;
      workingColors = dashed.colors;
      dashCapIndices = dashed.dashCapIndices;
    }

    // Round dash caps put a disk at every dash boundary; otherwise the
    // disks are just the line's two round ends.
    final diskPoints = (dash != null && dash.cap == PolylineCap.round)
        ? dashCapIndices
        : diskPointIndices(working.length, cap);
    return PolylineGeometry._(
      working,
      workingWidths,
      widthMode,
      buildPolylineVertices(
        working,
        widths: workingWidths,
        colors: workingColors,
        diskPoints: diskPoints,
      ),
    );
  }

  PolylineGeometry._(
    this._points,
    List<double> widths,
    this._widthMode,
    ({Float32List vertices, List<int> indices}) mesh,
  ) {
    setVertexShader(baseShaderLibrary['PolylineVertex']!);

    final vertexCount = mesh.vertices.length ~/ polylineVertexFloats;
    final vertexBytes = ByteData.sublistView(mesh.vertices);
    final wide = vertexCount > 0xFFFF;
    final TypedData indices = wide
        ? Uint32List.fromList(mesh.indices)
        : Uint16List.fromList(mesh.indices);
    final indexBytes = ByteData.sublistView(indices);
    final buffer = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      vertexBytes.lengthInBytes + indexBytes.lengthInBytes,
    );
    buffer.overwrite(vertexBytes);
    buffer.overwrite(
      indexBytes,
      destinationOffsetInBytes: vertexBytes.lengthInBytes,
    );
    setVertices(
      gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: vertexBytes.lengthInBytes,
      ),
      vertexCount,
    );
    setIndices(
      gpu.BufferView(
        buffer,
        offsetInBytes: vertexBytes.lengthInBytes,
        lengthInBytes: indexBytes.lengthInBytes,
      ),
      wide ? gpu.IndexType.int32 : gpu.IndexType.int16,
    );

    // A pixel width has no world size to pad by, so such a line is culled
    // by its center line and can leave a view up to half its width early.
    var pad = 0.0;
    if (_widthMode == PolylineWidthMode.worldUnits) {
      for (final width in widths) {
        pad = math.max(pad, width / 2.0);
      }
    }
    final aabb = Aabb3.minMax(_points.first.clone(), _points.first.clone());
    for (final point in _points) {
      aabb.hullPoint(point);
    }
    aabb.min.sub(Vector3.all(pad));
    aabb.max.add(Vector3.all(pad));
    setLocalBounds(
      aabb,
      Sphere.centerRadius(
        (aabb.min + aabb.max) * 0.5,
        (aabb.max - aabb.min).length * 0.5,
      ),
    );
  }

  final List<Vector3> _points;
  final PolylineWidthMode _widthMode;

  /// The fraction of the line, by arc length, where the visible range
  /// begins. With [drawEnd] this trims the line or animates it drawing
  /// on. Clamped to `0..1`; the default is `0`.
  double drawStart = 0.0;

  /// The fraction of the line, by arc length, where the visible range
  /// ends. See [drawStart]. The default is `1`.
  double drawEnd = 1.0;

  // The range the cached boundary points below were resolved for.
  double _rangeStart = double.nan;
  double _rangeEnd = double.nan;
  final Float32List _range = Float32List(8);

  /// Does nothing. The line follows the rendering camera on its own.
  @Deprecated('The line follows the rendering camera on its own. Remove it.')
  void updateForCamera(Camera camera, ui.Size viewportSize) {}

  @override
  VertexLayoutDescriptor? get defaultVertexLayout => _kPolylineLayout;

  // The strip reads the model transform from the FrameInfo uniform, so the
  // color encoder must not bind a model-transform buffer over slot 1.
  @override
  bool get bindsModelTransformInstance => false;

  // The strip turns to face each pass's camera, so the material-less passes
  // (selection mask, depth, shadow) must not cull it.
  @override
  bool get isDoubleSided => true;

  // The expansion runs in the engine's own vertex shader; a custom
  // material's generated vertex variants do not apply to this geometry.
  @override
  String? get materialVertexVariant => null;

  // The first stream's position is the center line, not the drawn vertex.
  // TODO(custom-velocity-vertex): give the line motion vectors.
  @override
  VertexLayoutDescriptor? get velocityPositionLayout => null;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    // See [materialVertexVariant]; the override is accepted and ignored.
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    bindGeometryBuffers(pass);

    if (drawStart != _rangeStart || drawEnd != _rangeEnd) {
      _rangeStart = drawStart;
      _rangeEnd = drawEnd;
      _range.setAll(0, polylineDrawRange(_points, drawStart, drawEnd));
    }

    final frameInfo = _frameInfoScratch
      ..setRange(0, 16, cameraTransform.storage)
      ..setRange(16, 32, modelTransform.storage)
      ..setRange(32, 48, currentViewSizingTransform);
    frameInfo[48] = cameraPosition.x;
    frameInfo[49] = cameraPosition.y;
    frameInfo[50] = cameraPosition.z;
    frameInfo[52] = currentViewSizingSize[0];
    frameInfo[53] = currentViewSizingSize[1];
    frameInfo[54] = _widthMode == PolylineWidthMode.screenPixels ? 1.0 : 0.0;
    // [56..57] the drawn range, [60..62] and [64..66] its boundary points.
    frameInfo[56] = _range[0];
    frameInfo[57] = _range[1];
    frameInfo.setRange(60, 63, _range, 2);
    frameInfo.setRange(64, 67, _range, 5);
    frameInfo[68] = currentDrawDepthOffset[0];
    frameInfo[69] = currentDrawDepthOffset[1];
    pass.bindUniform(
      vertexShader.cachedUniformSlot('FrameInfo'),
      transientsBuffer.emplace(scratchBytesOf(frameInfo)),
    );
  }
}

// Shared by every draw; emplace copies it out. Three matrices and six
// vectors, of which the unwritten components stay zero.
final Float32List _frameInfoScratch = Float32List(72);

final VertexLayoutDescriptor _kPolylineLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: polylineVertexFloats * 4,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'previous',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 12,
        ),
        VertexAttributeDescriptor(
          name: 'next',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 24,
        ),
        VertexAttributeDescriptor(
          name: 'shape',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 36,
        ),
        VertexAttributeDescriptor(
          name: 'arcs',
          format: gpu.VertexFormat.float32x3,
          offsetInBytes: 52,
        ),
        VertexAttributeDescriptor(
          name: 'texture_coords',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 64,
        ),
        VertexAttributeDescriptor(
          name: 'color',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 72,
        ),
      ],
    ),
  ],
);

/// The polyline point indices that receive a round cap disk: the two
/// end points when [cap] is [PolylineCap.round], otherwise none.
List<int> diskPointIndices(int count, PolylineCap cap) {
  if (cap == PolylineCap.round) {
    return <int>[0, count - 1];
  }
  return const <int>[];
}

// The cumulative arc length at each point.
List<double> _arcLengths(List<Vector3> points) {
  final arc = List<double>.filled(points.length, 0.0);
  for (var i = 1; i < points.length; i++) {
    arc[i] = arc[i - 1] + points[i].distanceTo(points[i - 1]);
  }
  return arc;
}

/// Packs [points] into the vertices and triangle indices the polyline
/// vertex shader expands, [polylineVertexFloats] floats per vertex.
///
/// The strip is two vertices per point, one on each side. Each index in
/// [diskPoints] adds a cap disk of a center vertex and a 16-vertex ring.
/// Every vertex carries its point and the two neighbors its tangent runs
/// between, so the shader can place it for any camera.
({Float32List vertices, List<int> indices}) buildPolylineVertices(
  List<Vector3> points, {
  required List<double> widths,
  required List<Vector4> colors,
  required List<int> diskPoints,
}) {
  final count = points.length;
  final arc = _arcLengths(points);
  final total = arc[count - 1];
  double fraction(int i) => total > 0.0 ? arc[i] / total : 0.0;

  final stripVertexCount = count * 2;
  final vertexCount =
      stripVertexCount + diskPoints.length * (_diskSegments + 1);
  final vertices = Float32List(vertexCount * polylineVertexFloats);

  // The last four arguments are the shape attribute's x and y, the texture
  // u, and whether the vertex belongs to a cap disk.
  void write(int vertex, int point, double x, double y, double u, bool disk) {
    // A disk has no tangent, so its neighbors are the point itself.
    final previous = disk || point == 0 ? point : point - 1;
    final next = disk || point == count - 1 ? point : point + 1;
    final at = vertex * polylineVertexFloats;
    points[point].copyIntoArray(vertices, at);
    points[previous].copyIntoArray(vertices, at + 3);
    points[next].copyIntoArray(vertices, at + 6);
    vertices[at + 9] = x;
    vertices[at + 10] = y;
    vertices[at + 11] = widths[point] / 2.0;
    vertices[at + 12] = disk ? 1.0 : 0.0;
    vertices[at + 13] = fraction(point);
    vertices[at + 14] = fraction(previous);
    vertices[at + 15] = fraction(next);
    vertices[at + 16] = u;
    vertices[at + 17] = arc[point];
    colors[point].copyIntoArray(vertices, at + 18);
  }

  final indices = <int>[];
  for (var i = 0; i < count; i++) {
    write(i * 2, i, -1.0, 0.0, 0.0, false);
    write(i * 2 + 1, i, 1.0, 0.0, 1.0, false);
  }
  for (var i = 0; i < count - 1; i++) {
    final a = i * 2;
    indices
      ..addAll([a, a + 1, a + 2])
      ..addAll([a + 1, a + 3, a + 2]);
  }

  // A triangle-fan disk for each round cap.
  for (var ord = 0; ord < diskPoints.length; ord++) {
    final point = diskPoints[ord];
    final base = stripVertexCount + ord * (_diskSegments + 1);
    write(base, point, 0.0, 0.0, 0.5, true);
    for (var k = 0; k < _diskSegments; k++) {
      final angle = 2.0 * math.pi * k / _diskSegments;
      write(base + 1 + k, point, math.cos(angle), math.sin(angle), 0.5, true);
      final next = (k + 1) % _diskSegments;
      indices.addAll([base, base + 1 + k, base + 1 + next]);
    }
  }
  return (vertices: vertices, indices: indices);
}

/// The draw range the polyline vertex shader trims to, as eight floats: the
/// start and end arc-length fractions, then the local-space point at each.
///
/// [drawStart] and [drawEnd] clamp to `0..1`. A zero-length line has no
/// range to trim, so it reports the whole line.
Float32List polylineDrawRange(
  List<Vector3> points,
  double drawStart,
  double drawEnd,
) {
  final arc = _arcLengths(points);
  final total = arc.last;
  final start = total > 0.0 ? _clamp01(drawStart) : 0.0;
  final end = total > 0.0 ? _clamp01(drawEnd) : 1.0;
  final range = Float32List(8)
    ..[0] = start
    ..[1] = end;
  _pointAtArc(points, arc, start * total).copyIntoArray(range, 2);
  _pointAtArc(points, arc, end * total).copyIntoArray(range, 5);
  return range;
}

/// Expands [points] into a camera-facing triangle strip's vertex
/// positions and normals on the CPU, including round cap disks.
///
/// `PolylineGeometry` does this in its vertex shader. The trail ribbon,
/// whose points change every frame, still expands here.
///
/// [drawStart] and [drawEnd] (fractions `0..1` of the arc length) trim
/// the visible range: points outside it collapse onto the range
/// boundary with zero width.
///
/// [diskPoints] lists the point indices that receive a round cap disk.
///
/// Pure: it takes the view-projection matrix rather than touching the
/// GPU, so it can be exercised without a render context. The strip is
/// two vertices per point; each round cap adds a disk of `1 + 16`
/// vertices.
({Float32List positions, Float32List normals}) expandPolyline(
  List<Vector3> points, {
  required List<double> widths,
  required PolylineWidthMode widthMode,
  required List<int> diskPoints,
  required double drawStart,
  required double drawEnd,
  required Matrix4 viewProjection,
  required Vector3 cameraPosition,
  required ui.Size viewportSize,
}) {
  final count = points.length;
  final (drawnPoints, drawnWidths) = _applyDrawRange(
    points,
    widths,
    drawStart,
    drawEnd,
  );
  final tangents = _pointTangents(drawnPoints);
  final viewDirections = <Vector3>[
    for (final p in drawnPoints) _towardCamera(cameraPosition, p),
  ];

  // Strip edge vertices, computed per point.
  final left = List<Vector3>.filled(count, Vector3.zero());
  final right = List<Vector3>.filled(count, Vector3.zero());

  if (widthMode == PolylineWidthMode.worldUnits) {
    for (var i = 0; i < count; i++) {
      var across = tangents[i].cross(viewDirections[i]);
      if (across.length2 < 1e-12) across = _anyPerpendicular(tangents[i]);
      across = across.normalized() * (drawnWidths[i] / 2.0);
      left[i] = drawnPoints[i] - across;
      right[i] = drawnPoints[i] + across;
    }
  } else {
    final inverse = Matrix4.inverted(viewProjection);
    final clip = <Vector4>[
      for (final p in drawnPoints)
        viewProjection.transformed(Vector4(p.x, p.y, p.z, 1.0)),
    ];
    final width = viewportSize.width;
    final height = viewportSize.height;
    for (var i = 0; i < count; i++) {
      final here = clip[i];
      final w = here.w.abs() < 1e-6 ? 1e-6 : here.w;
      final previous = clip[i == 0 ? 0 : i - 1];
      final next = clip[i == count - 1 ? count - 1 : i + 1];
      // Screen-space direction between the neighbors.
      var screenX = (_ndcX(next) - _ndcX(previous)) * width;
      var screenY = -(_ndcY(next) - _ndcY(previous)) * height;
      var length = math.sqrt(screenX * screenX + screenY * screenY);
      if (length < 1e-9) {
        screenX = 1.0;
        screenY = 0.0;
        length = 1.0;
      }
      screenX /= length;
      screenY /= length;
      // Perpendicular, offset by half the pixel width, expressed in NDC.
      final half = drawnWidths[i] / 2.0;
      final ndcOffsetX = -screenY * half * 2.0 / width;
      final ndcOffsetY = -screenX * half * 2.0 / height;
      left[i] = _unproject(
        inverse,
        here.x + ndcOffsetX * w,
        here.y + ndcOffsetY * w,
        here.z,
        w,
      );
      right[i] = _unproject(
        inverse,
        here.x - ndcOffsetX * w,
        here.y - ndcOffsetY * w,
        here.z,
        w,
      );
    }
  }

  final vertexCount = count * 2 + diskPoints.length * (_diskSegments + 1);
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);

  for (var i = 0; i < count; i++) {
    _writePair(positions, normals, i, left[i], right[i], viewDirections[i]);
  }

  var base = count * 2;
  for (final point in diskPoints) {
    // The strip half-width at the point, recovered from its two edges,
    // works for both world and screen modes. It is zero for a point
    // collapsed by the draw range, hiding that cap.
    final radius = (left[point] - right[point]).length / 2.0;
    base = _emitDisk(
      positions,
      normals,
      base,
      drawnPoints[point],
      viewDirections[point],
      radius,
    );
  }
  return (positions: positions, normals: normals);
}

double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

// Trims the polyline to the [drawStart, drawEnd] arc-length range.
// Points outside the range collapse onto the boundary position with
// zero width, so the strip there is degenerate and draws nothing.
(List<Vector3>, List<double>) _applyDrawRange(
  List<Vector3> points,
  List<double> widths,
  double drawStart,
  double drawEnd,
) {
  final start = _clamp01(drawStart);
  final end = _clamp01(drawEnd);
  if (start <= 0.0 && end >= 1.0) return (points, widths);

  final count = points.length;
  final arc = List<double>.filled(count, 0.0);
  for (var i = 1; i < count; i++) {
    arc[i] = arc[i - 1] + points[i].distanceTo(points[i - 1]);
  }
  final total = arc[count - 1];
  if (total <= 0.0) return (points, widths);

  final startPosition = _pointAtArc(points, arc, start * total);
  final endPosition = _pointAtArc(points, arc, end * total);
  final drawnPoints = <Vector3>[];
  final drawnWidths = <double>[];
  for (var i = 0; i < count; i++) {
    final fraction = arc[i] / total;
    if (fraction < start) {
      drawnPoints.add(startPosition);
      drawnWidths.add(0.0);
    } else if (fraction > end) {
      drawnPoints.add(endPosition);
      drawnWidths.add(0.0);
    } else {
      drawnPoints.add(points[i]);
      drawnWidths.add(widths[i]);
    }
  }
  return (drawnPoints, drawnWidths);
}

// The point at arc-length distance [target] along the polyline.
Vector3 _pointAtArc(List<Vector3> points, List<double> arc, double target) {
  final clamped = target < 0.0 ? 0.0 : (target > arc.last ? arc.last : target);
  var hi = 1;
  while (hi < arc.length - 1 && arc[hi] < clamped) {
    hi++;
  }
  final lo = hi - 1;
  final span = arc[hi] - arc[lo];
  final local = span > 1e-12 ? (clamped - arc[lo]) / span : 0.0;
  return points[lo] + (points[hi] - points[lo]) * local;
}

/// Resamples a polyline into dash segments per [dash].
///
/// Each dash starts and ends with a full-width point at the exact dash
/// boundary; consecutive dashes are joined by zero-width gap points so
/// the gap draws nothing. The overall line keeps its two end points, so
/// round caps still apply to them. `dashCapIndices` lists the resampled
/// indices of every dash boundary, for per-dash round caps.
({
  List<Vector3> points,
  List<double> widths,
  List<Vector4> colors,
  List<int> dashCapIndices,
})
resampleDashed(
  List<Vector3> points,
  List<double> widths,
  List<Vector4> colors,
  DashPattern dash,
) {
  final count = points.length;
  final arc = List<double>.filled(count, 0.0);
  for (var i = 1; i < count; i++) {
    arc[i] = arc[i - 1] + points[i].distanceTo(points[i - 1]);
  }
  final total = arc[count - 1];
  if (total <= 0.0) {
    return (
      points: points,
      widths: widths,
      colors: colors,
      dashCapIndices: const <int>[],
    );
  }

  // Position, width, and color at an arc-length distance.
  (Vector3, double, Vector4) sampleAt(double distance) {
    final target = distance < 0.0 ? 0.0 : (distance > total ? total : distance);
    var hi = 1;
    while (hi < count - 1 && arc[hi] < target) {
      hi++;
    }
    final lo = hi - 1;
    final span = arc[hi] - arc[lo];
    final local = span > 1e-12 ? (target - arc[lo]) / span : 0.0;
    return (
      points[lo] + (points[hi] - points[lo]) * local,
      widths[lo] + (widths[hi] - widths[lo]) * local,
      colors[lo] + (colors[hi] - colors[lo]) * local,
    );
  }

  final period = dash.dashLength + dash.gapLength;
  final dashes = <(double, double)>[];
  for (var k = 0; k * period < total; k++) {
    final a = k * period;
    dashes.add((a, math.min(a + dash.dashLength, total)));
  }

  final outPoints = <Vector3>[];
  final outWidths = <double>[];
  final outColors = <Vector4>[];
  final dashCapIndices = <int>[];
  void emit(Vector3 p, double w, Vector4 c) {
    outPoints.add(p);
    outWidths.add(w);
    outColors.add(c);
  }

  for (var k = 0; k < dashes.length; k++) {
    final (a, b) = dashes[k];
    final (startPos, startWidth, startColor) = sampleAt(a);
    final (endPos, endWidth, endColor) = sampleAt(b);
    // A zero-width gap connector before every dash but the first.
    if (k > 0) emit(startPos, 0.0, startColor);
    emit(startPos, startWidth, startColor);
    dashCapIndices.add(outPoints.length - 1);
    for (var i = 0; i < count; i++) {
      if (arc[i] > a && arc[i] < b) emit(points[i], widths[i], colors[i]);
    }
    emit(endPos, endWidth, endColor);
    dashCapIndices.add(outPoints.length - 1);
    // A zero-width gap connector after every dash but the last.
    if (k < dashes.length - 1) emit(endPos, 0.0, endColor);
  }

  if (outPoints.length < 2) {
    return (
      points: points,
      widths: widths,
      colors: colors,
      dashCapIndices: const <int>[],
    );
  }
  return (
    points: outPoints,
    widths: outWidths,
    colors: outColors,
    dashCapIndices: dashCapIndices,
  );
}

List<Vector3> _pointTangents(List<Vector3> points) {
  final count = points.length;
  return <Vector3>[
    for (var i = 0; i < count; i++)
      () {
        final Vector3 delta;
        if (i == 0) {
          delta = points[1] - points[0];
        } else if (i == count - 1) {
          delta = points[count - 1] - points[count - 2];
        } else {
          delta = points[i + 1] - points[i - 1];
        }
        return delta.length2 < 1e-12
            ? Vector3(1.0, 0.0, 0.0)
            : delta.normalized();
      }(),
  ];
}

// Emits a camera-facing disk: a center vertex and a ring, fanned into
// triangles. The disk is nudged slightly toward the camera so it draws
// over the strip rather than z-fighting with it.
int _emitDisk(
  Float32List positions,
  Float32List normals,
  int base,
  Vector3 center,
  Vector3 viewDirection,
  double radius,
) {
  final faceCenter = center + viewDirection * (radius * 0.1);
  final u = _anyPerpendicular(viewDirection);
  final v = viewDirection.cross(u);
  _writeVertex(positions, normals, base, faceCenter, viewDirection);
  for (var k = 0; k < _diskSegments; k++) {
    final angle = 2.0 * math.pi * k / _diskSegments;
    final rim =
        faceCenter +
        u * (radius * math.cos(angle)) +
        v * (radius * math.sin(angle));
    _writeVertex(positions, normals, base + 1 + k, rim, viewDirection);
  }
  return base + 1 + _diskSegments;
}

double _ndcX(Vector4 clip) => clip.x / (clip.w.abs() < 1e-6 ? 1e-6 : clip.w);

double _ndcY(Vector4 clip) => clip.y / (clip.w.abs() < 1e-6 ? 1e-6 : clip.w);

Vector3 _unproject(Matrix4 inverse, double x, double y, double z, double w) {
  final world = inverse.transformed(Vector4(x, y, z, w));
  final iw = world.w.abs() < 1e-9 ? 1e-9 : world.w;
  return Vector3(world.x / iw, world.y / iw, world.z / iw);
}

Vector3 _towardCamera(Vector3 cameraPosition, Vector3 point) {
  final direction = cameraPosition - point;
  return direction.length2 < 1e-12
      ? Vector3(0.0, 0.0, 1.0)
      : direction.normalized();
}

Vector3 _anyPerpendicular(Vector3 direction) {
  final reference = direction.x.abs() < 0.9
      ? Vector3(1.0, 0.0, 0.0)
      : Vector3(0.0, 1.0, 0.0);
  return direction.cross(reference).normalized();
}

void _writeVertex(
  Float32List positions,
  Float32List normals,
  int vertex,
  Vector3 position,
  Vector3 normal,
) {
  final base = vertex * 3;
  positions[base] = position.x;
  positions[base + 1] = position.y;
  positions[base + 2] = position.z;
  normals[base] = normal.x;
  normals[base + 1] = normal.y;
  normals[base + 2] = normal.z;
}

void _writePair(
  Float32List positions,
  Float32List normals,
  int point,
  Vector3 left,
  Vector3 right,
  Vector3 normal,
) {
  _writeVertex(positions, normals, point * 2, left, normal);
  _writeVertex(positions, normals, point * 2 + 1, right, normal);
}
