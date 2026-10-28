// Resolves KHR_animation_pointer channels against the parsed document.
// Pointers follow RFC 6901 (JSON Pointer); the targets this engine drives are
// listed in the KHR_animation_pointer specification's "Animatable
// properties" tables.

import 'dart:typed_data';

import 'types.dart';
import 'warnings.dart';

// Node properties a pointer drives through a plain channel.
const _nodeChannelPaths = {'translation', 'rotation', 'scale', 'weights'};

// Material factors, by the pointer's suffix after `/materials/{m}/`, mapped
// to the engine material property and its float count.
const _materialFactors = <String, (String, int)>{
  'pbrMetallicRoughness/baseColorFactor': ('baseColorFactor', 4),
  'pbrMetallicRoughness/metallicFactor': ('metallicFactor', 1),
  'pbrMetallicRoughness/roughnessFactor': ('roughnessFactor', 1),
  'emissiveFactor': ('emissiveFactor', 3),
  'alphaCutoff': ('alphaCutoff', 1),
  'normalTexture/scale': ('normalScale', 1),
  'occlusionTexture/strength': ('occlusionStrength', 1),
  'extensions/KHR_materials_emissive_strength/emissiveStrength': (
    'emissiveStrength',
    1,
  ),
  'extensions/KHR_materials_ior/ior': ('ior', 1),
  'extensions/KHR_materials_transmission/transmissionFactor': (
    'transmission',
    1,
  ),
  'extensions/KHR_materials_volume/thicknessFactor': ('thickness', 1),
  'extensions/KHR_materials_volume/attenuationDistance': (
    'attenuationDistance',
    1,
  ),
  'extensions/KHR_materials_volume/attenuationColor': ('attenuationColor', 3),
  'extensions/KHR_materials_clearcoat/clearcoatFactor': ('clearcoat', 1),
  'extensions/KHR_materials_clearcoat/clearcoatRoughnessFactor': (
    'clearcoatRoughness',
    1,
  ),
  'extensions/KHR_materials_sheen/sheenColorFactor': ('sheenColor', 3),
  'extensions/KHR_materials_sheen/sheenRoughnessFactor': ('sheenRoughness', 1),
  'extensions/KHR_materials_specular/specularFactor': ('specular', 1),
  'extensions/KHR_materials_specular/specularColorFactor': ('specularColor', 3),
  'extensions/KHR_materials_iridescence/iridescenceFactor': ('iridescence', 1),
  'extensions/KHR_materials_iridescence/iridescenceIor': ('iridescenceIor', 1),
  'extensions/KHR_materials_iridescence/iridescenceThicknessMinimum': (
    'iridescenceThicknessMinimum',
    1,
  ),
  'extensions/KHR_materials_iridescence/iridescenceThicknessMaximum': (
    'iridescenceThicknessMaximum',
    1,
  ),
  'extensions/KHR_materials_anisotropy/anisotropyStrength': ('anisotropy', 1),
  'extensions/KHR_materials_anisotropy/anisotropyRotation': (
    'anisotropyRotation',
    1,
  ),
  'extensions/KHR_materials_dispersion/dispersion': ('dispersion', 1),
  'extensions/KHR_materials_diffuse_transmission/diffuseTransmissionFactor': (
    'diffuseTransmission',
    1,
  ),
  'extensions/KHR_materials_diffuse_transmission/diffuseTransmissionColorFactor':
      ('diffuseTransmissionColor', 3),
};

// Texture infos whose KHR_texture_transform animates, by the pointer's
// suffix up to the texture info. The engine names each slot after the
// texture info's own key.
const _materialTextures = {
  'pbrMetallicRoughness/baseColorTexture',
  'pbrMetallicRoughness/metallicRoughnessTexture',
  'normalTexture',
  'occlusionTexture',
  'emissiveTexture',
  'extensions/KHR_materials_specular/specularTexture',
  'extensions/KHR_materials_specular/specularColorTexture',
  'extensions/KHR_materials_clearcoat/clearcoatTexture',
  'extensions/KHR_materials_clearcoat/clearcoatRoughnessTexture',
  'extensions/KHR_materials_clearcoat/clearcoatNormalTexture',
  'extensions/KHR_materials_sheen/sheenColorTexture',
  'extensions/KHR_materials_sheen/sheenRoughnessTexture',
  'extensions/KHR_materials_transmission/transmissionTexture',
  'extensions/KHR_materials_diffuse_transmission/diffuseTransmissionTexture',
  'extensions/KHR_materials_diffuse_transmission/diffuseTransmissionColorTexture',
  'extensions/KHR_materials_volume/thicknessTexture',
  'extensions/KHR_materials_iridescence/iridescenceTexture',
  'extensions/KHR_materials_iridescence/iridescenceThicknessTexture',
  'extensions/KHR_materials_anisotropy/anisotropyTexture',
};

