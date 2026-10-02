// CPU tests for the depth-precision machinery: the depth raster (reversed
// depth, layer offsets), reversed and infinite projections, the near-plane
// fit, and the nearest-depth BVH query. None of them needs a GPU.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/camera.dart' show buildRasterProjectionMatrix;
import 'package:flutter_scene/src/depth_conflicts.dart';
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/depth_raster.dart';
import 'package:flutter_scene/src/render/near_fit.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
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
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _BoundedGeometry extends _StubGeometry {
  _BoundedGeometry(this.bounds);

  final Aabb3 bounds;

  @override
  Aabb3? get localBounds => bounds;
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

RenderItem _itemWith(Aabb3 bounds) =>
    RenderItem(geometry: _StubGeometry(), material: _StubMaterial())
      ..worldBounds = bounds;

// Clip depth over w of a view-space point at planar depth [z] on the axis.
double _ndcDepth(Matrix4 projection, double z) {
  final clip = projection.transform(Vector4(0, 0, z, 1));
  return clip.z / clip.w;
}

void main() {
  group('DepthRaster', () {
    test('clears to and tests toward the near plane of each convention', () {
      const standard = DepthRaster();
      const reversed = DepthRaster(reversed: true, floatDepth: true);
      expect(standard.clearDepth, 1.0);
      expect(standard.nearerOrEqual, gpu.CompareFunction.lessEqual);
      expect(reversed.clearDepth, 0.0);
      expect(reversed.farClipDepth, 0.0);
      expect(reversed.nearerOrEqual, gpu.CompareFunction.greaterEqual);
      expect(
        reversed.compare(gpu.CompareFunction.less),
        gpu.CompareFunction.greater,
      );
      expect(
        reversed.compare(gpu.CompareFunction.always),
        gpu.CompareFunction.always,
      );
      expect(
        reversed.compare(gpu.CompareFunction.equal),
        gpu.CompareFunction.equal,
      );
      expect(
        standard.compare(gpu.CompareFunction.less),
        gpu.CompareFunction.less,
      );
    });

    test('layer offsets move toward the camera in each convention', () {
      final out = Float32List(2);
      const DepthRaster().writeOffset(8, out, 0);
      expect(out[0], 0.0);
      expect(out[1], closeTo(-8 / 16777216, 1e-12));

      const DepthRaster(
        reversed: true,
        floatDepth: true,
      ).writeOffset(8, out, 0);
      expect(out[0], closeTo(8 / 8388608, 1e-12));
      expect(out[1], 0.0);

      const DepthRaster(reversed: true).writeOffset(8, out, 0);
      expect(out[0], 0.0);
      expect(out[1], closeTo(8 / 16777216, 1e-12));
    });

    test('the current draw offset combines a layer and a tie-break rank', () {
      const step = 1 / 16777216;
      setCurrentDrawDepthOffset(const DepthRaster(), 1, 2, pixelSlope: 2.0);
      expect(currentDrawDepthOffset[1], closeTo(-8 * step, 1e-12));
      expect(currentDrawDepthOffset[3], 0.0);
      // A quarter pixel of slope toward the camera (standard depth: down).
      expect(currentDrawDepthSlope[0], closeTo(-0.5, 1e-9));
      expect(currentDrawDepthSlope[1], 0.0);
      expect(currentDrawDepthSlope[2], 0.0);

      // The tie-break pushes back three ranks per material rank, and one per
      // instance rank in the vertex stage.
      const tie = DepthRaster(tieBreak: true);
      setCurrentDrawDepthOffset(tie, 0, 2, pixelSlope: 2.0);
      expect(currentDrawDepthOffset[1], closeTo(24 * step, 1e-12));
      expect(currentDrawDepthOffset[3], closeTo(4 * step, 1e-12));
      expect(currentDrawDepthSlope[0], 0.0);
      expect(currentDrawDepthSlope[1], closeTo(2 / 16, 1e-9));
      expect(currentDrawDepthSlope[2], closeTo(2 * 6 / 16, 1e-9));

      // An explicit layer overrides the automatic rank, and a negative one
      // moves back past the deepest rank.
      setCurrentDrawDepthOffset(tie, 1, 2);
      expect(currentDrawDepthOffset[1], closeTo(-8 * step, 1e-12));
      expect(currentDrawDepthOffset[3], 0.0);
      setCurrentDrawDepthOffset(tie, -1, 2);
      expect(currentDrawDepthOffset[1], closeTo(40 * step, 1e-12));

      // A probe nudge adds a step and a sixty-fourth of a pixel.
      setCurrentDrawDepthOffset(const DepthRaster(), 0, 0, nudge: 1);
      expect(currentDrawDepthOffset[1], closeTo(-step, 1e-12));
      clearCurrentDrawDepthOffset();
      expect(currentDrawDepthOffset, everyElement(0.0));
      expect(currentDrawDepthSlope, everyElement(0.0));
    });

    test('the precision line states the storage, the fit, and the gap', () {
      final standard = depthPrecisionSummary(
        reversed: false,
        floatDepth: false,
        authoredNear: 0.1,
      );
      expect(standard, contains('depth is 24-bit, near 0.10 m.'));
      // Eight steps of d^2 / (near 2^24) fit in 1 cm out to about 46 m.
      expect(standard, contains('to about 46 m face-on'));
      final fitted = depthPrecisionSummary(
        reversed: false,
        floatDepth: true,
        authoredNear: 0.1,
        fittedNear: 1.6,
      );
      expect(fitted, contains('near 0.10 m, fitted to 1.6 m'));
      expect(fitted, contains('to about 183 m'));
      final reversed = depthPrecisionSummary(
        reversed: true,
        floatDepth: true,
        authoredNear: 0.1,
      );
      expect(reversed, contains('32-bit float, reversed'));
      expect(reversed, contains('beyond 10 km'));
    });

    test('pixel depth slope is the depth constant over the focal length', () {
      final reversed = buildRasterProjectionMatrix(
        PerspectiveProjection(fovRadiansY: math.pi / 2, near: 0.5, far: 400),
        const ui.Size(1600, 900),
        reversed: true,
      )!;
      // A 90 degree view 900 pixels tall has a 450 pixel focal length, and
      // reversed depth is far * near / (far - near) over w.
      expect(
        pixelDepthSlope(reversed, 900),
        closeTo(400 * 0.5 / 399.5 / 450, 1e-9),
      );
      final orthographic = buildRasterProjectionMatrix(
        OrthographicProjection(
          size: const OrthographicSize.height(10),
          near: 0,
          far: 100,
        ),
        const ui.Size(1600, 900),
        reversed: false,
      )!;
      // 10 units over 900 pixels, with depth 1/100 per unit.
      expect(pixelDepthSlope(orthographic, 900), closeTo(10 / 900 / 100, 1e-9));
    });

    test('world step size follows each convention', () {
      const standard = DepthRaster();
      const reversed = DepthRaster(reversed: true, floatDepth: true);
      // 24-bit at 100 m with near 0.1 is about 6 mm a step.
      expect(standard.worldStepAt(100, 0.1), closeTo(0.00596, 0.00001));
      // Reversed float is near-uniform in relative terms.
      expect(reversed.worldStepAt(100, 0.1), closeTo(100 / 8388608, 1e-9));
    });
  });

  group('raster projections', () {
    const size = ui.Size(1600, 900);

    test('reversed perspective maps near to 1 and far to 0', () {
      final projection = PerspectiveProjection(near: 0.5, far: 400);
      final reversed = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: true,
      )!;
      expect(_ndcDepth(reversed, 0.5), closeTo(1.0, 1e-6));
      expect(_ndcDepth(reversed, 400), closeTo(0.0, 1e-6));
      final standard = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: false,
      )!;
      expect(_ndcDepth(standard, 0.5), closeTo(0.0, 1e-6));
      expect(_ndcDepth(standard, 400), closeTo(1.0, 1e-6));
      // The lateral rows are untouched.
      expect(reversed.getRow(0), standard.getRow(0));
      expect(reversed.getRow(1), standard.getRow(1));
      expect(reversed.getRow(3), standard.getRow(3));
    });

    test('an infinite far plane maps distance to near over distance', () {
      final projection = PerspectiveProjection(
        near: 0.25,
        far: double.infinity,
      );
      final reversed = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: true,
      )!;
      expect(_ndcDepth(reversed, 0.25), closeTo(1.0, 1e-6));
      expect(_ndcDepth(reversed, 1000), closeTo(0.25 / 1000, 1e-6));
      final standard = projection.getProjectionMatrix(16 / 9);
      expect(_ndcDepth(standard, 0.25), closeTo(0.0, 1e-6));
      expect(_ndcDepth(standard, 1e6), closeTo(1.0, 1e-6));
      for (final v in standard.storage) {
        expect(v.isFinite, isTrue);
      }
    });

    test('a fitted near plane replaces a smaller authored one', () {
      final projection = PerspectiveProjection(near: 0.1, far: 100);
      final fitted = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: false,
        near: 2.0,
      )!;
      expect(_ndcDepth(fitted, 2.0), closeTo(0.0, 1e-6));
      // A fit below the authored plane never lowers it.
      final kept = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: false,
        near: 0.01,
      )!;
      expect(_ndcDepth(kept, 0.1), closeTo(0.0, 1e-6));
    });

    test('reversed orthographic stays linear', () {
      final projection = OrthographicProjection(near: -10, far: 90);
      final reversed = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: true,
      )!;
      expect(_ndcDepth(reversed, -10), closeTo(1.0, 1e-6));
      expect(_ndcDepth(reversed, 90), closeTo(0.0, 1e-6));
      expect(_ndcDepth(reversed, 40), closeTo(0.5, 1e-6));
    });

    test('a custom projection reverses by its depth row', () {
      final matrix = makePerspectiveMatrix(1.0, 1.5, 1.0, 50.0);
      final reversed = reverseDepthRow(matrix);
      // makePerspectiveMatrix is GL [-1, 1]; reversing maps z/w to 1 - z/w.
      for (final z in [1.0, 5.0, 50.0]) {
        final standard = matrix.transform(Vector4(0, 0, -z, 1));
        final flipped = reversed.transform(Vector4(0, 0, -z, 1));
        expect(
          flipped.z / flipped.w,
          closeTo(1.0 - standard.z / standard.w, 1e-6),
        );
      }
    });

    test('culling an infinite projection keeps a non-culling far plane', () {
      final camera = PerspectiveCamera(
        position: Vector3(0, 0, 0),
        target: Vector3(0, 0, 1),
        fovNear: 0.1,
        fovFar: double.infinity,
      );
      final frustum = cullingFrustumOf(camera, size);
      for (final plane in [
        frustum.plane0,
        frustum.plane1,
        frustum.plane2,
        frustum.plane3,
        frustum.plane4,
        frustum.plane5,
      ]) {
        expect(plane.constant.isFinite, isTrue);
        expect(plane.normal.x.isFinite, isTrue);
      }
      final far = Aabb3.minMax(Vector3(-1, -1, 1e7), Vector3(1, 1, 1e7 + 2));
      expect(frustum.intersectsWithAabb3(far), isTrue);
      final behind = Aabb3.minMax(Vector3(-1, -1, -10), Vector3(1, 1, -8));
      expect(frustum.intersectsWithAabb3(behind), isFalse);
    });
  });

  group('near-plane fit', () {
    test('keeps the authored plane when something reaches it', () {
      expect(
        fittedNearPlane(visibleDepth: 0.05, authoredNear: 0.1, far: 1000),
        0.1,
      );
      expect(
        fittedNearPlane(visibleDepth: -3, authoredNear: 0.1, far: 1000),
        0.1,
      );
    });

    test('takes most of the visible depth, snapped to a power of root two', () {
      final fitted = fittedNearPlane(
        visibleDepth: 10,
        authoredNear: 0.1,
        far: 1000,
      );
      expect(fitted, lessThanOrEqualTo(10 * kNearFitSafety));
      expect(fitted, greaterThan(10 * kNearFitSafety / math.sqrt2));
      final halfSteps = math.log(fitted) / math.ln2 * 2;
      expect(halfSteps, closeTo(halfSteps.roundToDouble(), 1e-9));
    });

    test('never passes a tenth of the far plane', () {
      expect(
        fittedNearPlane(visibleDepth: 500, authoredNear: 0.1, far: 100),
        lessThanOrEqualTo(10),
      );
    });

    test('holds the previous plane until the fit can double it', () {
      final first = fittedNearPlane(
        visibleDepth: 10,
        authoredNear: 0.1,
        far: 1000,
      );
      // A slightly larger visible depth keeps the plane.
      expect(
        fittedNearPlane(
          visibleDepth: 12,
          authoredNear: 0.1,
          far: 1000,
          previous: first,
        ),
        first,
      );
      // Moving closer than the plane allows drops it at once.
      final closer = fittedNearPlane(
        visibleDepth: first * 0.5,
        authoredNear: 0.1,
        far: 1000,
        previous: first,
      );
      expect(closer, lessThanOrEqualTo(first * 0.5 * kNearFitSafety));
      // A fit at least twice as far moves up.
      expect(
        fittedNearPlane(
          visibleDepth: 40,
          authoredNear: 0.1,
          far: 1000,
          previous: first,
        ),
        greaterThanOrEqualTo(first * 2),
      );
    });

    test('keeps the previous plane when nothing is visible', () {
      expect(
        fittedNearPlane(
          visibleDepth: double.infinity,
          authoredNear: 0.1,
          far: 1000,
          previous: 3.0,
        ),
        3.0,
      );
    });

    test('a ground plane under the camera bounds depth by its height', () {
      // Eye 4 m above an infinite-ish ground, looking along +z.
      final bound = aabbDepthLowerBound(
        -500,
        -1,
        -500,
        500,
        0,
        500, //
        0,
        3,
        0, //
        0,
        0,
        1, //
        0.5,
      );
      expect(bound, closeTo(1.5, 1e-9));
      // A box straight ahead bounds by its planar depth.
      final ahead = aabbDepthLowerBound(
        -1,
        -1,
        20,
        1,
        1,
        22, //
        0,
        0,
        0, //
        0,
        0,
        1, //
        0.5,
      );
      expect(ahead, closeTo(20, 1e-9));
    });

    test('a spread instanced set is bounded per instance', () {
      // A ring of 1 m boxes 100 m around an eye below their bottoms: the
      // aggregate bounds hold the eye's column, but every box is far away.
      final instances = [
        for (var i = 0; i < 16; i++)
          Matrix4.translation(
            Vector3(
              math.sin(i / 16 * math.pi * 2) * 100,
              10,
              math.cos(i / 16 * math.pi * 2) * 100,
            ),
          ),
      ];
      final item =
          RenderItem(
              geometry: _BoundedGeometry(
                Aabb3.minMax(Vector3.all(-0.5), Vector3.all(0.5)),
              ),
              material: _StubMaterial(),
            )
            ..visible = true
            ..instanceTransforms = instances
            ..worldBounds = Aabb3.minMax(
              Vector3(-100.5, 9.5, -100.5),
              Vector3(100.5, 10.5, 100.5),
            );
      final eye = Vector3(0, 0, 0);
      final forward = Vector3(0, 0, 1);
      final camera = PerspectiveCamera(
        position: eye,
        target: forward,
        fovNear: 0.1,
        fovFar: 1000,
      );
      final frustum = cullingFrustumOf(camera, const ui.Size(800, 600));
      final bound = item.depthLowerBound(frustum, eye, forward, 0.7, 1e9);
      // Far beyond the 9.5 m to the aggregate box.
      expect(bound, greaterThan(50));
    });

    test('the BVH query matches a brute-force minimum', () {
      final random = math.Random(42);
      final items = <RenderItem>[];
      for (var i = 0; i < 300; i++) {
        final x = random.nextDouble() * 200 - 100;
        final y = random.nextDouble() * 20;
        final z = random.nextDouble() * 200 - 100;
        final s = random.nextDouble() * 4 + 0.5;
        items.add(
          _itemWith(
            Aabb3.minMax(Vector3(x, y, z), Vector3(x + s, y + s, z + s)),
          ),
        );
      }
      final bvh = Bvh.build(items);
      final eye = Vector3(3, 6, -40);
      final forward = Vector3(0.1, -0.2, 1)..normalize();
      final camera = PerspectiveCamera(
        position: eye,
        target: eye + forward,
        fovNear: 0.1,
        fovFar: 1000,
      );
      const size = ui.Size(1000, 600);
      final frustum = cullingFrustumOf(camera, size);
      const cosHalf = 0.6;
      double boundOf(RenderItem item) {
        final b = item.worldBounds!;
        return aabbDepthLowerBound(
          b.min.x,
          b.min.y,
          b.min.z,
          b.max.x,
          b.max.y,
          b.max.z,
          eye.x,
          eye.y,
          eye.z,
          forward.x,
          forward.y,
          forward.z,
          cosHalf,
        );
      }

      var expected = double.infinity;
      for (final item in items) {
        if (!frustum.intersectsWithAabb3(item.worldBounds!)) continue;
        expected = math.min(expected, boundOf(item));
      }
      var visits = 0;
      final found = bvh.nearestBound(frustum, eye, forward, cosHalf, (
        item,
        best,
      ) {
        visits++;
        return boundOf(item);
      });
      expect(found, closeTo(expected, 1e-9));
      // Pruning visits far fewer leaves than the scene holds.
      expect(visits, lessThan(items.length ~/ 2));
    });
  });

  group('near-plane advisory', () {
    test('reports the precision a fit would recover when off', () {
      final message = nearPlaneAdvisory(
        const NearPlaneFit(
          authoredNear: 0.1,
          fittedNear: 0.1,
          visibleDepth: 9.0,
          nearestNode: null,
        ),
        fitEnabled: false,
      );
      expect(message, contains('Scene.fitNearPlane'));
      expect(message, contains('0.10 m'));
      expect(message, contains('x the precision'));
    });

    test('names a large node holding the eye when the fit is pinned', () {
      final message = nearPlaneAdvisory(
        const NearPlaneFit(
          authoredNear: 0.1,
          fittedNear: 0.1,
          visibleDepth: 0.0,
          nearestNode: null,
          nearestContainsEye: true,
          nearestExtent: 800,
        ),
        fitEnabled: true,
        nodeName: 'sky_sphere',
      );
      expect(message, contains("'sky_sphere'"));
      expect(message, contains('800 m across'));
    });

    test('stays quiet for ordinary nearby geometry', () {
      expect(
        nearPlaneAdvisory(
          const NearPlaneFit(
            authoredNear: 0.1,
            fittedNear: 0.1,
            visibleDepth: 0.0,
            nearestNode: null,
            nearestContainsEye: true,
            nearestExtent: 3,
          ),
          fitEnabled: true,
        ),
        isNull,
      );
      expect(
        nearPlaneAdvisory(
          const NearPlaneFit(
            authoredNear: 0.1,
            fittedNear: 0.1,
            visibleDepth: 0.2,
            nearestNode: null,
          ),
          fitEnabled: false,
        ),
        isNull,
      );
    });
  });

  group('.fmat depth_layer', () {
    test('parses into the AST and the sidecar', () {
      final m = parseFmat('''
material { name: "Sign", depth_layer: 2 }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.depthLayer, 2);
      expect(buildSidecar(m)['depth_layer'], 2);

      final negative = parseFmat('''
material { name: "Ground", depth_layer: -1 }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(negative.depthLayer, -1);

      final byDefault = parseFmat('''
material { name: "Plain" }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(byDefault.depthLayer, 0);
      expect(buildSidecar(byDefault).containsKey('depth_layer'), isFalse);
    });

    test('rejects a fraction or an out-of-range layer', () {
      for (final bad in ['1.5', '9', '-12', 'high']) {
        expect(
          () => parseFmat('''
material { name: "X", depth_layer: $bad }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
          throwsA(isA<FmatException>()),
        );
      }
    });
  });

  group('depth conflict probe', () {
    test('perturbing the depth row keeps the far plane and the screen', () {
      final projection = PerspectiveProjection(near: 0.1, far: 500);
      for (final reversed in [false, true]) {
        final matrix = buildRasterProjectionMatrix(
          projection,
          const ui.Size(800, 600),
          reversed: reversed,
        )!;
        final perturbed = perturbDepthRow(matrix, 0.03, reversed: reversed);
        for (final z in [1.0, 40.0, 500.0]) {
          final a = matrix.transform(Vector4(0.3, -0.2, z, 1));
          final b = perturbed.transform(Vector4(0.3, -0.2, z, 1));
          expect(b.x / b.w, closeTo(a.x / a.w, 1e-6));
          expect(b.y / b.w, closeTo(a.y / a.w, 1e-6));
        }
        // The far plane maps where it did.
        final far = perturbed.transform(Vector4(0, 0, 500, 1));
        expect(far.z / far.w, closeTo(reversed ? 0.0 : 1.0, 1e-5));
        // Mid-range depth moves.
        final mid = matrix.transform(Vector4(0, 0, 40, 1));
        final midPerturbed = perturbed.transform(Vector4(0, 0, 40, 1));
        expect(
          (midPerturbed.z / midPerturbed.w - mid.z / mid.w).abs(),
          greaterThan(1e-6),
        );
      }
    });

    test('summarizes the pixels whose owner changes, by pair', () {
      // A 4x2 image: ids 1 and 2 fight at two pixels, 3 holds, background
      // changes to an id at a clip edge and is ignored.
      final reference = Uint32List.fromList([1, 1, 2, 3, 0, 1, 2, 3]);
      final variantA = Uint32List.fromList([2, 1, 2, 3, 3, 1, 2, 3]);
      final variantB = Uint32List.fromList([1, 1, 1, 3, 0, 1, 2, 0]);
      final pairs = summarizeIdConflicts(
        comparisons: [
          (first: reference, second: variantA, areaOnly: false),
          (first: reference, second: variantB, areaOnly: false),
        ],
        width: 4,
      );
      expect(pairs.length, 1);
      final summary = pairs.values.single;
      expect(summary.count, 2);
      expect(
        [summary.minX, summary.minY, summary.maxX, summary.maxY],
        [0, 0, 2, 0],
      );
    });

    test('counts area changes, not moved lines', () {
      // A 6x6 image: id 1 fills the left two columns and id 2 the rest. A
      // second render moves the edge one column (a line) and flips a 2x3
      // patch inside id 2 (a fight).
      final reference = Uint32List.fromList([
        for (var y = 0; y < 6; y++)
          for (var x = 0; x < 6; x++) x < 2 ? 1 : 2,
      ]);
      final moved = Uint32List.fromList(reference);
      for (var y = 0; y < 6; y++) {
        moved[y * 6 + 2] = 1;
      }
      for (var y = 1; y < 4; y++) {
        moved[y * 6 + 4] = 1;
        moved[y * 6 + 5] = 1;
      }
      final pairs = summarizeIdConflicts(
        comparisons: [(first: reference, second: moved, areaOnly: true)],
        width: 6,
      );
      // The moved column's pixels have at most two changed neighbors and the
      // patch's rim three; only its middle row, with five, counts.
      final summary = pairs.values.single;
      expect(summary.count, 2);
      expect(
        [summary.minX, summary.minY, summary.maxX, summary.maxY],
        [4, 2, 5, 2],
      );
      expect(
        summarizeIdConflicts(
          comparisons: [(first: reference, second: moved, areaOnly: false)],
          width: 6,
        ).values.single.count,
        12,
      );
    });

    test('counts every pair of ids, but never background', () {
      // Untested surfaces draw as background (0), like empty pixels.
      final reference = Uint32List.fromList([1, 2, 0, 3]);
      final variant = Uint32List.fromList([2, 1, 3, 0]);
      final pairs = summarizeIdConflicts(
        comparisons: [(first: reference, second: variant, areaOnly: false)],
        width: 4,
      );
      expect(pairs.length, 1);
      expect(pairs.keys.single, 1 + 2 * (1 << 24));
      expect(pairs.values.single.count, 2);
    });

    test('keys pairs exactly past 32-bit ids', () {
      const big = 9000000;
      final reference = Uint32List.fromList([big]);
      final variant = Uint32List.fromList([7]);
      final pairs = summarizeIdConflicts(
        comparisons: [(first: reference, second: variant, areaOnly: false)],
        width: 1,
      );
      final key = pairs.keys.single;
      expect(key % (1 << 24), 7);
      expect(key ~/ (1 << 24), big);
    });

    test('describes a report for a log', () {
      expect(
        const DepthConflictReport(
          width: 10,
          height: 10,
          conflicts: [],
        ).describe(),
        contains('No depth conflicts'),
      );
      final node = Node(name: 'barriers');
      final report = DepthConflictReport(
        width: 100,
        height: 50,
        conflicts: [
          DepthConflict(
            nodeA: node,
            nodeB: Node(name: 'paint'),
            pixelCount: 120,
            bounds: const ui.Rect.fromLTRB(0.1, 0.2, 0.3, 0.4),
            distance: 42,
          ),
        ],
      );
      final text = report.describe();
      expect(text, contains("'barriers' and 'paint' trade 120 pixels"));
      expect(text, contains('2.40%'));
      expect(report.conflictPixelCount, 120);
    });
  });
}
