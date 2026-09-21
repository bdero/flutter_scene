import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/env_prefilter.dart'
    show radiancePrefilterPending;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _expectedAndroidImpellerBackend = String.fromEnvironment(
  'SMOKE_EXPECTED_ANDROID_IMPELLER_BACKEND',
);
const _androidManifestChannel = MethodChannel(
  'dev.bdero.smoke_render/android_manifest',
);

/// Restricts the run to one scene, for iterating on it locally without
/// paying for the whole matrix. Pass `--dart-define=SMOKE_ONLY=<id>`.
const _onlyScene = String.fromEnvironment('SMOKE_ONLY');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};

  if (_expectedAndroidImpellerBackend.isNotEmpty) {
    testWidgets('Android requests the expected Impeller backend', (_) async {
      expect(defaultTargetPlatform, TargetPlatform.android);
      expect(kIsWeb, isFalse);

      final backend = await _androidManifestChannel.invokeMethod<String>(
        'getApplicationMetadataValue',
        'io.flutter.embedding.android.ImpellerBackend',
      );

      expect(backend, _expectedAndroidImpellerBackend);
    });
  }

  for (final smoke in kSmokeScenes) {
    if (_onlyScene.isNotEmpty && smoke.id != _onlyScene) continue;
    testWidgets('${smoke.id} renders a sane frame', (tester) async {
      // Let Flutter render one ordinary frame before touching flutter_scene.
      // Android GLES can race GPU context setup if Scene initialization uploads
      // textures before the first frame has established the backend context.
      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(backgroundColor: kSmokeClear, body: SizedBox.expand()),
        ),
      );
      await tester.pump();

      // flutter_scene gates rendering on this future. Wait before building the
      // smoke scene: Geometry/Material constructors touch the shader bundle,
      // which must be loaded before SmokeSceneView constructs them.
      await Scene.initializeStaticResources();
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

      // Let the post-ready repaint and GPU frames settle. Android software
      // renderers need fewer, longer frames to stay below emulator watchdogs.
      // TODO(smoke): restore multi-frame Android settling when the emulator
      // watchdog no longer terminates sustained software rendering.
      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final baseFrames = isAndroid ? 1 : 20;
      final settleStep = Duration(milliseconds: 1000 ~/ baseFrames);
      // A converging feature (the irradiance field, a temporal resolve) has
      // nothing to show in one frame, so its scene asks for more.
      final settleFrames = isAndroid
          ? 1
          : (smoke.warmupFrames > baseFrames ? smoke.warmupFrames : baseFrames);
      final boundary =
          smokeSceneKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      // The build above painted the first frame; let it finish so no pump
      // below is paced and every one renders.
      await _settleGpu();
      final scene = tester
          .state<SmokeSceneViewState>(find.byType(SmokeSceneView))
          .scene;
      var paced = false;
      for (var i = 0; i < settleFrames; i++) {
        paced = await _pumpSettled(
          tester,
          scene,
          settleStep,
          markNeedsPaint: i > 0 ? boundary.markNeedsPaint : null,
        );
      }
      await _drainRadianceFills(tester, scene, settleStep, boundary);
      await _capturableFrame(tester, scene, settleStep, paced, boundary);

      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;

      // Hand the PNG to the host driver (writes it outside the app sandbox).
      // Platform is distinguished by the Argos build-name, not the filename.
      captures['${smoke.id}.png'] = base64Encode(png.buffer.asUint8List());

      final stats = _frameStats(rgba, image.width, image.height);
      final colorPass = _colorPassCounters(scene);
      // ignore: avoid_print
      print(
        'SMOKE ${smoke.id}: ${image.width}x${image.height} '
        'paced=${scene.pacedFrameCount} '
        'settleMaxMs=$_settleMaxMs settleTimeouts=$_settleTimeouts '
        'repumps=$_repumps '
        'cornersClear=${stats.cornersClear} '
        'centerCoverage=${stats.centerNonClearFraction.toStringAsFixed(3)} '
        'fgLuma=${stats.foregroundMeanLuma.toStringAsFixed(1)} '
        'colors=${stats.distinctColors} '
        'draws=${colorPass?.draws} submitted=${colorPass?.submitted} '
        'culled=${colorPass?.culled}',
      );
      _settleMaxMs = _settleTimeouts = _repumps = 0;

      // Reference-free render-sanity checks (catch black screen / nothing /
      // unlit). The visual diff service catches subtler "renders, but changed".
      if (!smoke.fullCoverage) {
        expect(
          stats.cornersClear,
          isTrue,
          reason: 'corners are not the clear color; the surface did not clear',
        );
      }
      expect(
        stats.centerNonClearFraction,
        greaterThan(0.05),
        reason: 'little or no geometry drew in the center',
      );
      expect(
        stats.foregroundMeanLuma,
        greaterThan(20),
        reason: 'foreground is ~black; lighting or textures may have broken',
      );
      // A loose backstop against a flat/uniform fill; corners, coverage, and
      // foreground luma above are the primary blank detectors. Kept very low
      // because this metric is noisy: it is dominated by the anti-aliased
      // clear/geometry edge, software rasterizers (llvmpipe on the Linux CI,
      // SwiftShader on web) produce far fewer distinct values than hardware,
      // and a flat-shaded surface legitimately covers only a handful of values
      // there (the toon material on a flat-normal cuboid renders ~12 distinct
      // colors on the software rasterizers, versus far more on a real GPU).
      expect(
        stats.distinctColors,
        greaterThan(8),
        reason: 'frame looks uniform; possible blank render',
      );
      // A scene may pin counters instead of pixels.
      final expectedCounters = smoke.colorPassCounters;
      if (expectedCounters != null) {
        expect(colorPass, isNotNull, reason: 'no ScenePass in the frame stats');
        final actual = colorPass!.toJson();
        for (final entry in expectedCounters.entries) {
          expect(
            actual[entry.key],
            entry.value,
            reason: 'ScenePass ${entry.key} for the captured frame',
          );
        }
      }
      if (smoke.id == 'irradiance_field') {
        // Both colored walls are emissive and nothing else lights the scene,
        // so the floor's color is entirely bounce light carried by the probe
        // field. Each half of the floor must take the tint of the wall beside
        // it. This fails outright if the field stops contributing, and fails
        // directionally if the octahedral addressing or the cage weights are
        // wrong, which the luma gates above would not catch.
        double redBias(int left, int top, int right, int bottom) {
          var sum = 0.0;
          var count = 0;
          for (var y = top; y < bottom; y++) {
            for (var x = left; x < right; x++) {
              final offset = (y * image.width + x) * 4;
              sum += rgba.getUint8(offset) - rgba.getUint8(offset + 1);
              count++;
            }
          }
          return sum / count;
        }

        final top = image.height * 58 ~/ 100;
        final bottom = image.height * 76 ~/ 100;
        // The view basis puts world -x on the right of the frame, so the red
        // wall (at -x) lights the right half of the floor.
        final greenSide = redBias(
          image.width * 12 ~/ 100,
          top,
          image.width * 28 ~/ 100,
          bottom,
        );
        final redSide = redBias(
          image.width * 72 ~/ 100,
          top,
          image.width * 88 ~/ 100,
          bottom,
        );
        // ignore: avoid_print
        print(
          'SMOKE irradiance_field bleed: greenSide=$greenSide '
          'redSide=$redSide',
        );
        expect(
          redSide,
          greaterThan(greenSide + 8.0),
          reason:
              'the floor beside the red wall is not redder than the floor '
              'beside the green wall; colored bounce is missing or mirrored',
        );
      }
      if (smoke.id == 'ambient_occlusion_edge') {
        double meanLuma(int left, int top, int right, int bottom) {
          var sum = 0.0;
          var count = 0;
          for (var y = top; y < bottom; y++) {
            for (var x = left; x < right; x++) {
              final offset = (y * image.width + x) * 4;
              sum +=
                  0.2126 * rgba.getUint8(offset) +
                  0.7152 * rgba.getUint8(offset + 1) +
                  0.0722 * rgba.getUint8(offset + 2);
              count++;
            }
          }
          return sum / count;
        }

        final bandWidth = image.width ~/ 32;
        final inset = image.width * 3 ~/ 32;
        final bandTop = image.height * 300 ~/ 512;
        final bandBottom = image.height * 321 ~/ 512;
        final leftEdge = meanLuma(0, bandTop, bandWidth, bandBottom);
        final leftInterior = meanLuma(
          inset,
          bandTop,
          inset + bandWidth,
          bandBottom,
        );
        final rightInterior = meanLuma(
          image.width - inset - bandWidth,
          bandTop,
          image.width - inset,
          bandBottom,
        );
        final rightEdge = meanLuma(
          image.width - bandWidth,
          bandTop,
          image.width,
          bandBottom,
        );
        expect(
          (leftEdge - leftInterior).abs(),
          lessThan(6.0),
          reason:
              'ambient occlusion changes abruptly at the left viewport edge',
        );
        expect(
          (rightEdge - rightInterior).abs(),
          lessThan(6.0),
          reason:
              'ambient occlusion changes abruptly at the right viewport edge',
        );
      }
    });
  }

  testWidgets('noise parity between CPU and GPU', (tester) async {
    // The probe evaluates all of noise.glsl's functions in one shader, so it
    // pulls in every gradient and cell-vector table (about 2k float
    // constants). The CI Android emulator's software GLES/Vulkan compiler
    // exhausts its memory on a shader that large and fails to link it (real
    // Android GPU drivers, and every other backend here, compile it fine).
    // Skip the probe on Android rather than fail on an emulator-only limit.
    // TODO(noise-probe): split the probe into per-family shaders (simplex,
    // perlin/value, cellular, warp/curl) so each fits the emulator compiler
    // and Android regains parity coverage; a real material uses one or two
    // functions and is unaffected.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return;

    await loadSmokeMaterials();

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: kSmokeClear, body: SizedBox.expand()),
      ),
    );
    await tester.pump();
    await Scene.initializeStaticResources();
    await loadSmokeMaterials();

    final setup = buildNoiseParityScene();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kSmokeClear,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: kSmokeSize.toDouble(),
                height: kSmokeSize.toDouble(),
                child: SceneView(setup.scene, camera: setup.camera),
              ),
            ),
          ),
        ),
      ),
    );
    await _settleGpu();
    final scene = setup.scene;
    var paced = false;
    for (var i = 0; i < 20; i++) {
      paced = await _pumpSettled(
        tester,
        scene,
        const Duration(milliseconds: 50),
      );
    }
    await _capturableFrame(
      tester,
      scene,
      const Duration(milliseconds: 50),
      paced,
      null,
    );

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width, height = image.height;

    int decode(int px, int py) {
      final o = (py * width + px) * 4;
      return (rgba.getUint8(o) << 16) |
          (rgba.getUint8(o + 1) << 8) |
          rgba.getUint8(o + 2);
    }

    // Locate the three marker tiles (see noise_parity.fmat) and derive the
    // tile-center-to-pixel mapping from their centroids, which stays correct
    // under any flip or framing without replicating camera math.
    (double, double) centroidOf(int marker) {
      var sx = 0.0, sy = 0.0;
      var n = 0;
      for (var py = 0; py < height; py++) {
        for (var px = 0; px < width; px++) {
          if (decode(px, py) == marker) {
            sx += px;
            sy += py;
            n++;
          }
        }
      }
      expect(
        n,
        greaterThan(50),
        reason: 'marker 0x0${marker.toRadixString(16)} not found',
      );
      return (sx / n, sy / n);
    }

    final a = centroidOf(0xABCDEF); // tile (row 0, col 0)
    final b = centroidOf(0x123456); // tile (row 0, col 7)
    final c = centroidOf(0xFEDCBA); // tile (row 20, col 0)

    int sampleTile(int row, int col) {
      final px = a.$1 + (b.$1 - a.$1) * col / 7 + (c.$1 - a.$1) * row / 20;
      final py = a.$2 + (b.$2 - a.$2) * col / 7 + (c.$2 - a.$2) * row / 20;
      return decode(px.round(), py.round());
    }

    // Dart mirror of the shader's per-tile evaluation. Coordinates and
    // fractal parameters are exactly representable in float32, so the noise
    // inputs are bit identical; only gradient-math rounding differs.
    double expected01(int r, int c) {
      final fx = c * 7.25 - 27.5;
      final fy = c * 3.75 + r * 11.125 - 40.0;
      final fz = c * 1.875 - r * 5.25 + 13.75;
      final n = FastNoiseLite(seed: 1337 + r)..frequency = 0.0625;
      if (r == 3 || r == 4 || r == 6) n.noiseType = NoiseType.openSimplex2S;
      if (r >= 5) {
        n
          ..octaves = 4
          ..lacunarity = 2.0
          ..gain = 0.5;
      }
      if (r == 5 || r == 6) n.fractalType = FractalType.fbm;
      if (r == 7) n.fractalType = FractalType.ridged;
      if (r == 8) {
        n
          ..fractalType = FractalType.pingPong
          ..pingPongStrength = 2.0;
      }
      if (r == 11 || r == 12) n.noiseType = NoiseType.perlin;
      if (r == 13 || r == 14) n.noiseType = NoiseType.value;
      if (r >= 15 && r <= 17) n.noiseType = NoiseType.cellular;
      if (r == 15) {
        n
          ..cellularDistanceFunction = CellularDistanceFunction.euclideanSq
          ..cellularReturnType = CellularReturnType.distance;
      }
      if (r == 16) {
        n
          ..cellularDistanceFunction = CellularDistanceFunction.euclidean
          ..cellularReturnType = CellularReturnType.distance2;
      }
      if (r == 17) {
        n
          ..cellularDistanceFunction = CellularDistanceFunction.manhattan
          ..cellularReturnType = CellularReturnType.cellValue;
      }
      if (r == 18) {
        // Domain warp probe, mirrored against the pre-scaled coordinates the
        // shader passes (frequency folds to 1).
        // octaves = 1 makes the fractal bounding exactly 1, so the Dart
        // domainWarpAmp equals the GLSL amp parameter.
        final w =
            (FastNoiseLite(seed: 1337 + r)
                  ..frequency = 1.0
                  ..octaves = 1
                  ..domainWarpAmp = 30.0)
                .domainWarp2(fx * 0.0625, fy * 0.0625);
        return ((w.x - fx * 0.0625) / 60.0 + 0.5).clamp(0.0, 1.0);
      }
      if (r == 19) {
        final v = noiseCurl3(
          fx * 0.0625,
          fy * 0.0625,
          fz * 0.0625,
          seed: 1337 + r,
          epsilon: 0.25,
        );
        return (v.x * 0.125 + 0.5).clamp(0.0, 1.0);
      }
      final is3d =
          r == 2 || r == 4 || r == 6 || r == 8 || r == 12 || r == 14 || r == 16;
      final v = is3d ? n.getNoise3(fx, fy, fz) : n.getNoise2(fx, fy);
      return v * 0.5 + 0.5;
    }

    // The value comparison uses the Dart FastNoiseLite as the reference. On
    // the web (dart2js) that reference is itself wrong: Dart ints are JS
    // doubles there, so the noise's 32-bit integer hash multiplies overflow
    // 2^53 and lose their low bits (and the 3D lattice math overflows
    // entirely), before `toSigned(32)` can wrap. The GPU shader noise is
    // correct on the web (it has been checked bit-for-bit against the native
    // Metal output), so only the CPU-side reference is unreliable there.
    // Verify the shader compiled and rendered on the web (the markers
    // located above prove that), and skip the numeric comparison until the
    // Dart integer math is made web-safe.
    // TODO(noise-web): give the Dart hash a Math.imul-style 32-bit multiply
    // so `FastNoiseLite` matches native on the web, then drop this guard.
    if (kIsWeb) return;

    // Float rows: the GPU evaluates the noise in float32 and every backend's
    // compiler rounds a little differently, so these tolerances are set above
    // the loosest software rasterizer (single-octave simplex on llvmpipe
    // differs by ~6e-5) yet far below a transcription bug, which shifts a
    // whole gradient or constant and lands near 0.1. They are the executable
    // form of the float layer of the parity contract.
    for (final r in [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
    ]) {
      final tol = switch (r) {
        <= 4 => 5e-4, // single-octave simplex
        <= 8 => 1e-3, // four octaves of accumulated rounding
        <= 14 => 5e-4, // single-octave perlin/value
        <= 16 => 1e-3, // cellular distance chains
        17 => 5e-4, // cellValue, hash-derived but evaluated in float
        18 => 5e-4, // warp displacement, normalized
        _ => 1e-3, // curl, central differences amplify rounding
      };
      for (var c = 0; c < 8; c++) {
        final gpu01 = sampleTile(r, c) / 16777215.0;
        expect(
          gpu01,
          closeTo(expected01(r, c), tol),
          reason: 'float noise mismatch at tile row $r col $c',
        );
      }
    }

    // Hash rows: the integer layer is bit-exact wherever Dart ints are true
    // 64-bit (every native backend), no tolerance.
    for (var c = 0; c < 8; c++) {
      expect(
        sampleTile(9, c),
        noiseHash2(1337 + 9, c * 3 - 11, 9 * 7 + c) & 0xFFFFFF,
        reason: 'NoiseHash2 mismatch at col $c',
      );
      expect(
        sampleTile(10, c),
        noiseHash3(1337 + 10, c * 3 - 11, 10 * 7 + c, c - 5) & 0xFFFFFF,
        reason: 'NoiseHash3 mismatch at col $c',
      );
    }
  });

  testWidgets('depth test survives switching MSAA off', (tester) async {
    // Regression probe for a color target reused as an MSAA resolve
    // destination and then as a direct target with a depth attachment. The
    // GLES backend caches one framebuffer per color texture, so without a
    // separate pooled texture per attachment setup the second frame draws
    // with no depth buffer at all.
    final msaaSupported = Scene.isAntiAliasingModeSupported(
      AntiAliasingMode.msaa,
    );
    debugPrint('SMOKE depth_pairing: msaaSupported=$msaaSupported');
    if (!msaaSupported) return;

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: kSmokeClear, body: SizedBox.expand()),
      ),
    );
    await tester.pump();
    await Scene.initializeStaticResources();

    final setup = buildDepthPairingScene();
    final scene = setup.scene..antiAliasingMode = AntiAliasingMode.msaa;
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kSmokeClear,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: kSmokeSize.toDouble(),
                height: kSmokeSize.toDouble(),
                child: SceneView(scene, camera: setup.camera),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> pumpFrames() async {
      await _settleGpu();
      var paced = false;
      for (var i = 0; i < 10; i++) {
        paced = await _pumpSettled(
          tester,
          scene,
          const Duration(milliseconds: 50),
        );
      }
      await _capturableFrame(
        tester,
        scene,
        const Duration(milliseconds: 50),
        paced,
        null,
      );
    }

    Future<(int, int, int)> centerPixel() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final o = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      return (rgba.getUint8(o), rgba.getUint8(o + 1), rgba.getUint8(o + 2));
    }

    await pumpFrames();
    final msaa = await centerPixel();
    expect(msaa.$1, greaterThan(200), reason: 'msaa frame center $msaa');
    expect(msaa.$2, lessThan(60), reason: 'msaa frame center $msaa');

    scene.antiAliasingMode = AntiAliasingMode.none;
    await pumpFrames();
    final none = await centerPixel();
    debugPrint('SMOKE depth_pairing: msaa=$msaa none=$none');
    expect(none.$1, greaterThan(200), reason: 'no-AA frame center $none');
    expect(none.$2, lessThan(60), reason: 'no-AA frame center $none');
  });

  testWidgets('a display-referred surface keeps its colours', (tester) async {
    // Pixel-level guard for the display-referred layer (issue #382). A
    // scene-referred quad is transformed by whatever tone curve is set; a
    // display-referred one must arrive byte-exact under every one of them.
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: kSmokeClear, body: SizedBox.expand()),
      ),
    );
    await tester.pump();
    await Scene.initializeStaticResources();

    final material = UnlitMaterial()
      ..alphaMode = AlphaMode.opaque
      ..displayReferred = true;
    final scene = Scene()..environment = EnvironmentMap.empty();
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(4, 4, 0.01)), material)),
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kSmokeClear,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: kSmokeSize.toDouble(),
                height: kSmokeSize.toDouble(),
                child: SceneView(
                  scene,
                  camera: PerspectiveCamera(position: vm.Vector3(0, 0, 3)),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Android software rendering pays for every frame, so settle in fewer,
    // longer steps there, matching the scene loop above.
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final frames = isAndroid ? 2 : 10;
    Future<int> render(int value, ToneMappingMode mode) async {
      final pixels = Uint8List(4 * 4 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = value;
        pixels[i + 1] = value;
        pixels[i + 2] = value;
        pixels[i + 3] = 255;
      }
      material.baseColorTexture = Texture2D.fromPixels(pixels, 4, 4);
      scene.toneMapping = mode;

      await _settleGpu();
      var paced = false;
      for (var i = 0; i < frames; i++) {
        paced = await _pumpSettled(
          tester,
          scene,
          const Duration(milliseconds: 50),
        );
      }
      await _capturableFrame(
        tester,
        scene,
        const Duration(milliseconds: 50),
        paced,
        null,
      );

      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final o = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      final red = rgba.getUint8(o);
      image.dispose();
      return red;
    }

    // Near-black is where the default operator's black-point term does its
    // worst (27 resolves to 2 scene-referred), so it earns a row.
    const inputs = [255, 128, 27];
    final mismatches = <String>[];
    for (final mode in ToneMappingMode.values) {
      final row = <String>[];
      for (final value in inputs) {
        final out = await render(value, mode);
        row.add('$value->$out');
        if (out != value) mismatches.add('${mode.name} $value gave $out');
      }
      debugPrint('SMOKE display_referred ${mode.name}: ${row.join('  ')}');
    }
    expect(
      mismatches,
      isEmpty,
      reason:
          'a display-referred surface must reach the screen unchanged, '
          'whatever the scene tone curve is',
    );
  });

  tearDownAll(() {
    binding.reportData = <String, dynamic>{...captures};
  });
}

