/// glTF extension recognition, the single source of truth for what
/// [parseGltfJson] understands. Adding decoder support for a planned
/// extension is a one-line move from [kPlannedGltfExtensions] to
/// [kRecognizedGltfExtensions].
library;

/// Extensions fully parsed today.
const Set<String> kRecognizedGltfExtensions = {
  'KHR_lights_punctual',
  'KHR_materials_variants',
  'KHR_materials_anisotropy',
  'KHR_materials_clearcoat',
  'KHR_materials_diffuse_transmission',
  'KHR_materials_dispersion',
  'KHR_materials_emissive_strength',
  'KHR_materials_ior',
  'KHR_materials_iridescence',
  'KHR_materials_sheen',
  'KHR_materials_specular',
  'KHR_materials_transmission',
  'KHR_materials_volume',
  'KHR_materials_unlit',
  'KHR_texture_transform',
  'EXT_meshopt_compression',
  // Only widens which attributes may use the quantized component types the
  // accessor readers already convert, so no dedicated parsing is needed.
  'KHR_mesh_quantization',
  'KHR_draco_mesh_compression',
  'KHR_texture_basisu',
  'EXT_lights_image_based',
};

/// Extensions not parsed yet but with support planned. Named individually so
/// [UnsupportedRequiredExtensionException] and the `extensionsUsed` warning
/// can say support is planned instead of a bare unsupported.
const Set<String> kPlannedGltfExtensions = {};

/// Thrown when a glTF document's `extensionsRequired` names an extension this
/// engine can't parse. Every unsupported required extension is named in one
/// message, so a single fix (or a single wait for planned support) covers
/// the whole file.
/// {@category Assets and loading}
class UnsupportedRequiredExtensionException extends FormatException {
  UnsupportedRequiredExtensionException(this.extensions)
    : super(_message(extensions));

  /// Names of every required extension this engine can't parse.
  final List<String> extensions;

  static String _message(List<String> extensions) {
    final parts = extensions.map(
      (name) => kPlannedGltfExtensions.contains(name)
          ? '$name (support planned)'
          : '$name (unsupported)',
    );
    return 'glTF requires unsupported extension(s): ${parts.join(', ')}';
  }
}
