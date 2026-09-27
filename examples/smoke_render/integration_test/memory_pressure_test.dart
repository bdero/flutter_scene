// The pool and the surface's byte counters are engine internals; this test
// reaches them the way the package's own tests do.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The byte accounting and the release path, over real GPU textures. The unit
/// tests in `packages/flutter_scene/test` cover the wiring but cannot allocate,
/// so this is where the numbers are actually checked.

TransientTextureDescriptor _descriptor(String debugName) =>
    TransientTextureDescriptor.color(
      width: 128,
      height: 128,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      debugName: debugName,
    );

Future<void> _sendMemoryPressure() async {
  final data = const JSONMessageCodec().encodeMessage(<String, dynamic>{
    'type': 'memoryPressure',
  })!;
  final completed = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.system.name,
    data,
    (_) => completed.complete(),
  );
  await completed.future;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Scene.initializeStaticResources();
  });

  testWidgets('residentBytes sums the whole mip chain', (_) async {
    final pool = TransientTexturePool();
    expect(pool.residentBytes, 0);

    pool.beginFrame();
    final texture = pool.acquire(_descriptor('mip chain'));

    var expected = 0;
    for (var level = 0; level < texture.mipLevelCount; level++) {
      expected += texture.getMipLevelSizeInBytes(level);
    }
    expect(pool.residentBytes, expected);
  });

  testWidgets('every frame in flight is counted', (_) async {
    final pool = TransientTexturePool();
    pool.beginFrame();
    pool.acquire(_descriptor('frames in flight'));
    final oneFrame = pool.residentBytes;
    expect(oneFrame, greaterThan(0));

    pool.beginFrame();
    pool.acquire(_descriptor('frames in flight'));
    expect(pool.residentBytes, oneFrame * 2);
  });

  testWidgets('clear releases everything and acquire reallocates', (_) async {
    final pool = TransientTexturePool();
    pool.beginFrame();
    pool.acquire(_descriptor('reallocate'));
    expect(pool.residentBytes, greaterThan(0));

    pool.clear();
    expect(pool.residentBytes, 0);

    pool.acquire(_descriptor('reallocate'));
    expect(pool.residentBytes, greaterThan(0));
  });

  testWidgets('a texture already acquired survives a clear', (_) async {
    final pool = TransientTexturePool();
    pool.beginFrame();
    final held = pool.acquire(_descriptor('mid frame'));
    pool.clear();

    // The pass that acquired it still has a usable texture; only the pool's
    // claim was dropped. This is what makes clearing safe mid-frame.
    expect(held.getMipLevelSizeInBytes(0), greaterThan(0));
    expect(pool.acquire(_descriptor('mid frame')), isNot(same(held)));
  });

  testWidgets('memory pressure releases a live surface\'s targets', (_) async {
    final surface = Surface();
    final pool = surface.transientTexturePool();
    pool.beginFrame();
    pool.acquire(_descriptor('under pressure'));
    expect(surface.transientBytes, greaterThan(0));

    await _sendMemoryPressure();
    expect(surface.transientBytes, 0);
  });

  testWidgets('the automatic release can be turned off', (_) async {
    final surface = Surface();
    final pool = surface.transientTexturePool();
    pool.beginFrame();
    pool.acquire(_descriptor('opted out'));
    final held = surface.transientBytes;
    expect(held, greaterThan(0));

    releaseRenderTargetsOnMemoryPressure = false;
    addTearDown(() => releaseRenderTargetsOnMemoryPressure = true);
    await _sendMemoryPressure();
    expect(surface.transientBytes, held);

    // The listener is still registered, so turning it back on takes effect
    // without re-registering anything.
    releaseRenderTargetsOnMemoryPressure = true;
    await _sendMemoryPressure();
    expect(surface.transientBytes, 0);
  });

  testWidgets('releaseTransientRenderTargets reports what it freed', (_) async {
    final surface = Surface();
    final pool = surface.transientTexturePool();
    pool.beginFrame();
    pool.acquire(_descriptor('reported'));

    final held = surface.transientBytes;
    expect(held, greaterThan(0));
    expect(releaseTransientRenderTargets(), greaterThanOrEqualTo(held));
    expect(surface.transientBytes, 0);
  });

  // The rest of this file checks the accounting. This one checks that the
  // release is actually safe to do against a scene that is drawing, which is
  // the claim the automatic path rests on, since a frame in flight may still
  // be reading a texture the pool has just let go of.
  testWidgets('a scene keeps drawing with the pool shed every frame', (
    tester,
  ) async {
    final smoke = kSmokeScenes.firstWhere(
      (scene) => scene.id == 'soft_shadows',
      orElse: () => kSmokeScenes.first,
    );

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: kSmokeClear, body: SizedBox.expand()),
      ),
    );
    await tester.pump();
    await smoke.preload?.call();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kSmokeClear,
          body: Center(child: SmokeSceneView(smoke)),
        ),
      ),
    );

    final boundary =
        smokeSceneKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

    // Draw, then drop everything that frame built, and do it again. The pool
    // reallocates from scratch on every one of these.
    var everShed = false;
    for (var i = 0; i < 12; i++) {
      boundary.markNeedsPaint();
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (releaseTransientRenderTargets() > 0) everShed = true;
    }

    // Without this the loop would pass just as well if nothing ever drew.
    expect(
      everShed,
      isTrue,
      reason: 'no render targets were allocated, so nothing was under test',
    );

    boundary.markNeedsPaint();
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 64));

    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(
      _centerNonClearFraction(rgba, image.width, image.height),
      greaterThan(0.05),
      reason: 'the scene stopped drawing once the pool was shed each frame',
    );
  });

  // Cached static shadow tiles outlive the pool. A tile that borrowed a pooled
  // depth kept a framebuffer on it past the shed, and its next refresh drew
  // into the freed texture (a crash or GPU hang on Vulkan).
  testWidgets('cached static shadows keep drawing with the pool shed', (
    tester,
  ) async {
    final setup = kSmokeScenes
        .firstWhere((scene) => scene.id == 'soft_shadows')
        .setup();
    for (final node in setup.scene.root.children) {
      if (node.mesh != null) node.shadowStatic = true;
    }
    final holder = _CameraHolder(setup.camera);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kSmokeClear,
          body: Center(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: SizedBox(
                width: 256,
                height: 256,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ScenePainter(setup.scene, holder),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

    var everShed = false;
    for (var i = 0; i < 24; i++) {
      // Orbit far enough each frame that the near cascades leave their slack
      // and refresh their tiles.
      final angle = i * 0.6;
      holder.camera = PerspectiveCamera(
        position: vm.Vector3(5.0 * math.cos(angle), 3.1, 5.0 * math.sin(angle)),
        target: vm.Vector3(0, 0.2, 0),
      );
      boundary.markNeedsPaint();
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (releaseTransientRenderTargets() > 0) everShed = true;
    }
    expect(everShed, isTrue);

    boundary.markNeedsPaint();
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 64));

    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(
      _centerNonClearFraction(rgba, image.width, image.height),
      greaterThan(0.05),
      reason: 'the scene stopped drawing once the pool was shed each frame',
    );
  });

  // Once a scene has warmed up, drawing it again must not allocate: per-frame
  // uniform and instance data recycle through the transient pools and
  // render-graph attachments come back from the texture pool. Every smoke
  // scene is checked, so a feature that allocates per frame shows up by name.
  testWidgets('warmed-up smoke scenes render without allocating', (
    tester,
  ) async {
    int allocations() =>
        TransientArena.buffersCreated +
        ImmediatePoolTransients.buffersCreated +
        TransientTexturePool.texturesCreated;

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: kSmokeClear, body: SizedBox.expand()),
      ),
    );
    final offenders = <String>[];
    for (final smoke in kSmokeScenes) {
      await smoke.preload?.call();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: kSmokeClear,
            body: Center(child: SmokeSceneView(smoke, key: ValueKey(smoke.id))),
          ),
        ),
      );
      final boundary =
          smokeSceneKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          boundary.markNeedsPaint();
          await tester.pump(const Duration(milliseconds: 16));
          // Lets GPU completions arrive, as they would between real frames.
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }
      }

      await frames(30);
      final warm = allocations();
      await frames(60);
      final grew = allocations() - warm;
      if (grew > 0) offenders.add('${smoke.id} (+$grew)');
    }
    expect(
      offenders,
      isEmpty,
      reason: 'these scenes kept allocating GPU memory after warming up',
    );
  });

  testWidgets('the memory report counts render targets', (_) async {
    releaseTransientRenderTargets();

    final surface = Surface();
    final pool = surface.transientTexturePool();
    pool.beginFrame();
    pool.acquire(_descriptor('reported category'));

    final targets = takeMemoryReport().categories.firstWhere(
      (category) => category.name == 'render targets',
    );
    expect(targets.bytes, surface.transientBytes);
    expect(targets.bytes, greaterThan(0));
  });
}

/// The fraction of the middle of the frame that is not the clear color.
///
/// A deliberately coarse "did anything draw" check, in the spirit of the
/// reference-free assertions in `smoke_test.dart`. It only has to separate a
/// drawn scene from a blank or corrupt one.
double _centerNonClearFraction(ByteData rgba, int width, int height) {
  final int x0 = width ~/ 4;
  final int x1 = width - x0;
  final int y0 = height ~/ 4;
  final int y1 = height - y0;
  var total = 0;
  var nonClear = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final int i = (y * width + x) * 4;
      final int r = rgba.getUint8(i);
      final int g = rgba.getUint8(i + 1);
      final int b = rgba.getUint8(i + 2);
      total++;
      // kSmokeClear is magenta.
      if (!(r > 200 && g < 60 && b > 200)) nonClear++;
    }
  }
  return total == 0 ? 0 : nonClear / total;
}

final _boundaryKey = GlobalKey();

class _CameraHolder {
  _CameraHolder(this.camera);
  Camera camera;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.holder);
  final Scene scene;
  final _CameraHolder holder;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(holder.camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
