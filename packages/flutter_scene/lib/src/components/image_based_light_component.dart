import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/material/diffuse_sh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// The image-based lighting a loaded model declares through
/// `EXT_lights_image_based`, surfaced so an application can build an
/// [EnvironmentMap] from it.
///
/// The importer attaches this to the root of a model whose default scene
/// references such a light. Nothing is applied automatically: reading it and
/// deciding whether the model's environment should light the whole scene is
/// the application's call.
///
/// ```dart
/// final ibl = ImageBasedLightComponent.of(model);
/// if (ibl != null) {
///   scene.environment = await EnvironmentMap.fromKtx2Bytes(
///     myCubemapBytes,
///     diffuseSphericalHarmonics: ibl.diffuseSphericalHarmonics,
///   );
///   scene.environmentIntensity = ibl.intensity;
/// }
/// ```
///
/// TODO(ibl-gltf-auto-apply): wire this into `Scene.environment` on import,
/// behind an opt-in, once the specular chain can be assembled straight into a
/// radiance cube (the extension ships one 2D image per face per roughness
/// level, which needs an upload path that stitches them).
/// {@category Lighting and environment}
class ImageBasedLightComponent extends Component {
  /// Used by the importer; not for application construction.
  @internal
  ImageBasedLightComponent.internal({
    required this.name,
    required this.rotation,
    required this.intensity,
    required List<Vector3> irradianceCoefficients,
    required this.specularImageSize,
    required List<List<Uint8List>> specularImages,
  }) : irradianceCoefficients = List.unmodifiable(irradianceCoefficients),
       specularImages = List.unmodifiable(
         specularImages.map(List<Uint8List>.unmodifiable),
       );

  /// The first image-based light on [root] or its subtree, breadth-first, or
  /// null when the model declared none.
  static ImageBasedLightComponent? of(Node root) {
    final own = root.getComponents<ImageBasedLightComponent>();
    if (own.isNotEmpty) return own.first;
    final queue = <Node>[...root.children];
    for (var i = 0; i < queue.length; i++) {
      final found = queue[i].getComponents<ImageBasedLightComponent>();
      if (found.isNotEmpty) return found.first;
      queue.addAll(queue[i].children);
    }
    return null;
  }

  /// The light's name in the source document, or null.
  final String? name;

  /// Rotation the source declares for the cubemap relative to the scene.
  /// Feed it to `Scene.environmentTransform` to honor it.
  final Quaternion rotation;

  /// Scalar multiplier the source declares, suitable for
  /// `Scene.environmentIntensity`.
  final double intensity;

  /// The extension's 9 RGB irradiance coefficients exactly as stored, or empty
  /// when the source omitted them.
  ///
  /// These are the raw radiance projection. Use
  /// [diffuseSphericalHarmonics] for the form the engine's shading expects.
  final List<Vector3> irradianceCoefficients;

  /// Face size of the specular chain's mip 0.
  final int specularImageSize;

  /// `specularImages[level][face]` encoded image bytes, faces in cube order
  /// (+X, -X, +Y, -Y, +Z, -Z), level 0 the mirror level. Empty when the
  /// importer could not source them.
  final List<List<Uint8List>> specularImages;

  /// [irradianceCoefficients] brought onto the engine's diffuse contract: the
  /// Lambertian `A_l` band factors and the `1/pi` BRDF term folded in, ready
  /// for `EnvironmentMap.fromKtx2Bytes` or `EnvironmentMap.fromGpuTextures`.
  ///
  /// Null when the source declared no coefficients. Exporters disagree on
  /// whether they pre-convolve, so check the result with
  /// [describeDiffuseSphericalHarmonics]: its mean must match the source
  /// environment's average radiance, not `pi` times it.
  List<Vector3>? get diffuseSphericalHarmonics {
    if (irradianceCoefficients.length != kDiffuseShCoefficientCount) {
      return null;
    }
    // A_l / pi is 1, 2/3, 1/4 for bands 0, 1, 2.
    return <Vector3>[
      irradianceCoefficients[0].clone(),
      for (var k = 1; k <= 3; k++) irradianceCoefficients[k] * (2.0 / 3.0),
      for (var k = 4; k <= 8; k++) irradianceCoefficients[k] * 0.25,
    ];
  }
}
