import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal, visibleForTesting;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/raster_sync.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/node_path.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/object_filter.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';

/// Two surfaces whose visible winner changes when the depth mapping changes
/// by an amount too small to move anything on screen: surfaces that flicker
/// against each other (z-fighting) as the camera moves.
/// {@category Rendering}
class DepthConflict {
  const DepthConflict({
    required this.nodeA,
    required this.nodeB,
    required this.pixelCount,
    required this.bounds,
    required this.distance,
  });

  /// One of the two nodes, or null when its item has no node.
  final Node? nodeA;

  /// The other node.
  final Node? nodeB;

  /// How many probe pixels changed hands between the two.
  final int pixelCount;

  /// Where the conflict shows, as fractions of the probe image (origin top
  /// left).
  final ui.Rect bounds;

  /// About how far from the camera the conflict shows, in world units: where
  /// the view ray through its pixels meets the nearer surface's bounds.
  final double distance;

  /// One line naming the pair, its size on screen, and its distance.
  String describe() {
    String label(Node? node) =>
        node == null ? '(unnamed)' : "'${debugNodePath(node)}'";
    return '${label(nodeA)} and ${label(nodeB)} trade $pixelCount pixels '
        'at ${distance.toStringAsFixed(distance < 10 ? 1 : 0)} m';
  }
}

/// The result of `Scene.probeDepthConflicts`: every pair of surfaces that
/// fights in one view, largest first.
/// {@category Rendering}
class DepthConflictReport {
  const DepthConflictReport({
    required this.width,
    required this.height,
    required this.conflicts,
  });

  /// The probe image's size in pixels.
  final int width;
  final int height;

  /// The fighting pairs, most pixels first. Empty when nothing fights.
  final List<DepthConflict> conflicts;

  /// The pixels involved in any conflict.
  int get conflictPixelCount =>
      conflicts.fold(0, (sum, conflict) => sum + conflict.pixelCount);

  /// [conflictPixelCount] as a fraction of the image.
  double get conflictFraction => conflictPixelCount / (width * height);

  /// A short report for a log or an agent: a summary line and the largest
  /// [limit] pairs.
  String describe({int limit = 8}) {
    if (conflicts.isEmpty) {
      return 'No depth conflicts in a ${width}x$height probe.';
    }
    final lines = [
      '${conflicts.length} depth conflict${conflicts.length == 1 ? '' : 's'} '
          'over ${(conflictFraction * 100).toStringAsFixed(2)}% of a '
          '${width}x$height probe. Surfaces that overlap in one plane fight '
          'at any distance; separate them, make repeated pieces abut, or give '
          'the one that belongs on top a higher Material.depthLayer.',
      for (final conflict in conflicts.take(limit)) '  ${conflict.describe()}',
      if (conflicts.length > limit) '  and ${conflicts.length - limit} more',
    ];
    return lines.join('\n');
  }
}

/// Relative changes to the depth row the probe renders with. Each re-rolls
/// the rounding of every interpolated depth without moving a pixel, which is
/// what camera motion does to surfaces closer than the depth buffer can
/// separate.
@internal
const List<double> kDepthConflictPerturbations = [0.013, 0.029, 0.047];

/// Sub-pixel camera offsets, in pixels, the probe also renders at. Each
/// re-rolls the rasterizer's snapping (a 256th of a pixel) the way camera
/// motion does, which no change to the depth mapping touches, while moving
/// edges too little to change many pixels.
@internal
const List<(double, double)> kDepthConflictJitters = [
  (0.061, 0.023),
  (-0.029, 0.057),
];

/// [viewProjection] with its depth row scaled by `1 + epsilon` about the far
/// plane, so far content stays put and nothing moves on screen.
@visibleForTesting
Matrix4 perturbDepthRow(
  Matrix4 viewProjection,
  double epsilon, {
  required bool reversed,
}) {
  final s = viewProjection.storage;
  final scale = 1.0 + epsilon;
  // Standard depth keeps the far plane at w: z' = z (1 + e) - e w. Reversed
  // depth keeps it at 0: z' = z (1 + e).
  final shift = reversed ? 0.0 : -epsilon;
  return Matrix4.copy(viewProjection)..setRow(
    2,
    Vector4(
      s[2] * scale + s[3] * shift,
      s[6] * scale + s[7] * shift,
      s[10] * scale + s[11] * shift,
      s[14] * scale + s[15] * shift,
    ),
  );
}

// TODO(depth-conflicts): the instances of one item share its id, so two
// instances with different colors fighting each other go unseen here (the
// coplanar lint still finds them). Encode the instance index into the id
// through the instance color record to catch them.

