import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/env_prefilter.dart';
import 'package:flutter_scene/src/render/sky_bake.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:vector_math/vector_math.dart';

/// Number of L2 spherical-harmonic coefficients used for diffuse
/// irradiance (bands 0..2).
/// {@category Lighting and environment}
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
/// {@category Lighting and environment}
base class EnvironmentMap {
  EnvironmentMap._(this._prefilteredRadianceTexture, List<Vector3> sh)
    : assert(sh.length == kDiffuseShCoefficientCount),
      _diffuseSphericalHarmonics = sh,
      _diffuseShTexture = _shTextureFromList(sh);

  // Wraps an already-built prefiltered atlas and a GPU-computed SH coefficient
  // texture (the diffuse term lives only on the GPU, so the coefficient list
  // is empty). Used by [fromSky].
  EnvironmentMap._fromGpuSh(
    this._prefilteredRadianceTexture,
    this._diffuseShTexture,
  ) : _diffuseSphericalHarmonics = const <Vector3>[];

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
  /// [prefilterEquirectRadiance]. The diffuse term comes from
  /// [diffuseSphericalHarmonics] ([kDiffuseShCoefficientCount] RGB
  /// coefficients with the Lambertian convolution and `1/pi` already folded
  /// in, as [computeDiffuseSphericalHarmonics] returns), or from
  /// [diffuseShTexture] (a 9x1 coefficient texture already on the GPU, as a
  /// sky bake produces); pass at most one. When both are omitted the diffuse
  /// term is zero.
  factory EnvironmentMap.fromGpuTextures({
    required gpu.Texture prefilteredRadiance,
    List<Vector3>? diffuseSphericalHarmonics,
    gpu.Texture? diffuseShTexture,
  }) {
    assert(
      diffuseSphericalHarmonics == null || diffuseShTexture == null,
      'Pass diffuseSphericalHarmonics or diffuseShTexture, not both.',
    );
    if (diffuseShTexture != null) {
      return EnvironmentMap._fromGpuSh(prefilteredRadiance, diffuseShTexture);
    }
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
    final environment = await fromUIImages(
      radianceImage: await imageFromAsset(radianceImagePath),
      diffuseSphericalHarmonics: diffuseSphericalHarmonics,
    );
    _environmentAssetPaths[environment] = radianceImagePath;
    return environment;
  }

  /// Builds an [EnvironmentMap] from a high-dynamic-range equirectangular
  /// radiance map: linear (not sRGB) RGBA float pixels, row-major,
  /// [width] by [height]. Row 0 is the top of the image (the up pole), the
  /// standard equirectangular convention.
  ///
  /// Unlike [fromUIImages], the input is linear HDR, so radiance above 1.0
  /// (bright skies, the sun) is preserved through the prefilter and lights
  /// the scene at its true intensity. Pass [diffuseSphericalHarmonics] to
  /// supply your own diffuse term instead of projecting it.
  static Future<EnvironmentMap> fromEquirectHdr({
    required Float32List linearPixels,
    required int width,
    required int height,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    assert(linearPixels.length == width * height * 4);
    // The radiance texture is fp16, not fp32: the prefilter samples it
    // with a linear sampler, and 32-bit-float textures are not filterable
    // on several GPU backends (notably Apple Silicon), which would make
    // the prefiltered atlas read back as black. fp16 is universally
    // filterable and carries ample range for radiance.
    final radianceTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
    )..overwrite(ByteData.sublistView(_floatPixelsToHalf(linearPixels)));
    final prefilteredRadiance = prefilterEquirectRadiance(
      radianceTexture,
      sourceIsLinear: true,
    );
    final sh =
        diffuseSphericalHarmonics ??
        _projectLinearEquirectToSphericalHarmonics(linearPixels, width, height);
    return EnvironmentMap._(prefilteredRadiance, sh);
  }

  /// Bakes a sky into an environment for image-based lighting.
  ///
  /// Renders [source] (a [ShaderSkySource], including a `.fmat` sky) into a
  /// prefiltered-radiance atlas plus a GPU-projected diffuse SH texture, so
  /// the sky also lights the scene. This is GPU work meant to run when the
  /// sky is set or changes, not every frame; the visible `Scene.skybox` draw
  /// is separate and cheap. To re-bake on a schedule instead of by hand, set
  /// `Scene.skyEnvironment` with a refresh policy. [faceResolution] and
  /// [equirectWidth] trade quality for bake cost.
  ///
  /// Only [ShaderSkySource]-based skies can be baked; an [EnvironmentSkySource]
  /// already is an environment.
  static EnvironmentMap fromSky(
    SkySource source, {
    int faceResolution = 128,
    int equirectWidth = 512,
  }) {
    if (source is! ShaderSkySource) {
      throw ArgumentError(
        'EnvironmentMap.fromSky requires a ShaderSkySource (or a .fmat sky); '
        'an EnvironmentSkySource already is an environment.',
      );
    }
    final baked = bakeSkyEnvironment(
      source,
      EnvironmentMap.empty(),
      faceResolution: faceResolution,
      equirectWidth: equirectWidth,
    );
    return EnvironmentMap._fromGpuSh(baked.atlas, baked.sh);
  }

  // Scratch storage for reinterpreting a 32-bit float as its raw bits.
  static final Float32List _floatBits = Float32List(1);
  static final Uint32List _floatBitsView = Uint32List.view(_floatBits.buffer);

  /// Converts linear RGBA float [pixels] to half-float (fp16) bit patterns
  /// for upload to an `r16g16b16a16Float` texture.
  static Uint16List _floatPixelsToHalf(Float32List pixels) {
    final half = Uint16List(pixels.length);
    for (var i = 0; i < pixels.length; i++) {
      half[i] = _floatToHalfBits(pixels[i]);
    }
    return half;
  }

  /// Converts one 32-bit float to a 16-bit half-float bit pattern.
  /// Subnormals flush to zero; values past the half range clamp to the
  /// largest finite half.
  static int _floatToHalfBits(double value) {
    _floatBits[0] = value;
    final bits = _floatBitsView[0];
    final sign = (bits >>> 16) & 0x8000;
    final exponent = ((bits >>> 23) & 0xff) - 112; // rebias 127 -> 15
    final mantissa = bits & 0x7fffff;
    if (exponent >= 0x1f) {
      return sign | 0x7bff; // overflow / inf / nan -> largest finite half
    }
    if (exponent <= 0) {
      return sign; // underflow -> signed zero
    }
    return sign | (exponent << 10) | (mantissa >>> 13);
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
      // Row 0 (the top of the image) is the up hemisphere (+y), matching the
      // standard equirect convention loaded images use and the way the
      // prefilter and SH projection sample the source.
      final latitude = (0.5 - v) * math.pi; // asin(dirY)
      final cosLat = math.cos(latitude);
      final dirY = math.sin(latitude);
      for (var px = 0; px < width; px++) {
        final u = (px + 0.5) / width;
        final longitude = (u - 0.5) * twoPi; // atan2(dirZ, dirX)
        final dirX = cosLat * math.cos(longitude);
        final dirZ = cosLat * math.sin(longitude);

        // Vertical studio gradient (linear): a near-neutral grey, faintly
        // cool above the horizon and faintly warm below. Kept low-
        // saturation so glancing reflections on glossy floors stay clean.
        double r, g, b;
        if (dirY >= 0.0) {
          final t = _smoothstep01(dirY);
          r = _lerp(0.50, 0.76, t);
          g = _lerp(0.51, 0.78, t);
          b = _lerp(0.52, 0.82, t);
        } else {
          final t = _smoothstep01(-dirY);
          r = _lerp(0.50, 0.20, t);
          g = _lerp(0.51, 0.19, t);
          b = _lerp(0.52, 0.17, t);
        }

        // Broad (near-neutral) top fill, the "ceiling softbox".
        final top = math.max(dirY, 0.0);
        final topL = top * top; // pow(., 2)
        r += 0.85 * topL;
        g += 0.86 * topL;
        b += 0.88 * topL;

        // Tight, faintly warm key highlight.
        final keyC = math.max(
          dirX * keyDir.x + dirY * keyDir.y + dirZ * keyDir.z,
          0.0,
        );
        final keyL = math.pow(keyC, 26.0).toDouble();
        r += 1.10 * keyL;
        g += 1.06 * keyL;
        b += 1.00 * keyL;

        // Softer, faintly cool fill from behind.
        final fillC = math.max(
          dirX * fillDir.x + dirY * fillDir.y + dirZ * fillDir.z,
          0.0,
        );
        final fillL = math.pow(fillC, 16.0).toDouble();
        r += 0.46 * fillL;
        g += 0.50 * fillL;
        b += 0.56 * fillL;

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

  /// SH-9 projection over RGBA8 sRGB equirectangular [bytes].
  static List<Vector3> _projectEquirectToSphericalHarmonics(
    Uint8List bytes,
    int width,
    int height,
  ) {
    return _projectEquirect(width, height, (px, py) {
      final o = (py * width + px) * 4;
      // Linearize sRGB the same way the shader's SRGBToLinear does.
      return (
        _srgbToLinear(bytes[o] / 255.0),
        _srgbToLinear(bytes[o + 1] / 255.0),
        _srgbToLinear(bytes[o + 2] / 255.0),
      );
    });
  }

  /// SH-9 projection over linear-radiance RGBA float equirect [pixels].
  static List<Vector3> _projectLinearEquirectToSphericalHarmonics(
    Float32List pixels,
    int width,
    int height,
  ) {
    return _projectEquirect(width, height, (px, py) {
      final o = (py * width + px) * 4;
      return (pixels[o], pixels[o + 1], pixels[o + 2]);
    });
  }

  /// Core SH-9 projection over an equirectangular image of the given
  /// dimensions. [sampleLinearRgb] returns the linear RGB radiance at a
  /// pixel; callers adapt their own storage (sRGB bytes, HDR floats).
  static List<Vector3> _projectEquirect(
    int width,
    int height,
    (double, double, double) Function(int px, int py) sampleLinearRgb,
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
      // The source equirect stores +y (up) at the top of the image (row 0),
      // but increasing v here maps to increasing latitude (up). Flip the row
      // lookup so the up hemisphere reads the top of the image, matching the
      // prefilter's source sampling; otherwise the diffuse irradiance is
      // vertically inverted relative to the specular radiance.
      final py = ((1.0 - v) * height).floor().clamp(0, height - 1);

      for (var i = 0; i < numPhi; i++) {
        final u = (i + 0.5) / numPhi;
        final longitude = (u - 0.5) * twoPi; // atan2(direction.z, direction.x)
        final dirX = cosLat * math.cos(longitude);
        final dirZ = cosLat * math.sin(longitude);
        final px = (u * width).floor().clamp(0, width - 1);

        final (r, g, b) = sampleLinearRgb(px, py);
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
  final gpu.Texture _diffuseShTexture;

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
  ///
  /// Empty for an environment baked from a sky ([fromSky]), whose coefficients
  /// are computed on the GPU and live only in [diffuseShTexture].
  List<Vector3> get diffuseSphericalHarmonics => _diffuseSphericalHarmonics;

  /// The diffuse SH coefficients as a `kDiffuseShCoefficientCount`-by-1
  /// `r16g16b16a16Float` texture (coefficient `i` at texel `i`, RGB used).
  ///
  /// The engine lighting samples this rather than a uniform so coefficients
  /// computed on the GPU (a baked sky) need no read-back. Built from
  /// [diffuseSphericalHarmonics] for the image-based constructors.
  gpu.Texture get diffuseShTexture => _diffuseShTexture;

  /// Uploads [sh] (9 RGB coefficients) to a 9-by-1 float texture.
  static gpu.Texture _shTextureFromList(List<Vector3> sh) {
    final half = Uint16List(kDiffuseShCoefficientCount * 4);
    for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
      half[i * 4] = _floatToHalfBits(sh[i].x);
      half[i * 4 + 1] = _floatToHalfBits(sh[i].y);
      half[i * 4 + 2] = _floatToHalfBits(sh[i].z);
      half[i * 4 + 3] = _floatToHalfBits(1.0);
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      kDiffuseShCoefficientCount,
      1,
      format: gpu.PixelFormat.r16g16b16a16Float,
    );
    texture.overwrite(ByteData.sublistView(half));
    return texture;
  }
}

/// Radiance asset paths recorded for [EnvironmentMap.fromAssets] results, so
/// provenance-aware tooling (the scene serializer) can recover where a live
/// environment came from.
final Expando<String> _environmentAssetPaths = Expando(
  'environment asset path',
);

/// The radiance asset path [environment] was loaded from through
/// [EnvironmentMap.fromAssets], or null for environments built another way.
/// {@category Lighting and environment}
String? environmentAssetPathOf(EnvironmentMap environment) =>
    _environmentAssetPaths[environment];
