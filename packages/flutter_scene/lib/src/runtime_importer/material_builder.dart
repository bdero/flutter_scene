import 'package:vector_math/vector_math.dart';

import '../material/material.dart';
import '../material/physically_based_material.dart';
import '../material/unlit_material.dart';
import 'gltf_types.dart';

/// Builds an engine [Material] from a glTF material. In Tier 1 textures are
/// not yet attached — slots that point at glTF textures stay null. Tier 2
/// fills them in.
Material buildMaterial(GltfMaterial? gm) {
  if (gm == null) {
    return PhysicallyBasedMaterial();
  }
  if (gm.unlit) {
    final m = UnlitMaterial();
    final pbr = gm.pbrMetallicRoughness;
    if (pbr != null) {
      m.baseColorFactor = _vec4(pbr.baseColorFactor);
    }
    return m;
  }
  final m = PhysicallyBasedMaterial();
  final pbr = gm.pbrMetallicRoughness;
  if (pbr != null) {
    m.baseColorFactor = _vec4(pbr.baseColorFactor);
    m.metallicFactor = pbr.metallicFactor;
    m.roughnessFactor = pbr.roughnessFactor;
  }
  if (gm.normalTexture?.scale != null) {
    m.normalScale = gm.normalTexture!.scale!;
  }
  if (gm.occlusionTexture?.strength != null) {
    m.occlusionStrength = gm.occlusionTexture!.strength!;
  }
  m.emissiveFactor = Vector4(
    gm.emissiveFactor.isNotEmpty ? gm.emissiveFactor[0] : 0.0,
    gm.emissiveFactor.length > 1 ? gm.emissiveFactor[1] : 0.0,
    gm.emissiveFactor.length > 2 ? gm.emissiveFactor[2] : 0.0,
    1.0,
  );
  return m;
}

Vector4 _vec4(List<double> components) {
  return Vector4(
    components.isNotEmpty ? components[0] : 1.0,
    components.length > 1 ? components[1] : 1.0,
    components.length > 2 ? components[2] : 1.0,
    components.length > 3 ? components[3] : 1.0,
  );
}