/// Draws exact object-id images of one view: every drawn item flat in a
/// dense id (24 bits of RGB8, 0 for background), depth-tested with the
/// view's own depth raster, so layers, the tie-break, reversed depth, and a
/// fitted near plane all count.
///
/// Projection volumes (decals, tested `always`) and items that draw nothing
/// are skipped.
///
/// Items drawing with one material and no per-instance color share an
/// appearance, since their overlaps draw identical pixels whoever wins.
@internal
class DepthConflictIds {
  DepthConflictIds({
    required this.renderScene,
    required this.camera,
    required this.size,
    this.layerMask = kRenderLayerAll,
  }) : frustum = cullingFrustumOf(camera, size),
       _pixelSlope = pixelDepthSlopeOf(camera, size) {
    final groups = Map<Object, int>.identity();
    renderScene.cull(frustum, (item) {
      if (!item.drawsColor || (item.layers & layerMask) == 0) return;
      if (!_include(item) || _ids.containsKey(item)) return;
      items.add(item);
      _ids[item] = items.length;
      final Object key = item.instanceColors == null ? item.material : item;
      appearances.add(groups.putIfAbsent(key, () => groups.length + 1));
    });
    appearanceCount = groups.length;
  }

  final RenderScene renderScene;
  final ViewportBoundCamera camera;
  final ui.Size size;
  final int layerMask;
  final Frustum frustum;
  final double _pixelSlope;

  /// The drawn items, the item with id `n` at index `n - 1`.
  final List<RenderItem> items = [];
  final Map<RenderItem, int> _ids = {};

  /// The appearance of each id, from 1, with background (id 0) at 0.
  final List<int> appearances = [0];

  /// How many appearances the items have.
  late final int appearanceCount;

  static bool _include(RenderItem item) =>
      !item.material.drawsNothing &&
      item.material.depthCompare != gpu.CompareFunction.always;

  static Vector4 _idColor(int id) => Vector4(
    (id & 0xff) / 255.0,
    ((id >> 8) & 0xff) / 255.0,
    ((id >> 16) & 0xff) / 255.0,
    1.0,
  );

  Vector4 _colorOf(RenderItem item) => _idColor(_ids[item] ?? 0);

  Vector4 _appearanceColorOf(RenderItem item) =>
      _idColor(appearances[_ids[item] ?? 0]);

  /// How many bits the appearances span, so [bitNudge] separates every pair
  /// of appearances in that many pairs of images.
  int get appearanceBits {
    var bits = 1;
    while ((1 << bits) <= appearanceCount) {
      bits++;
    }
    return bits;
  }

  /// A nudge for [draw] that moves each item one nudge unit toward the
  /// camera when [bit] of its appearance is [sign], and as far away when it
  /// is not (see `kDepthNudgeSteps` and `kDepthNudgePixels`).
  double Function(int appearance) bitNudge(int bit, {required bool sign}) =>
      (appearance) => ((appearance >> bit) & 1 == 1) == sign ? 1.0 : -1.0;

  /// Nudges for [draw] indexed by appearance, one of five levels from minus
  /// to plus one nudge unit each, drawn from [random].
  List<double> randomNudges(math.Random random) => [
    0.0,
    for (var i = 0; i < appearanceCount; i++) (random.nextInt(5) - 2) * 0.5,
  ];

  /// Draws the id image into [target] (RGBA8) with [depth] (the context's
  /// default depth-stencil format), through [viewProjection] or the view's
  /// own raster transform.
  ///
  /// A [nudge] moves each item that many nudge units toward the camera (away
  /// when negative), by its appearance. Drawn again with the nudges negated,
  /// a pair nudged apart swaps owners wherever the two are closer than their
  /// difference, which is where they fight as the camera moves; silhouettes
  /// never move. [byAppearance] fills appearances rather than ids.
  void draw({
    required gpu.Texture target,
    required gpu.Texture depth,
    required TransientWriter transients,
    Matrix4? viewProjection,
    bool reverseOrder = false,
    double Function(int appearance)? nudge,
    bool byAppearance = false,
  }) {
    renderObjectMask(
      target: target,
      depth: depth,
      clearColor: Vector4.zero(),
      cameraTransform: viewProjection ?? camera.rasterViewTransform(),
      cameraPosition: camera.position,
      renderScene: renderScene,
      transientsBuffer: transients,
      layerMask: layerMask,
      filter: const NodeFilter.all(),
      colorOf: byAppearance ? _appearanceColorOf : _colorOf,
      raster: camera.raster,
      frustum: frustum,
      reverseOrder: reverseOrder,
      materialCulling: true,
      include: _include,
      nudge: nudge == null
          ? null
          : (item) => nudge(appearances[_ids[item] ?? 0]),
      pixelSlope: _pixelSlope,
      fullVertex: true,
    );
  }

