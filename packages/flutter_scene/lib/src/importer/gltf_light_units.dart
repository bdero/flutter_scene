import 'package:flutter_scene/src/importer/src/gltf/types.dart';

/// Converts glTF photometric intensity to the renderer's linear radiometric
/// scale. The 683 lm/W constant is the peak photopic luminous efficacy.
/// Dividing by the color's luminance keeps `color * intensity` at the authored
/// luminance, so saturated colors receive a larger radiometric multiplier.
double gltfLightIntensity(GltfPunctualLight light) {
  final color = light.color;
  final luminance = color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722;
  if (luminance <= 1e-8 || light.intensity <= 0.0) return 0.0;
  return light.intensity / (683.0 * luminance);
}