const _textureTransformProperties = {'offset': 2, 'scale': 2, 'rotation': 1};

/// Rewrites each `KHR_animation_pointer` channel in [animations] into a
/// plain channel for a node transform or weights pointer, or into engine
/// path targets otherwise. A pointer the engine can't
/// drive adds a warning to [warnings] and is left untargeted, so the
/// importers skip it.
List<GltfAnimation> resolveGltfAnimationPointers(
  List<GltfAnimation> animations, {
  required int? scene,
  required List<GltfScene> scenes,
  required List<GltfNode> nodes,
  required List<GltfMesh> meshes,
  required List<GltfMaterial> materials,
  required List<GltfPunctualLight> lights,
  required List<GltfImportWarning> warnings,
}) {
  if (!animations.any((a) => a.channels.any((c) => c.pointer != null))) {
    return animations;
  }
  final materialUsers = _materialUsers(scene, scenes, nodes, meshes);
  GltfAnimationChannel resolve(GltfAnimationChannel channel) {
    final pointer = channel.pointer;
    if (pointer == null) return channel;
    final resolved = _resolve(
      channel,
      pointer,
      nodes: nodes,
      materials: materials,
      lights: lights,
      materialUsers: materialUsers,
    );
    if (resolved != null) return resolved;
    warnings.add(
      GltfImportWarning(
        'Skipping KHR_animation_pointer channel "$pointer", which this '
        "engine can't animate",
      ),
    );
    return channel;
  }

  return [
    for (final animation in animations)
      GltfAnimation(
        name: animation.name,
        channels: [for (final c in animation.channels) resolve(c)],
        samplers: animation.samplers,
      ),
  ];
}

// Returns the resolved channel, or null for a pointer the engine can't
// drive. A pointer into an unused material resolves with no targets.
GltfAnimationChannel? _resolve(
  GltfAnimationChannel channel,
  String pointer, {
  required List<GltfNode> nodes,
  required List<GltfMaterial> materials,
  required List<GltfPunctualLight> lights,
  required Map<int, (int, int)> materialUsers,
}) {
  if (!pointer.startsWith('/')) return null;
  final segments = [
    for (final s in pointer.substring(1).split('/'))
      s.replaceAll('~1', '/').replaceAll('~0', '~'),
  ];
  GltfAnimationChannel paths(
    List<GltfAnimationPathTarget> targets,
    int componentCount, {
    int? light,
  }) => GltfAnimationChannel(
    sampler: channel.sampler,
    targetNode: null,
    targetPath: channel.targetPath,
    pointer: pointer,
    pathTargets: targets,
    pathComponentCount: componentCount,
    pointerLight: light,
  );

  switch (segments) {
    case ['nodes', final n, final path] when _nodeChannelPaths.contains(path):
      final node = _index(n, nodes.length);
      if (node == null) return null;
      return GltfAnimationChannel(
        sampler: channel.sampler,
        targetNode: node,
        targetPath: path,
        pointer: pointer,
      );
    case ['nodes', final n, 'extensions', 'KHR_node_visibility', 'visible']:
      final node = _index(n, nodes.length);
      if (node == null) return null;
      return paths([GltfAnimationPathTarget(node, 'visible')], 1);
    case ['extensions', 'KHR_lights_punctual', 'lights', final l, ...final p]:
      final light = _index(l, lights.length);
      if (light == null) return null;
      final type = lights[light].type;
      final (property, count) = switch (p) {
        ['color'] => ('color', 3),
        ['intensity'] => ('intensity', 1),
        ['range'] when type != 'directional' => ('range', 1),
        ['spot', final angle]
            when type == 'spot' &&
                (angle == 'innerConeAngle' || angle == 'outerConeAngle') =>
          (angle, 1),
        _ => (null, 0),
      };
      if (property == null) return null;
      return paths(
        [
          for (var i = 0; i < nodes.length; i++)
            if (nodes[i].light == light)
              GltfAnimationPathTarget(i, 'light/$property'),
        ],
        count,
        light: light,
      );
    case ['materials', final m, ...final p]:
      final material = _index(m, materials.length);
      if (material == null) return null;
      final (property, count) = _materialProperty(
        p.join('/'),
        unlit: materials[material].unlit,
      );
      if (property == null) return null;
      final user = materialUsers[material];
      return paths([
        if (user != null)
          GltfAnimationPathTarget(
            user.$1,
            'primitives/${user.$2}/material/$property',
          ),
      ], count);
  }
  // TODO(gltf-animation-pointer): cameras (yfov, znear, xmag, ...), single
  // morph weights (`/nodes/{n}/weights/{i}`), and texCoord need engine
  // properties to drive before they can import.
  return null;
}

