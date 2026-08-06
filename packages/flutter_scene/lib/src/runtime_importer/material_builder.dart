import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/importer/gltf.dart';

import '../material/material.dart';
import '../material/physical_material.dart';
import '../material/physically_based_material.dart';
import '../material/unlit_material.dart';
import '../texture/texture2d.dart';

/// Builds an engine [Material] from a glTF material. Tier 2 wires up the
/// texture slots from a pre-decoded list of [Texture2D]s indexed
/// 1:1 with `GltfDocument.textures`.
Future<Material> buildMaterial(
  GltfMaterial? gm,
  List<Texture2D> textures,
) async {
  if (gm == null) {
    return PhysicallyBasedMaterial();
  }
  if (gm.unlit) {
    final m = UnlitMaterial();
    m.name = gm.name ?? '';
    final pbr = gm.pbrMetallicRoughness;
    if (pbr != null) {
      m.baseColorFactor = _vec4(pbr.baseColorFactor);
      final t = _resolveTexture(pbr.baseColorTexture, textures);
      if (t != null) m.baseColorTexture = t;
      m.baseColorTextureTransform = _textureTransform(pbr.baseColorTexture);
      m.baseColorTextureTexCoord = _textureTexCoord(pbr.baseColorTexture);
    }
    m.doubleSided = gm.doubleSided;
    return m;
  }
  return PhysicallyBasedMaterial.fromDescriptor(
    physicalMaterialDescriptor(gm, textures),
  );
}

/// Normalizes a glTF material into scene-native physical properties.
PhysicalMaterialDescriptor physicalMaterialDescriptor(
  GltfMaterial material,
  List<Texture2D> textures,
) {
  final pbr = material.pbrMetallicRoughness;
  final clearcoat = material.clearcoat;
  final diffuseTransmission = material.diffuseTransmission;
  final iridescence = material.iridescence;
  final sheen = material.sheen;
  final specular = material.specular;
  final transmission = material.transmission;
  final volume = material.volume;
  final anisotropy = material.anisotropy;
  return PhysicalMaterialDescriptor(
    name: material.name ?? '',
    baseColorTexture: _physicalTexture(pbr?.baseColorTexture, textures),
    baseColor: _vec4(pbr?.baseColorFactor ?? const [1, 1, 1, 1]),
    metallicRoughnessTexture: _physicalTexture(
      pbr?.metallicRoughnessTexture,
      textures,
    ),
    metallic: pbr?.metallicFactor ?? 1.0,
    roughness: pbr?.roughnessFactor ?? 1.0,
    normalTexture: _physicalTexture(material.normalTexture, textures),
    normalScale: material.normalTexture?.scale ?? 1.0,
    occlusionTexture: _physicalTexture(material.occlusionTexture, textures),
    occlusionStrength: material.occlusionTexture?.strength ?? 1.0,
    emissiveTexture: _physicalTexture(material.emissiveTexture, textures),
    emissive: _vec4([...material.emissiveFactor, 1.0]),
    emissiveStrength: material.emissiveStrength,
    specularTexture: _physicalTexture(specular?.texture, textures),
    specular: specular?.factor ?? 1.0,
    specularColorTexture: _physicalTexture(specular?.colorTexture, textures),
    specularColor: specular == null
        ? Vector4.all(1.0)
        : _vec4([...specular.colorFactor, 1.0]),
    ior: material.ior,
    clearcoatTexture: _physicalTexture(clearcoat?.texture, textures),
    clearcoat: clearcoat?.factor ?? 0.0,
    clearcoatRoughnessTexture: _physicalTexture(
      clearcoat?.roughnessTexture,
      textures,
    ),
    clearcoatRoughness: clearcoat?.roughnessFactor ?? 0.0,
    clearcoatNormalTexture: _physicalTexture(
      clearcoat?.normalTexture,
      textures,
    ),
    clearcoatNormalScale: Vector2.all(clearcoat?.normalTexture?.scale ?? 1.0),
    sheenColorTexture: _physicalTexture(sheen?.colorTexture, textures),
    sheenColor: sheen == null
        ? Vector4.zero()
        : _vec4([...sheen.colorFactor, 1.0]),
    sheenRoughnessTexture: _physicalTexture(sheen?.roughnessTexture, textures),
    sheenRoughness: sheen?.roughnessFactor ?? 0.0,
    transmissionTexture: _physicalTexture(transmission?.texture, textures),
    transmission: transmission?.factor ?? 0.0,
    diffuseTransmissionTexture: _physicalTexture(
      diffuseTransmission?.texture,
      textures,
    ),
    diffuseTransmission: diffuseTransmission?.factor ?? 0.0,
    diffuseTransmissionColorTexture: _physicalTexture(
      diffuseTransmission?.colorTexture,
      textures,
    ),
    diffuseTransmissionColor: diffuseTransmission == null
        ? Vector4.all(1.0)
        : _vec4([...diffuseTransmission.colorFactor, 1.0]),
    thicknessTexture: _physicalTexture(volume?.thicknessTexture, textures),
    thickness: volume?.thicknessFactor ?? 0.0,
    attenuationDistance: volume?.attenuationDistance ?? double.infinity,
    attenuationColor: volume == null
        ? Vector4.all(1.0)
        : _vec4([...volume.attenuationColor, 1.0]),
    dispersion: material.dispersion,
    iridescenceTexture: _physicalTexture(iridescence?.texture, textures),
    iridescence: iridescence?.factor ?? 0.0,
    iridescenceIor: iridescence?.ior ?? 1.3,
    iridescenceThicknessTexture: _physicalTexture(
      iridescence?.thicknessTexture,
      textures,
    ),
    iridescenceThicknessMinimum: iridescence?.thicknessMinimum ?? 100.0,
    iridescenceThicknessMaximum: iridescence?.thicknessMaximum ?? 400.0,
    anisotropyTexture: _physicalTexture(anisotropy?.texture, textures),
    anisotropy: anisotropy?.strength ?? 0.0,
    anisotropyRotation: anisotropy?.rotation ?? 0.0,
    alphaMode: _alphaMode(material.alphaMode),
    alphaCutoff: material.alphaCutoff,
    doubleSided: material.doubleSided,
  );
}

