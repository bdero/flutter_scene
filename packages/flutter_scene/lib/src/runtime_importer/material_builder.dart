import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene_importer/gltf.dart';

import '../material/material.dart';
import '../material/physically_based_material.dart';
import '../material/unlit_material.dart';

/// Builds an engine [Material] from a glTF material. Tier 2 wires up the
/// texture slots from a pre-decoded list of [gpu.Texture]s indexed
/// 1:1 with `GltfDocument.textures`.
Material buildMaterial(GltfMaterial? gm, List<gpu.Texture> textures) {
  if (gm == null) {
    return PhysicallyBasedMaterial();
  }
  if (gm.unlit) {
    final m = UnlitMaterial();
    final pbr = gm.pbrMetallicRoughness;
    if (pbr != null) {
      m.baseColorFactor = _vec4(pbr.baseColorFactor);
      final t = _resolveTexture(pbr.baseColorTexture, textures);
      if (t != null) m.baseColorTexture = t;
    }
    return m;
  }
  final m = PhysicallyBasedMaterial();
  final pbr = gm.pbrMetallicRoughness;
  if (pbr != null) {
    m.baseColorFactor = _vec4(pbr.baseColorFactor);
    m.metallicFactor = pbr.metallicFactor;
    m.roughnessFactor = pbr.roughnessFactor;
    m.baseColorTexture = _resolveTexture(pbr.baseColorTexture, textures);
    m.metallicRoughnessTexture = _resolveTexture(
      pbr.metallicRoughnessTexture,
      textures,
    );
  }
  m.normalTexture = _resolveTexture(gm.normalTexture, textures);
  if (gm.normalTexture?.scale != null) {
    m.normalScale = gm.normalTexture!.scale!;
  }
  m.occlusionTexture = _resolveTexture(gm.occlusionTexture, textures);
  if (gm.occlusionTexture?.strength != null) {
    m.occlusionStrength = gm.occlusionTexture!.strength!;
  }
  m.emissiveTexture = _resolveTexture(gm.emissiveTexture, textures);
  m.emissiveFactor = Vector4(
    gm.emissiveFactor.isNotEmpty ? gm.emissiveFactor[0] : 0.0,
    gm.emissiveFactor.length > 1 ? gm.emissiveFactor[1] : 0.0,
    gm.emissiveFactor.length > 2 ? gm.emissiveFactor[2] : 0.0,
    1.0,
  );
  return m;
}

gpu.Texture? _resolveTexture(
  GltfTextureInfo? info,
  List<gpu.Texture> textures,
) {
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