// The engine property, and its float count, for a material pointer's
// suffix, or (null, 0) when the engine doesn't animate it. Unlit materials
// only carry their base color.
(String?, int) _materialProperty(String suffix, {required bool unlit}) {
  final factor = _materialFactors[suffix];
  if (factor != null) {
    if (unlit && factor.$1 != 'baseColorFactor') return (null, 0);
    return factor;
  }
  const transform = '/extensions/KHR_texture_transform/';
  final split = suffix.indexOf(transform);
  if (split < 0) return (null, 0);
  final texture = suffix.substring(0, split);
  final property = suffix.substring(split + transform.length);
  final count = _textureTransformProperties[property];
  if (count == null || !_materialTextures.contains(texture)) return (null, 0);
  if (unlit && texture != 'pbrMetallicRoughness/baseColorTexture') {
    return (null, 0);
  }
  return ('${texture.split('/').last}/$property', count);
}

int? _index(String segment, int length) {
  final i = int.tryParse(segment);
  return i != null && i >= 0 && i < length ? i : null;
}

// Each material's first user as (node, triangle primitive index), the
// primitive's index among the triangle primitives both importers keep.
// Materials are shared by every primitive using them, so animating one
// user animates them all. Nodes in the default scene come first, so the
// target is reachable from the imported root.
Map<int, (int, int)> _materialUsers(
  int? scene,
  List<GltfScene> scenes,
  List<GltfNode> nodes,
  List<GltfMesh> meshes,
) {
  final order = <int>[];
  final seen = <int>{};
  void visit(int node) {
    if (node < 0 || node >= nodes.length || !seen.add(node)) return;
    order.add(node);
    nodes[node].children.forEach(visit);
  }

  final sceneIndex = scene ?? (scenes.isNotEmpty ? 0 : -1);
  if (sceneIndex >= 0 && sceneIndex < scenes.length) {
    scenes[sceneIndex].nodes.forEach(visit);
  }
  for (var i = 0; i < nodes.length; i++) {
    visit(i);
  }

  final users = <int, (int, int)>{};
  for (final node in order) {
    final mesh = nodes[node].mesh;
    if (mesh == null || mesh < 0 || mesh >= meshes.length) continue;
    var triangle = 0;
    for (final primitive in meshes[mesh].primitives) {
      if (primitive.mode != 4) continue;
      final material = primitive.material;
      if (material != null) users.putIfAbsent(material, () => (node, triangle));
      triangle++;
    }
  }
  return users;
}

/// Converts a path channel's decoded glTF keyframes to engine units.
///
/// Light color and intensity convert against the light's static values as
/// `gltfLightIntensity` does. Each color keyframe is rescaled to the static
/// color's luminance and each intensity divides by it, so their product
/// keeps the authored photometric luminance whichever of the two animates.
Float32List convertGltfPathKeyframes(
  GltfAnimationChannel channel,
  List<GltfPunctualLight> lights,
  Float32List values,
) {
  final light = channel.pointerLight;
  final path = channel.pathTargets.firstOrNull?.path;
  if (light == null || light >= lights.length) return values;
  final staticLuminance = _luminance(
    lights[light].color.x,
    lights[light].color.y,
    lights[light].color.z,
  );
  if (path == 'light/intensity') {
    return Float32List.fromList([
      for (final intensity in values)
        staticLuminance <= 1e-8 || intensity <= 0
            ? 0
            : intensity / (683.0 * staticLuminance),
    ]);
  }
  if (path == 'light/color' && staticLuminance > 1e-8) {
    final out = Float32List(values.length);
    for (var i = 0; i + 3 <= values.length; i += 3) {
      final luminance = _luminance(values[i], values[i + 1], values[i + 2]);
      if (luminance <= 1e-8) continue;
      final scale = staticLuminance / luminance;
      for (var c = 0; c < 3; c++) {
        out[i + c] = values[i + c] * scale;
      }
    }
    return out;
  }
  return values;
}

double _luminance(double r, double g, double b) =>
    r * 0.2126 + g * 0.7152 + b * 0.0722;