  /// The view-projections of the perturbed images, see [perturbDepthRow].
  List<Matrix4> perturbedViewProjections() {
    final base = camera.rasterViewTransform();
    return [
      for (final epsilon in kDepthConflictPerturbations)
        perturbDepthRow(base, epsilon, reversed: camera.raster.reversed),
    ];
  }

  /// The view-projections of the jittered images, see
  /// [kDepthConflictJitters].
  List<Matrix4> jitteredViewProjections() => [
    for (final (x, y) in kDepthConflictJitters)
      camera.rasterViewTransform(
        jitter: Vector2(x * 2 / size.width, y * 2 / size.height),
      ),
  ];
}

/// Renders an exact object-id image of [camera]'s view several times (with
/// the draw order reversed, under [kDepthConflictPerturbations] and
/// [kDepthConflictJitters], and with appearances nudged apart one bit at a
/// time) and reports the pairs of items whose pixels change owner.
@internal
Future<DepthConflictReport> probeDepthConflicts({
  required RenderScene renderScene,
  required ViewportBoundCamera camera,
  required int width,
  required int height,
  required TransientWriter transients,
  int layerMask = kRenderLayerAll,
  int minPixels = 4,
}) async {
  final ids = DepthConflictIds(
    renderScene: renderScene,
    camera: camera,
    size: ui.Size(width.toDouble(), height.toDouble()),
    layerMask: layerMask,
  );
  final items = ids.items;

  final color = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    width,
    height,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
  final depth = gpu.gpuContext.createTexture(
    gpu.StorageMode.deviceTransient,
    width,
    height,
    format: gpu.gpuContext.defaultDepthStencilFormat,
    enableRenderTargetUsage: true,
  );

  Future<Uint32List> render({
    Matrix4? viewProjection,
    bool reverseOrder = false,
    double Function(int appearance)? nudge,
  }) async {
    ids.draw(
      target: color,
      depth: depth,
      transients: transients,
      viewProjection: viewProjection,
      reverseOrder: reverseOrder,
      nudge: nudge,
    );
    await awaitRasterThread();
    final image = color.asImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) {
        throw StateError('Could not read back the depth conflict probe.');
      }
      // One id per pixel: RGB, with alpha masked off.
      final words = Uint32List(width * height);
      for (var i = 0; i < words.length; i++) {
        final o = i * 4;
        words[i] =
            bytes.getUint8(o) |
            (bytes.getUint8(o + 1) << 8) |
            (bytes.getUint8(o + 2) << 16);
      }
      return words;
    } finally {
      image.dispose();
    }
  }

  final reference = await render();
  final comparisons = <IdComparison>[
    (
      first: reference,
      second: await render(reverseOrder: true),
      areaOnly: false,
    ),
    for (final perturbed in ids.perturbedViewProjections())
      (
        first: reference,
        second: await render(viewProjection: perturbed),
        areaOnly: false,
      ),
    for (final jittered in ids.jitteredViewProjections())
      (
        first: reference,
        second: await render(viewProjection: jittered),
        areaOnly: true,
      ),
  ];
  for (var bit = 0; bit < ids.appearanceBits; bit++) {
    comparisons.add((
      first: await render(nudge: ids.bitNudge(bit, sign: true)),
      second: await render(nudge: ids.bitNudge(bit, sign: false)),
      areaOnly: true,
    ));
  }

  final pairs = summarizeIdConflicts(
    comparisons: comparisons,
    width: width,
    appearances: ids.appearances,
  );
  final conflicts = <DepthConflict>[];
  final eye = camera.position;
  final inverse = Matrix4.inverted(camera.getViewTransform(ids.size));
  final perspective =
      camera.projection.getProjectionMatrixForViewport(ids.size).storage[11] !=
      0.0;
  // How far the view ray through pixel (x, y) travels to the nearer item's
  // bounds, measured from the eye.
  double? rayDistance(int x, int y, RenderItem a, RenderItem b) {
    final ndcX = (x + 0.5) / width * 2 - 1;
    final ndcY = 1 - (y + 0.5) / height * 2;
    Vector3 unproject(double z) {
      final point = inverse.transform(Vector4(ndcX, ndcY, z, 1));
      return point.xyz / point.w;
    }

    final start = unproject(0.25);
    final direction = (unproject(0.75) - start)..normalize();
    final origin = perspective ? eye : start;
    final hits = [
      a.rayBoundsDistance(origin, direction),
      b.rayBoundsDistance(origin, direction),
    ].whereType<double>();
    if (hits.isEmpty) return null;
    final along = hits.reduce(math.min);
    return perspective ? along : along + (start - eye).length;
  }

  double boundsDistance(RenderItem item) {
    final bounds = item.worldBounds;
    if (bounds == null) return 0.0;
    final closest = Vector3.copy(eye)..clamp(bounds.min, bounds.max);
    return closest.distanceTo(eye);
  }

  for (final entry in pairs.entries) {
    final summary = entry.value;
    if (summary.count < minPixels) continue;
    final a = items[entry.key % _kIdSpan - 1];
    final b = items[entry.key ~/ _kIdSpan - 1];
    final along = [
      rayDistance(summary.firstX, summary.firstY, a, b),
      rayDistance(summary.lastX, summary.lastY, a, b),
    ].whereType<double>();
    conflicts.add(
      DepthConflict(
        nodeA: a.sourceNode is Node ? a.sourceNode as Node : null,
        nodeB: b.sourceNode is Node ? b.sourceNode as Node : null,
        pixelCount: summary.count,
        bounds: ui.Rect.fromLTRB(
          summary.minX / width,
          summary.minY / height,
          (summary.maxX + 1) / width,
          (summary.maxY + 1) / height,
        ),
        distance: along.isNotEmpty
            ? along.reduce(math.min)
            : math.min(boundsDistance(a), boundsDistance(b)),
      ),
    );
  }
  conflicts.sort((x, y) => y.pixelCount.compareTo(x.pixelCount));
  return DepthConflictReport(
    width: width,
    height: height,
    conflicts: conflicts,
  );
}

