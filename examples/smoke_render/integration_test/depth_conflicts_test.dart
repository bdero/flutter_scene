// The depth conflict probe and coplanar lint against cases that once fooled
// them: overlaps sharing a material, a cutout that shows nothing, a surface
// moving while the probe waits for the GPU, and a dense mesh the lint must get
// through quickly.
//
// Not part of the smoke matrix. Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/depth_conflicts_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/coplanar_overlaps.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _size = 256;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A 2 m quad in the xy plane, in one vertex color.
  MeshGeometry quad(vm.Vector4 color) => MeshGeometry.fromArrays(
    positions: Float32List.fromList([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]),
    colors: Float32List.fromList([
      for (var i = 0; i < 4; i++) ...[color.x, color.y, color.z, color.w],
    ]),
    indices: const [0, 1, 2, 0, 2, 3],
  );

  PerspectiveCamera camera() => PerspectiveCamera(
    position: vm.Vector3(0, 0, 5),
    target: vm.Vector3.zero(),
  );

  // Shows [scene] through [view] and renders a frame per pump.
  Future<RenderRepaintBoundary> show(
    WidgetTester tester,
    Scene scene,
    Camera view,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: _size.toDouble(),
              height: _size.toDouble(),
              child: CustomPaint(painter: _ScenePainter(scene, view)),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  }

  testWidgets('overlaps sharing a material still fight', (tester) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    final shared = UnlitMaterial()..doubleSided = true;
    scene.add(
      Node(name: 'red', mesh: Mesh(quad(vm.Vector4(1, 0, 0, 1)), shared)),
    );
    scene.add(
      Node(name: 'green', mesh: Mesh(quad(vm.Vector4(0, 1, 0, 1)), shared))
        ..position = vm.Vector3(0.5, 0, 0),
    );
    final view = camera();
    await show(tester, scene, view);

    final report = await scene.probeDepthConflicts(
      camera: view,
      width: _size,
      height: _size,
    );
    final overlaps = scene.findCoplanarOverlaps(camera: view);
    // ignore: avoid_print
    print(
      'DEPTH_TEST shared material: pixels=${report.conflictPixelCount} '
      'overlaps=${overlaps.length}',
    );
    expect(report.conflictPixelCount, greaterThan(1000));
    expect(overlaps, isNotEmpty);
  });

  testWidgets('a cutout covers only what it shows', (tester) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    scene.add(
      Node(
        name: 'opaque',
        mesh: Mesh(
          quad(vm.Vector4(1, 1, 1, 1)),
          UnlitMaterial()..doubleSided = true,
        ),
      ),
    );
    scene.add(
      Node(
        name: 'cutout',
        mesh: Mesh(
          quad(vm.Vector4(1, 1, 1, 1)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(1, 0, 0, 0)
            ..alphaMode = AlphaMode.mask
            ..doubleSided = true,
        ),
      ),
    );
    final view = camera();
    await show(tester, scene, view);

    final report = await scene.probeDepthConflicts(
      camera: view,
      width: _size,
      height: _size,
    );
    // ignore: avoid_print
    print('DEPTH_TEST cutout: pixels=${report.conflictPixelCount}');
    expect(report.conflicts, isEmpty, reason: report.describe());
  });

  testWidgets('motion while the probe waits does not count', (tester) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    scene.add(
      Node(
        name: 'back',
        mesh: Mesh(
          quad(vm.Vector4(0, 0, 1, 1)),
          UnlitMaterial()..doubleSided = true,
        ),
      ),
    );
    final front = Node(
      name: 'front',
      mesh: Mesh(
        quad(vm.Vector4(1, 1, 0, 1)),
        UnlitMaterial()..doubleSided = true,
      ),
    )..position = vm.Vector3(0, 0, 1);
    scene.add(front);
    final view = camera();
    await show(tester, scene, view);

    // Slide the front quad and tick the scene every millisecond, the way an
    // animation runs while the probe waits for the GPU.
    var moves = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      moves++;
      front.position = vm.Vector3((moves % 7) * 0.1 - 0.3, 0, 1);
      scene.update(1 / 60);
    });
    final report = await scene.probeDepthConflicts(
      camera: view,
      width: _size,
      height: _size,
    );
    timer.cancel();
    // ignore: avoid_print
    print(
      'DEPTH_TEST motion: pixels=${report.conflictPixelCount} moves=$moves',
    );
    // The web backend runs as it encodes and reads back without yielding, so
    // nothing gets the chance to move there.
    if (!kIsWeb) {
      expect(moves, greaterThan(0), reason: 'nothing moved during the probe');
    }
    expect(report.conflicts, isEmpty, reason: report.describe());
  });

  testWidgets('only reversed camera depth pays for float', (tester) async {
    await Scene.initializeStaticResources();
    final reversed = gpu.reversedDepthStencilFormat;
    final forward = gpu.gpuContext.defaultDepthStencilFormat;
    // ignore: avoid_print
    print(
      'DEPTH_TEST formats: reversed=${reversed.name} forward=${forward.name}',
    );
    // Forward depth (shadow maps, masks) keeps the 24-bit default on web, so
    // a float format's cost lands only on reversed camera passes.
    if (kIsWeb) expect(forward, gpu.PixelFormat.d24UnormS8Uint);
  });

  testWidgets('dense coplanar overlaps keep the lint in its slice', (
    tester,
  ) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    // Two coplanar 100 by 100 grids, 20,000 triangles each, half overlapping.
    MeshGeometry grid() {
      const cells = 100;
      const step = 0.1;
      return MeshGeometry.fromArrays(
        positions: Float32List.fromList([
          for (var i = 0; i <= cells; i++)
            for (var j = 0; j <= cells; j++) ...[i * step, 0.0, j * step],
        ]),
        indices: [
          for (var i = 0; i < cells; i++)
            for (var j = 0; j < cells; j++) ...[
              i * (cells + 1) + j,
              i * (cells + 1) + j + 1,
              (i + 1) * (cells + 1) + j + 1,
              i * (cells + 1) + j,
              (i + 1) * (cells + 1) + j + 1,
              (i + 1) * (cells + 1) + j,
            ],
        ],
      );
    }

    scene.add(Node(name: 'a', mesh: Mesh(grid(), UnlitMaterial())));
    scene.add(
      Node(name: 'b', mesh: Mesh(grid(), UnlitMaterial()))
        ..position = vm.Vector3(5, 0, 0),
    );
    await show(tester, scene, camera());

    // The longest 2 ms slice of one scan, and how many slices it took.
    ({int longest, int slices, int overlaps}) scanInSlices() {
      // ignore: invalid_use_of_internal_member
      final scan = CoplanarOverlapScan(scene.renderScene.items);
      var longest = 0;
      var slices = 0;
      while (true) {
        final watch = Stopwatch()..start();
        final done = scan.advance(const Duration(milliseconds: 2));
        watch.stop();
        slices++;
        if (watch.elapsedMicroseconds > longest) {
          longest = watch.elapsedMicroseconds;
        }
        if (done) break;
      }
      return (longest: longest, slices: slices, overlaps: scan.result!.length);
    }

    // The first scan also pays for compiling the scan's code (debug builds
    // run it on the JIT), so the measured one is a repeat.
    scanInSlices();
    final repeat = scanInSlices();
    // ignore: avoid_print
    print(
      'DEPTH_TEST dense lint: slices=${repeat.slices} '
      'longest=${repeat.longest / 1000} ms overlaps=${repeat.overlaps}',
    );
    expect(repeat.overlaps, 1);
    // A 2 ms slice may run one bounded step past its budget.
    if (!kIsWeb) expect(repeat.longest, lessThan(6000));
  });

  testWidgets('the coplanar lint gets through a dense mesh', (tester) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    // 16,128 triangles, nearly every one its own plane.
    scene.add(
      Node(
        name: 'sphere',
        mesh: Mesh(SphereGeometry(segments: 128, rings: 64), UnlitMaterial()),
      ),
    );
    await show(tester, scene, camera());

    final watch = Stopwatch()..start();
    final overlaps = scene.findCoplanarOverlaps();
    watch.stop();
    // ignore: avoid_print
    print(
      'DEPTH_TEST lint sphere: ${watch.elapsedMicroseconds / 1000} ms '
      'overlaps=${overlaps.length}',
    );
    expect(overlaps, isEmpty);
    // Searching every plane per triangle took about a quarter second here.
    if (!kIsWeb) expect(watch.elapsedMilliseconds, lessThan(100));
  });
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.camera);
  final Scene scene;
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
