import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';

const _expectedAndroidImpellerBackend = String.fromEnvironment(
  'SMOKE_EXPECTED_ANDROID_IMPELLER_BACKEND',
);
const _androidManifestChannel = MethodChannel(
  'dev.bdero.smoke_render/android_manifest',
);

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
      await loadSmokeMaterials();

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: kSmokeClear,
            body: Center(child: SmokeSceneView(smoke)),
          ),
        ),
      );

      // Let the post-ready repaint and GPU frames settle.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final boundary =
          smokeSceneKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;

      // Hand the PNG to the host driver (writes it outside the app sandbox).
      // Platform is distinguished by the Argos build-name, not the filename.
      captures['${smoke.id}.png'] = base64Encode(png.buffer.asUint8List());

      final stats = _frameStats(rgba, image.width, image.height);
      // ignore: avoid_print
      print(
        'SMOKE ${smoke.id}: ${image.width}x${image.height} '
        'cornersClear=${stats.cornersClear} '
        'centerCoverage=${stats.centerNonClearFraction.toStringAsFixed(3)} '
        'fgLuma=${stats.foregroundMeanLuma.toStringAsFixed(1)} '
        'colors=${stats.distinctColors}',
      );

      // Reference-free render-sanity checks (catch black screen / nothing /
      // unlit). The visual diff service catches subtler "renders, but changed".
      expect(
        stats.cornersClear,
        isTrue,
        reason: 'corners are not the clear color; the surface did not clear',
      );
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
                width: kSmokeSize,
                height: kSmokeSize,
                child: SceneView(setup.scene, camera: setup.camera),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

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
