import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:vector_math/vector_math.dart';

/// Tone mapping operator applied to the physically based lighting result.
///
/// The integer values are wire-compatible with the `tone_mapping_mode`
/// uniform in the standard fragment shader; don't reorder.
enum ToneMappingMode {
  /// Khronos PBR Neutral. Preserves base-color hue/saturation and only
  /// rolls off highlights. Good default for product/configurator
  /// rendering. This is the [Environment] default.
  pbrNeutral,

  /// ACES filmic (Stephen Hill fit). The classic games-y look; tends to
  /// desaturate and shift hue in the highlights.
  aces,

  /// Reinhard (`c / (1 + c)`). Cheap; flattens highlights.
  reinhard,

  /// No tone curve; the lighting result is just exposed and clamped to
  /// `[0, 1]`.
  linear,
}

/// Number of L2 spherical-harmonic coefficients used for diffuse
/// irradiance (bands 0..2).
const int kDiffuseShCoefficientCount = 9;

/// Sources of image-based lighting for a material.
///
/// Holds a radiance texture for specular reflections, plus the diffuse
/// (ambient) term, which is supplied either as 9 spherical-harmonic
/// coefficients (cheap, no texture fetch, no seams, the preferred form)
/// or, for backward compatibility, as a pre-convolved irradiance texture.
/// The radiance texture is currently expected to be an equirectangular
/// map; cubemap support will land once Flutter GPU exposes cubemaps.
///
/// Use [EnvironmentMap.fromAssets] or [EnvironmentMap.fromUIImages] to
/// construct one from images (which compute the diffuse SH from the
/// radiance image when no irradiance image is supplied),
/// [EnvironmentMap.fromGpuTextures] when you already hold GPU textures,
/// or [EnvironmentMap.empty] for a no-op placeholder.
base class EnvironmentMap {
  EnvironmentMap._(
    this._radianceTexture,
    this._irradianceTexture,
    this._diffuseSphericalHarmonics,
  ) : assert(
        _diffuseSphericalHarmonics == null ||
            _diffuseSphericalHarmonics.length == kDiffuseShCoefficientCount,
      );

  /// Creates an empty environment map. [radianceTexture] returns a white
  /// placeholder and the diffuse term is absent, contributing no
  /// directional lighting.
  factory EnvironmentMap.empty() {
    return EnvironmentMap._(null, null, null);
  }

  /// Wraps already-uploaded GPU textures.
  ///
  /// Provide either [diffuseSphericalHarmonics] (9 RGB coefficients;
  /// preferred) or [irradianceTexture] for the diffuse term. When both
  /// are omitted, diffuse falls back to a white placeholder.
  factory EnvironmentMap.fromGpuTextures({
    required gpu.Texture radianceTexture,
    gpu.Texture? irradianceTexture,
    List<Vector3>? diffuseSphericalHarmonics,
  }) {
    return EnvironmentMap._(
      radianceTexture,
      irradianceTexture,
      diffuseSphericalHarmonics,
    );
  }

  /// Builds an [EnvironmentMap] from already-decoded `dart:ui` images,
  /// uploading them to GPU textures.
  ///
  /// When [irradianceImage] is omitted (the common case), the diffuse
  /// term is computed as spherical harmonics from [radianceImage]; pass
  /// [diffuseSphericalHarmonics] to supply your own instead.
  static Future<EnvironmentMap> fromUIImages({
    required ui.Image radianceImage,
    ui.Image? irradianceImage,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    final radianceTexture = await gpuTextureFromImage(radianceImage);
    gpu.Texture? irradianceTexture;
    var sh = diffuseSphericalHarmonics;

    if (irradianceImage != null) {
      irradianceTexture = await gpuTextureFromImage(irradianceImage);
    } else {
      sh ??= await computeDiffuseSphericalHarmonics(radianceImage);
    }

    return EnvironmentMap._(radianceTexture, irradianceTexture, sh);
  }

  /// Loads an [EnvironmentMap] from the asset bundle.
  ///
  /// [radianceImagePath] is required; [irradianceImagePath] is optional.
  /// When it is omitted, the diffuse term is computed as spherical
  /// harmonics from the radiance image.
  static Future<EnvironmentMap> fromAssets({
    required String radianceImagePath,
    String? irradianceImagePath,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    final radianceImage = await imageFromAsset(radianceImagePath);
    final irradianceImage =
        irradianceImagePath == null
            ? null
            : await imageFromAsset(irradianceImagePath);
    return fromUIImages(
      radianceImage: radianceImage,
      irradianceImage: irradianceImage,
      diffuseSphericalHarmonics: diffuseSphericalHarmonics,
    );
  }

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
    final width = equirectangular.width;
    final height = equirectangular.height;
    final bytes = byteData.buffer.asUint8List();

    // Quadrature over a regular grid in equirectangular UV space. The grid
    // resolution is independent of the source image; sampling 192x96 cells
    // keeps the L2 projection accurate while staying fast on the CPU.
    const numPhi = 192;
    const numTheta = 96;
    final coefficients = List<Vector3>.generate(
      kDiffuseShCoefficientCount,
      (_) => Vector3.zero(),
    );

    const twoPi = 2.0 * math.pi;
    final cellSolidAngle = twoPi * math.pi / (numPhi * numTheta);

    for (var j = 0; j < numTheta; j++) {
      final v = (j + 0.5) / numTheta;
      final latitude = (v - 0.5) * math.pi; // asin(direction.y), in [-pi/2, pi/2]
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

  /// Whether this environment map has no radiance texture.
  ///
  /// An empty environment contributes no IBL; the [Scene] swaps it for
  /// the package's bundled default at draw time.
  bool isEmpty() => _radianceTexture == null;

  gpu.Texture? _radianceTexture;
  gpu.Texture? _irradianceTexture;
  final List<Vector3>? _diffuseSphericalHarmonics;

  // TODO(bdero): Once cubemaps are supported, change this to be an environment cubemap. (Cubemaps are missing from Flutter GPU at the time of writing: https://github.com/flutter/flutter/issues/145027)
  /// Represents the light being emitted by the environment from any direction.
  ///
  /// Currently expected to be an equirectangular map.
  gpu.Texture get radianceTexture =>
      Material.whitePlaceholder(_radianceTexture);

  // TODO(bdero): Once cubemaps are supported, change this to be an environment cubemap. (Cubemaps are missing from Flutter GPU at the time of writing: https://github.com/flutter/flutter/issues/145027)
  // TODO(bdero): Generate Gaussian blurred mipmaps for this texture for accurate roughness sampling.
  /// The integral of all light being received by a given surface at any direction.
  ///
  /// Currently expected to be an equirectangular map. Used only when
  /// [diffuseSphericalHarmonics] is null.
  gpu.Texture get irradianceTexture =>
      Material.whitePlaceholder(_irradianceTexture);

  /// The 9 RGB L2 spherical-harmonic coefficients for diffuse irradiance,
  /// or null if the diffuse term comes from [irradianceTexture] instead.
  List<Vector3>? get diffuseSphericalHarmonics => _diffuseSphericalHarmonics;
}

/// Shared material rendering properties.
///
/// A default environment can be set on the [Scene], which is automatically
/// applied to all materials. Individual [Material]s may optionally override the
/// default environment.
base class Environment {
  /// Creates an [Environment] with the given image-based-lighting map
  /// and shared tone-mapping parameters.
  ///
  /// All parameters are optional; the defaults pair an empty
  /// [EnvironmentMap] with `intensity = 1.0`, `exposure = 2.0`, and
  /// [ToneMappingMode.pbrNeutral].
  Environment({
    EnvironmentMap? environmentMap,
    this.intensity = 1.0,
    this.exposure = 2.0,
    this.toneMappingMode = ToneMappingMode.pbrNeutral,
  }) : environmentMap = environmentMap ?? EnvironmentMap.empty();

  /// Computes the exposure multiplier for a physical pinhole camera, the
  /// way real photographers reason about it: aperture (f-stops),
  /// [shutterSpeed] (seconds), and sensor [iso].
  ///
  /// Returns `1 / (1.2 * 2^EV100)` with
  /// `EV100 = log2(aperture^2 / shutterSpeed * 100 / iso)`, matching
  /// Filament's exposure model. Assign the result to [exposure].
  ///
  /// Reference values (sunlit exterior): `aperture: 16, shutterSpeed:
  /// 1/125, iso: 100`. Lower the aperture or ISO, or lengthen the
  /// shutter, to brighten.
  static double exposureFromPhysicalCamera({
    required double aperture,
    required double shutterSpeed,
    required double iso,
  }) {
    final ev100 = _log2(aperture * aperture / shutterSpeed * 100.0 / iso);
    return 1.0 / (1.2 * math.pow(2.0, ev100));
  }

  static double _log2(double x) => math.log(x) / math.ln2;

  /// Returns a copy of this environment with a different
  /// [environmentMap], preserving [intensity], [exposure], and
  /// [toneMappingMode].
  Environment withNewEnvironmentMap(EnvironmentMap environmentMap) {
    return Environment(
      environmentMap: environmentMap,
      intensity: intensity,
      exposure: exposure,
      toneMappingMode: toneMappingMode,
    );
  }

  /// The environment map to use for image-based-lighting.
  ///
  /// This must be an equirectangular map.
  EnvironmentMap environmentMap;

  /// The intensity of the environment map.
  double intensity;

  /// Linear exposure multiplier applied before tone mapping.
  ///
  /// `1.0` is neutral. Use [exposureFromPhysicalCamera] to derive a value
  /// from photographic camera settings.
  double exposure;

  /// Tone mapping operator applied to the lighting result.
  ToneMappingMode toneMappingMode;
}
