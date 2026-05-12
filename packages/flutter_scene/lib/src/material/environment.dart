import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/env_prefilter.dart';
import 'package:vector_math/vector_math.dart';

/// Number of L2 spherical-harmonic coefficients used for diffuse
/// irradiance (bands 0..2).
const int kDiffuseShCoefficientCount = 9;

/// A source of image-based lighting: diffuse irradiance plus prefiltered
/// specular radiance, both derived from an equirectangular environment.
///
/// Diffuse is stored as 9 L2 spherical-harmonic RGB coefficients (cheap,
/// no texture fetch, seam-free); specular is a GPU-prefiltered "PMREM"
/// roughness-band atlas (see [prefilterEquirectRadiance]). Both are
/// computed up front, so constructing an environment from images does GPU
/// work and is best done once.
///
/// Construct one with [EnvironmentMap.fromAssets] / [EnvironmentMap.fromUIImages]
/// (which compute the SH and prefilter the radiance for you),
/// [EnvironmentMap.studio] (the built-in procedural default),
/// [EnvironmentMap.fromGpuTextures] when you already hold a prefiltered
/// atlas, or [EnvironmentMap.empty] for a no-op black environment.
///
/// Set one on a [Scene] via `Scene.environment` (it defaults to
/// [EnvironmentMap.studio]); an individual [PhysicallyBasedMaterial] can
/// override it via `PhysicallyBasedMaterial.environment`.
base class EnvironmentMap {
  EnvironmentMap._(
    this._prefilteredRadianceTexture,
    this._diffuseSphericalHarmonics,
  ) : assert(_diffuseSphericalHarmonics.length == kDiffuseShCoefficientCount);

  /// A black environment that contributes no image-based lighting.
  ///
  /// Specular reflections are black and the diffuse term is zero, so
  /// objects are lit only by analytic lights (if any).
  factory EnvironmentMap.empty() {
    return EnvironmentMap._(
      Material.getBlackPlaceholderTexture(),
      _zeroSphericalHarmonics(),
    );
  }

  /// Wraps an already-built prefiltered-radiance atlas.
  ///
  /// [prefilteredRadiance] must be a roughness-band atlas as produced by
  /// [prefilterEquirectRadiance]. [diffuseSphericalHarmonics], if given,
  /// must be [kDiffuseShCoefficientCount] RGB coefficients (with the
  /// Lambertian convolution and `1/pi` already folded in, as
  /// [computeDiffuseSphericalHarmonics] returns); when omitted the diffuse
  /// term is zero.
  factory EnvironmentMap.fromGpuTextures({
    required gpu.Texture prefilteredRadiance,
    List<Vector3>? diffuseSphericalHarmonics,
  }) {
    return EnvironmentMap._(
      prefilteredRadiance,
      diffuseSphericalHarmonics ?? _zeroSphericalHarmonics(),
    );
  }

  /// Builds an [EnvironmentMap] from an already-decoded equirectangular
  /// `dart:ui` radiance image: uploads it, GPU-prefilters it for
  /// roughness-aware specular, and projects it onto diffuse SH.
  ///
  /// The image is interpreted as sRGB-encoded. Pass [diffuseSphericalHarmonics]
  /// to supply your own diffuse term instead of projecting it.
  static Future<EnvironmentMap> fromUIImages({
    required ui.Image radianceImage,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    final radianceTexture = await gpuTextureFromImage(radianceImage);
    final prefilteredRadiance = prefilterEquirectRadiance(radianceTexture);
    final sh =
        diffuseSphericalHarmonics ??
        await computeDiffuseSphericalHarmonics(radianceImage);
    return EnvironmentMap._(prefilteredRadiance, sh);
  }

  /// Loads an [EnvironmentMap] from an equirectangular sRGB radiance image
  /// in the asset bundle (see [fromUIImages]).
  static Future<EnvironmentMap> fromAssets({
    required String radianceImagePath,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    return fromUIImages(
      radianceImage: await imageFromAsset(radianceImagePath),
      diffuseSphericalHarmonics: diffuseSphericalHarmonics,
    );
  }

  /// Builds the package's built-in procedural "studio" environment.
  ///
  /// A neutral image-based-lighting setup generated on the fly (no bundled
  /// HDR): a cool soft "ceiling" fading through a neutral horizon to a dim
  /// warm "floor bounce", with a broad top fill and a couple of soft
  /// key/fill light lobes that read as defined specular highlights on
  /// glossy surfaces. This is the zero-config default a [Scene] uses when
  /// no environment is configured.
  static EnvironmentMap studio() {
    final pixels = _generateStudioEquirectPixels(
      _studioEnvWidth,
      _studioEnvHeight,
    );
    final radianceTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      _studioEnvWidth,
      _studioEnvHeight,
    )..overwrite(ByteData.sublistView(pixels));
    return EnvironmentMap._(
      prefilterEquirectRadiance(radianceTexture),
      _projectEquirectToSphericalHarmonics(
        pixels,
        _studioEnvWidth,
        _studioEnvHeight,
      ),
    );
  }

  static const int _studioEnvWidth = 256;
  static const int _studioEnvHeight = 128;

  // Generates the procedural studio equirect as sRGB-encoded RGBA8 pixels.
  // The scan order matches _projectEquirectToSphericalHarmonics / the
  // shader's SphericalToEquirectangular: row 0 is the "down" pole, the last
  // row is the "up" pole.
  static Uint8List _generateStudioEquirectPixels(int width, int height) {
    final pixels = Uint8List(width * height * 4);

    final keyDir = Vector3(0.45, 0.55, 0.70)..normalize();
    final fillDir = Vector3(-0.70, 0.22, -0.35)..normalize();

    const twoPi = 2.0 * math.pi;
    for (var py = 0; py < height; py++) {
      final v = (py + 0.5) / height;
      final latitude = (v - 0.5) * math.pi; // asin(dirY)
      final cosLat = math.cos(latitude);
      final dirY = math.sin(latitude);
      for (var px = 0; px < width; px++) {
        final u = (px + 0.5) / width;
        final longitude = (u - 0.5) * twoPi; // atan2(dirZ, dirX)
        final dirX = cosLat * math.cos(longitude);
        final dirZ = cosLat * math.sin(longitude);

        // Vertical studio gradient (linear): cool bright above, neutral at
        // the horizon, dim warm below.
        double r, g, b;
        if (dirY >= 0.0) {
          final t = _smoothstep01(dirY);
          r = _lerp(0.50, 0.78, t);
          g = _lerp(0.51, 0.80, t);
          b = _lerp(0.53, 0.86, t);
        } else {
          final t = _smoothstep01(-dirY);
          r = _lerp(0.50, 0.20, t);
          g = _lerp(0.51, 0.18, t);
          b = _lerp(0.53, 0.16, t);
        }

        // Broad top fill (the "ceiling softbox").
        final top = math.max(dirY, 0.0);
        final topL = top * top; // pow(., 2)
        r += 0.85 * topL;
        g += 0.86 * topL;
        b += 0.88 * topL;

        // Tight warm key highlight.
        final keyC = math.max(
          dirX * keyDir.x + dirY * keyDir.y + dirZ * keyDir.z,
          0.0,
        );
        final keyL = math.pow(keyC, 26.0).toDouble();
        r += 1.20 * keyL;
        g += 1.10 * keyL;
        b += 0.95 * keyL;

        // Softer cool fill from behind.
        final fillC = math.max(
          dirX * fillDir.x + dirY * fillDir.y + dirZ * fillDir.z,
          0.0,
        );
        final fillL = math.pow(fillC, 16.0).toDouble();
        r += 0.40 * fillL;
        g += 0.48 * fillL;
        b += 0.60 * fillL;

        final o = (py * width + px) * 4;
        pixels[o] = _encodeSrgb(r);
        pixels[o + 1] = _encodeSrgb(g);
        pixels[o + 2] = _encodeSrgb(b);
        pixels[o + 3] = 255;
      }
    }
    return pixels;
  }

  static int _encodeSrgb(double linear) {
    final c = linear.clamp(0.0, 1.0);
    return (math.pow(c, 1.0 / 2.2) * 255.0).round().clamp(0, 255).toInt();
  }

  static double _smoothstep01(double x) {
    final t = x.clamp(0.0, 1.0).toDouble();
    return t * t * (3.0 - 2.0 * t);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static List<Vector3> _zeroSphericalHarmonics() =>
      List<Vector3>.generate(kDiffuseShCoefficientCount, (_) => Vector3.zero());

  /// Projects an equirectangular radiance image onto 9 L2 spherical-
  /// harmonic coefficients suitable for diffuse irradiance.
  ///
  /// The image is interpreted as sRGB-encoded and read in the same
  /// equirectangular convention the runtime shader samples with. The
  /// returned coefficients already fold in the Lambertian cosine
  /// convolution (the `A_l` band factors) and the `1 / pi` BRDF term, so
  /// the shader just evaluates `Sum c_i * Y_i(n)` and multiplies by the
  /// diffuse albedo.
  static Future<List<Vector3>> computeDiffuseSphericalHarmonics(
    ui.Image equirectangular,
  ) async {
    final byteData = await equirectangular.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw Exception('Failed to read RGBA data from environment image.');
    }
    return _projectEquirectToSphericalHarmonics(
      byteData.buffer.asUint8List(),
      equirectangular.width,
      equirectangular.height,
    );
  }

  /// Core SH-9 projection over RGBA8 equirectangular [bytes] of the given
  /// dimensions. Shared by [computeDiffuseSphericalHarmonics] and [studio].
  static List<Vector3> _projectEquirectToSphericalHarmonics(
    Uint8List bytes,
    int width,
    int height,
  ) {
    // Quadrature over a regular grid in equirectangular UV space. The grid
    // resolution is independent of the source image; sampling 192x96 cells
    // keeps the L2 projection accurate while staying fast on the CPU.
    const numPhi = 192;
    const numTheta = 96;
    final coefficients = _zeroSphericalHarmonics();

    const twoPi = 2.0 * math.pi;
    final cellSolidAngle = twoPi * math.pi / (numPhi * numTheta);

    for (var j = 0; j < numTheta; j++) {
      final v = (j + 0.5) / numTheta;
      final latitude =
          (v - 0.5) * math.pi; // asin(direction.y), in [-pi/2, pi/2]
      final cosLat = math.cos(latitude);
      final dirY = math.sin(latitude);
      final weightRow = cosLat * cellSolidAngle;
      final py = (v * height).floor().clamp(0, height - 1);

      for (var i = 0; i < numPhi; i++) {
        final u = (i + 0.5) / numPhi;
        final longitude = (u - 0.5) * twoPi; // atan2(direction.z, direction.x)
        final dirX = cosLat * math.cos(longitude);
        final dirZ = cosLat * math.sin(longitude);
        final px = (u * width).floor().clamp(0, width - 1);

        final o = (py * width + px) * 4;
        // Linearize sRGB the same way the shader's SRGBToLinear does.
        final r = _srgbToLinear(bytes[o] / 255.0);
        final g = _srgbToLinear(bytes[o + 1] / 255.0);
        final b = _srgbToLinear(bytes[o + 2] / 255.0);

        _accumulateSh(coefficients, dirX, dirY, dirZ, r, g, b, weightRow);
      }
    }

    // Fold in the Lambertian convolution band factors (A_l) divided by pi:
    // A_0/pi = 1, A_1/pi = 2/3, A_2/pi = 1/4. Band 0 is unchanged.
    for (var k = 1; k <= 3; k++) {
      coefficients[k] = coefficients[k] * (2.0 / 3.0);
    }
    for (var k = 4; k <= 8; k++) {
      coefficients[k] = coefficients[k] * 0.25;
    }
    return coefficients;
  }

  static void _accumulateSh(
    List<Vector3> coefficients,
    double x,
    double y,
    double z,
    double r,
    double g,
    double b,
    double weight,
  ) {
    // Real spherical-harmonic basis, bands 0..2. Must match the basis the
    // standard fragment shader evaluates with.
    final basis = <double>[
      0.282095,
      0.488603 * y,
      0.488603 * z,
      0.488603 * x,
      1.092548 * x * y,
      1.092548 * y * z,
      0.315392 * (3.0 * z * z - 1.0),
      1.092548 * x * z,
      0.546274 * (x * x - y * y),
    ];
    for (var k = 0; k < kDiffuseShCoefficientCount; k++) {
      final w = basis[k] * weight;
      coefficients[k].x += r * w;
      coefficients[k].y += g * w;
      coefficients[k].z += b * w;
    }
  }

  static double _srgbToLinear(double c) => math.pow(c, 2.2).toDouble();

  final gpu.Texture _prefilteredRadianceTexture;
  final List<Vector3> _diffuseSphericalHarmonics;

  // TODO(bdero): Once mipmapped cubemaps land in Flutter GPU, replace this
  // equirectangular atlas with a real prefiltered cubemap.
  // (https://github.com/flutter/flutter/issues/145027)
  /// The prefiltered-radiance atlas sampled for specular IBL.
  ///
  /// A vertical atlas of equirectangular roughness bands (see
  /// [prefilterEquirectRadiance]); the standard fragment shader samples it
  /// via `SamplePrefilteredRadiance`.
  gpu.Texture get prefilteredRadianceTexture => _prefilteredRadianceTexture;

  /// The [kDiffuseShCoefficientCount] RGB L2 spherical-harmonic
  /// coefficients describing the diffuse (Lambertian) irradiance.
  ///
  /// The Lambertian cosine convolution and the `1/pi` BRDF term are
  /// already folded in, so the shader just evaluates the polynomial and
  /// multiplies by the diffuse albedo. All zero for [EnvironmentMap.empty].
  List<Vector3> get diffuseSphericalHarmonics => _diffuseSphericalHarmonics;
}