({
  bool cornersClear,
  double centerNonClearFraction,
  double foregroundMeanLuma,
  int distinctColors,
})
_frameStats(ByteData rgba, int w, int h) {
  final bytes = rgba.buffer.asUint8List();
  int idx(int x, int y) => (y * w + x) * 4;
  bool isClear(int i) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
    return (r - 0xFF).abs() < 24 && g < 24 && (b - 0xFF).abs() < 24;
  }

  final corners = <int>[
    idx(8, 8),
    idx(w - 9, 8),
    idx(8, h - 9),
    idx(w - 9, h - 9),
  ];
  final cornersClear = corners.every(isClear);

  final x0 = w ~/ 4, x1 = 3 * w ~/ 4, y0 = h ~/ 4, y1 = 3 * h ~/ 4;
  var centerTotal = 0, centerNonClear = 0, fgCount = 0;
  var fgLumaSum = 0.0;
  final colors = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = idx(x, y);
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2], a = bytes[i + 3];
      colors.add((r << 24) | (g << 16) | (b << 8) | a);
      final clear = isClear(i);
      if (x >= x0 && x < x1 && y >= y0 && y < y1) {
        centerTotal++;
        if (!clear) centerNonClear++;
      }
      if (!clear) {
        fgLumaSum += 0.299 * r + 0.587 * g + 0.114 * b;
        fgCount++;
      }
    }
  }
  return (
    cornersClear: cornersClear,
    centerNonClearFraction: centerTotal == 0
        ? 0.0
        : centerNonClear / centerTotal,
    foregroundMeanLuma: fgCount == 0 ? 0.0 : fgLumaSum / fgCount,
    distinctColors: colors.length,
  );
}