PhysicalTexture _physicalTexture(
  GltfTextureInfo? info,
  List<Texture2D> textures,
) => PhysicalTexture(
  source: _resolveTexture(info, textures),
  transform: _textureTransform(info),
  texCoord: _textureTexCoord(info),
);

TextureTransform _textureTransform(GltfTextureInfo? info) {
  final transform = info?.transform;
  if (transform == null) return TextureTransform();
  return TextureTransform(
    offset: Vector2(
      transform.offset.isNotEmpty ? transform.offset[0] : 0.0,
      transform.offset.length > 1 ? transform.offset[1] : 0.0,
    ),
    scale: Vector2(
      transform.scale.isNotEmpty ? transform.scale[0] : 1.0,
      transform.scale.length > 1 ? transform.scale[1] : 1.0,
    ),
    rotation: transform.rotation,
  );
}

int _textureTexCoord(GltfTextureInfo? info) =>
    (info?.transform?.texCoord ?? info?.texCoord ?? 0).clamp(0, 1);

/// Maps a glTF `alphaMode` string to the engine [AlphaMode].
AlphaMode _alphaMode(String mode) {
  switch (mode) {
    case 'MASK':
      return AlphaMode.mask;
    case 'BLEND':
      return AlphaMode.blend;
    default:
      return AlphaMode.opaque;
  }
}

Texture2D? _resolveTexture(GltfTextureInfo? info, List<Texture2D> textures) {
  if (info == null) return null;
  if (info.index < 0 || info.index >= textures.length) return null;
  return textures[info.index];
}

Vector4 _vec4(List<double> components) {
  return Vector4(
    components.isNotEmpty ? components[0] : 1.0,
    components.length > 1 ? components[1] : 1.0,
    components.length > 2 ? components[2] : 1.0,
    components.length > 3 ? components[3] : 1.0,
  );
}