/// The pixels of one conflicting pair of ids.
@visibleForTesting
class IdConflictSummary {
  int count = 0;
  int minX = 1 << 30;
  int minY = 1 << 30;
  int maxX = -1;
  int maxY = -1;

  /// The first and last pixels counted, in scan order.
  int firstX = 0;
  int firstY = 0;
  int lastX = 0;
  int lastY = 0;

  void add(int x, int y) {
    if (count++ == 0) {
      firstX = x;
      firstY = y;
    }
    lastX = x;
    lastY = y;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }
}

// Ids span 24 bits. Pair keys combine two by arithmetic, not shifts, so they
// stay exact on the web, where integer shifts are 32-bit.
const int _kIdSpan = 1 << 24;

/// Two id images to compare. With `areaOnly`, a changed pixel counts only
/// when at least [kDepthConflictAreaNeighbors] of its eight neighbors changed
/// too: one surface winning a patch the other held, not a one-pixel line where
/// an edge, a crossing, or a sliver thinner than a pixel moved under a
/// sub-pixel change.
typedef IdComparison = ({Uint32List first, Uint32List second, bool areaOnly});

/// How many of a changed pixel's eight neighbors must also change for an
/// `areaOnly` comparison to count it. A moved line touches at most three.
@internal
const int kDepthConflictAreaNeighbors = 4;

/// Pairs of ids that own one pixel in the first image of a comparison and
/// another in the second, keyed `low + high * 2^24`. Each pixel counts once,
/// for the first comparison that disagrees on it. Pixels where either side
/// is background (0) are a clip boundary, not a fight, and are skipped, as
/// are pairs of one appearance (`appearances[id]`) that draw alike.
@visibleForTesting
Map<int, IdConflictSummary> summarizeIdConflicts({
  required List<IdComparison> comparisons,
  required int width,
  List<int>? appearances,
}) {
  final pairs = <int, IdConflictSummary>{};
  if (comparisons.isEmpty) return pairs;
  final length = comparisons.first.first.length;
  final height = length ~/ width;
  bool changed(IdComparison comparison, int i) {
    final a = comparison.first[i];
    final b = comparison.second[i];
    if (a == b || a == 0 || b == 0) return false;
    return appearances == null || appearances[a] != appearances[b];
  }

  // Whether enough of pixel i's neighbors changed too.
  bool inArea(IdComparison comparison, int i) {
    final x = i % width;
    final y = i ~/ width;
    var count = 0;
    for (var dy = -1; dy <= 1; dy++) {
      if (y + dy < 0 || y + dy >= height) continue;
      for (var dx = -1; dx <= 1; dx++) {
        if ((dx == 0 && dy == 0) || x + dx < 0 || x + dx >= width) continue;
        if (changed(comparison, i + dy * width + dx) &&
            ++count >= kDepthConflictAreaNeighbors) {
          return true;
        }
      }
    }
    return false;
  }

  for (var i = 0; i < length; i++) {
    for (final comparison in comparisons) {
      if (!changed(comparison, i)) continue;
      if (comparison.areaOnly && !inArea(comparison, i)) continue;
      final a = comparison.first[i];
      final b = comparison.second[i];
      final key = a < b ? a + b * _kIdSpan : b + a * _kIdSpan;
      (pairs[key] ??= IdConflictSummary()).add(i % width, i ~/ width);
      break;
    }
  }
  return pairs;
}