/// The color pass's counters for the frame [scene] last rendered, or null
/// when no frame has rendered or none of its passes is the color pass.
RenderCounters? _colorPassCounters(Scene scene) {
  final views = scene.renderStats.latest?.views;
  if (views == null || views.isEmpty) return null;
  for (final pass in views.first.passes) {
    if (pass.name == 'ScenePass') return pass.counters;
  }
  return null;
}

/// Waits for the GPU to finish the frame the last pump submitted, so the next
/// pump renders instead of re-presenting under `Scene.maxGpuFramesInFlight`
/// and the capture is the frame the last pump drew. Bounded, since the
/// immediate-execution web shim never holds work.
Future<void> _settleGpu() async {
  final start = DateTime.now();
  final deadline = start.add(const Duration(seconds: 10));
  while (rendererSubmissions.framesInFlight > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final waited = DateTime.now().difference(start).inMilliseconds;
  if (waited > _settleMaxMs) _settleMaxMs = waited;
  if (rendererSubmissions.framesInFlight > 0) _settleTimeouts++;
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

/// Pumps one frame and lets its GPU work finish. Returns whether the frame
/// was paced (re-presented) rather than rendered.
Future<bool> _pumpSettled(
  WidgetTester tester,
  Scene scene,
  Duration step, {
  void Function()? markNeedsPaint,
}) async {
  markNeedsPaint?.call();
  final pacedBefore = scene.pacedFrameCount;
  await tester.pump(step);
  await _settleGpu();
  return scene.pacedFrameCount != pacedBefore;
}

/// Makes sure the frame on screen is a rendered one. The Android emulator's
/// Vulkan host signals some fences only when the next frame presents, so a
/// pump right after such a frame is paced no matter how long the wait; pump
/// again until one renders, bounded.
/// Pumps until no environment is still filling its radiance.
///
/// A scene refines its radiance a roughness band per frame so one oversized
/// prefilter cannot stall the display, which leaves an environment an
/// approximation for its first few frames. These captures settle a single
/// frame on Android (the emulator watchdog terminates sustained software
/// rendering), so without this they would photograph the approximation there
/// and the converged image everywhere else, then compare the two against one
/// baseline.
///
/// Pumping is what the fill paces against, so this drives it rather than
/// waiting on it. Forcing the prefilter into one submission instead puts back
/// exactly the stall the pacing exists to avoid, which on the software Vulkan
/// emulator is enough to time the device out.
Future<void> _drainRadianceFills(
  WidgetTester tester,
  Scene scene,
  Duration settleStep,
  RenderRepaintBoundary boundary,
) async {
  // One pump per band, plus slack for an environment built during the drain.
  const maxPumps = kPrefilterBandCount * 2;
  for (var i = 0; i < maxPumps && radiancePrefilterPending; i++) {
    await _pumpSettled(
      tester,
      scene,
      settleStep,
      markNeedsPaint: boundary.markNeedsPaint,
    );
  }
}

Future<void> _capturableFrame(
  WidgetTester tester,
  Scene scene,
  Duration step,
  bool lastPaced,
  RenderRepaintBoundary? boundary,
) async {
  for (var tries = 0; lastPaced && tries < 4; tries++) {
    _repumps++;
    lastPaced = await _pumpSettled(
      tester,
      scene,
      step,
      markNeedsPaint: boundary?.markNeedsPaint,
    );
  }
}

// Per-scene diagnostics of the GPU waits, printed with the frame stats.
int _settleMaxMs = 0;
int _settleTimeouts = 0;
int _repumps = 0;
