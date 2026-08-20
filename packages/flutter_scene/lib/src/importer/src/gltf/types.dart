import 'package:vector_math/vector_math.dart';

import 'warnings.dart';

/// In-memory representation of the parts of glTF 2.0 that flutter_scene
/// consumes. Field names match the glTF spec (camelCase). Indexes into other
/// arrays are stored as `int?` and resolved at use time.

class GltfDocument {
  GltfDocument({
    this.scene,
    this.scenes = const [],
    this.nodes = const [],
    this.meshes = const [],
    this.accessors = const [],
    this.bufferViews = const [],
    this.buffers = const [],
    this.materials = const [],
    this.textures = const [],
    this.images = const [],
    this.samplers = const [],
    this.skins = const [],
    this.animations = const [],
    this.lights = const [],
    this.imageBasedLights = const [],
    this.materialsVariants = const [],
    this.warnings = const [],
  });

  final int? scene;
  final List<GltfScene> scenes;
  final List<GltfNode> nodes;
  final List<GltfMesh> meshes;
  final List<GltfAccessor> accessors;
  final List<GltfBufferView> bufferViews;
  final List<GltfBuffer> buffers;
  final List<GltfMaterial> materials;
  final List<GltfTexture> textures;
  final List<GltfImage> images;
  final List<GltfSampler> samplers;
  final List<GltfSkin> skins;
  final List<GltfAnimation> animations;

  /// Punctual lights declared by the `KHR_lights_punctual` extension, indexed
  /// by [GltfNode.light]. Empty when the extension is absent.
  final List<GltfPunctualLight> lights;

  /// Image-based lights declared by the `EXT_lights_image_based` extension,
  /// indexed by [GltfScene.imageBasedLight]. Empty when the extension is
  /// absent.
  final List<GltfImageBasedLight> imageBasedLights;

  /// Variant names declared by the `KHR_materials_variants` extension, in
  /// declaration order. Empty when the extension is absent. Primitive
  /// mappings ([GltfMeshPrimitive.variantMappings]) index into this list.
  final List<String> materialsVariants;

  /// Non-fatal issues noticed while parsing this document (currently,
  /// unrecognized `extensionsUsed` entries). Import entry points deliver
  /// these to a caller's warning callback, or print them when none is given.
  final List<GltfImportWarning> warnings;

  /// A copy of this document with the given lists replaced.
  GltfDocument copyWith({
    List<GltfBufferView>? bufferViews,
    List<GltfImage>? images,
  }) {
    return GltfDocument(
      scene: scene,
      scenes: scenes,
      nodes: nodes,
      meshes: meshes,
      accessors: accessors,
      bufferViews: bufferViews ?? this.bufferViews,
      buffers: buffers,
      materials: materials,
      textures: textures,
      images: images ?? this.images,
      samplers: samplers,
      skins: skins,
      animations: animations,
      lights: lights,
      materialsVariants: materialsVariants,
      warnings: warnings,
    );
  }
}

/// A `KHR_lights_punctual` light definition. Fields match the extension spec.
/// [innerConeAngle]/[outerConeAngle] are only meaningful for `spot` lights.
class GltfPunctualLight {
  GltfPunctualLight({
    this.name,
    required this.type,
    Vector3? color,
    this.intensity = 1.0,
    this.range,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = 0.7853981633974483, // pi / 4
  }) : color = color ?? Vector3(1.0, 1.0, 1.0);

  final String? name;

  /// One of `directional`, `point`, or `spot`.
  final String type;
  final Vector3 color;
  final double intensity;

  /// Distance cutoff, or null for infinite range (point and spot only).
  final double? range;
  final double innerConeAngle;
  final double outerConeAngle;
}

/// An `EXT_lights_image_based` light definition. Fields match the extension
/// spec; the images are left as indices into `GltfDocument.images` so the
/// parse stays free of resource resolution.
class GltfImageBasedLight {
  GltfImageBasedLight({
    this.name,
    Quaternion? rotation,
    this.intensity = 1.0,
    required this.irradianceCoefficients,
    required this.specularImageSize,
    required this.specularImages,
  }) : rotation = rotation ?? Quaternion.identity();

  final String? name;

  /// Rotation of the light's cubemap relative to the scene.
  final Quaternion rotation;

  /// Scalar multiplier on both the irradiance and the specular images.
  final double intensity;

  /// The spec's 9x3 irradiance spherical-harmonic coefficients, as stored.
  ///
  /// These are the source radiance projection, without the Lambertian
  /// convolution or the `1/pi` the engine folds in at bake time; see
  /// `ImageBasedLightComponent.diffuseSphericalHarmonics` for the converted
  /// form.
  final List<Vector3> irradianceCoefficients;

  /// Face size of the specular cubemap's mip 0.
  final int specularImageSize;

  /// `specularImages[level][face]` image indices, faces in cube order
  /// (+X, -X, +Y, -Y, +Z, -Z). Level count is the roughness chain length.
  final List<List<int>> specularImages;
}

class GltfScene {
  GltfScene({this.name, this.nodes = const [], this.imageBasedLight});
  final String? name;
  final List<int> nodes;

  /// Index into [GltfDocument.imageBasedLights] (`EXT_lights_image_based`),
  /// or null.
  final int? imageBasedLight;
}

class GltfNode {
  GltfNode({
    this.name,
    this.mesh,
    this.skin,
    this.light,
    this.children = const [],
    this.matrix,
    this.translation,
    this.rotation,
    this.scale,
    this.weights,
  });

  final String? name;
  final int? mesh;
  final int? skin;

  /// Index into [GltfDocument.lights] (`KHR_lights_punctual`), or null.
  final int? light;
  final List<int> children;

  /// If [matrix] is set, [translation]/[rotation]/[scale] are ignored.
  final Matrix4? matrix;
  final Vector3? translation;
  final Quaternion? rotation;
  final Vector3? scale;

  /// Per-instance morph target weights overriding [GltfMesh.weights], or
  /// null when the node keeps the mesh defaults.
  final List<double>? weights;
}

/// The engine-side name for the glTF node at [index].
///
/// glTF lets nodes omit their name, and many real exports leave most
/// nodes unnamed. Animation channels resolve their target nodes by
/// name, so every unnamed node sharing the empty string would make all
/// channels collide on the same node. Synthesizing a unique,
/// index-derived name keeps channel binding correct. Both the offline
/// scene emitter and the runtime GLB importer must call this so a
/// model animates identically whichever path imported it.
///
/// Named nodes are returned unchanged. The synthetic `node_<index>`
/// form could in theory collide with an authored name; resolving that
/// fully would mean index- or path-based channel binding.
String resolveGltfNodeName(String? gltfName, int index) {
  if (gltfName != null && gltfName.isNotEmpty) return gltfName;
  return 'node_$index';
}

class GltfMesh {
  GltfMesh({
    this.name,
    this.primitives = const [],
    this.weights = const [],
    this.targetNames = const [],
  });
  final String? name;
  final List<GltfMeshPrimitive> primitives;

  /// Default morph target weights, or empty when the mesh declares none
  /// (all-zero defaults per spec).
  final List<double> weights;

  /// Morph target names from `extras.targetNames` (a common exporter
  /// convention), or empty when absent.
  final List<String> targetNames;
}

/// `KHR_draco_mesh_compression` data on a mesh primitive.
class GltfDracoCompression {
  GltfDracoCompression({required this.bufferView, required this.attributes});

  /// Buffer view holding the compressed Draco payload.
  final int bufferView;

  /// glTF attribute name to Draco unique attribute id.
  final Map<String, int> attributes;
}

class GltfMeshPrimitive {
  GltfMeshPrimitive({
    this.attributes = const {},
    this.indices,
    this.material,
    this.mode = 4,
    this.variantMappings = const {},
    this.draco,
    this.targets = const [],
  });

  /// Maps glTF attribute names ('POSITION', 'NORMAL', 'TEXCOORD_0',
  /// 'COLOR_0', 'JOINTS_0', 'WEIGHTS_0', 'TANGENT') to accessor indexes.
  final Map<String, int> attributes;
  final int? indices;
  final int? material;

  /// Primitive topology. 4 = TRIANGLES (the only mode flutter_scene supports).
  final int mode;

  /// `KHR_materials_variants` mappings, variant index (into
  /// [GltfDocument.materialsVariants]) to material index. Empty when the
  /// primitive declares no mappings; [material] stays the default.
  final Map<int, int> variantMappings;

  /// `KHR_draco_mesh_compression` data, or null when the primitive is not
  /// compressed. When present, the attribute and index accessors describe
  /// decoded output and their buffer views may be undefined.
  final GltfDracoCompression? draco;

  /// Morph targets, each mapping delta attribute names ('POSITION',
  /// 'NORMAL', 'TANGENT') to accessor indexes. Empty when unmorphed.
  final List<Map<String, int>> targets;
}

/// Validates that every triangle primitive of [mesh] declares the same
/// morph target count, the glTF invariant that lets one weight list drive
/// all of a mesh's primitives. Throws a [FormatException] on a mismatch.
void validateMorphTargetConsistency(GltfMesh mesh) {
  int? expected;
  for (final primitive in mesh.primitives) {
    if (primitive.mode != 4) continue;
    final count = primitive.targets.length;
    expected ??= count;
    if (count != expected) {
      throw FormatException(
        'glTF mesh "${mesh.name ?? ''}" has primitives with mismatched morph '
        'target counts ($expected vs $count); all primitives of a mesh must '
        'share the same targets',
      );
    }
  }
}

/// Component types from glTF spec section 5.1.1.
enum GltfComponentType {
  byte_(5120, 1, true),
  unsignedByte(5121, 1, false),
  short(5122, 2, true),
  unsignedShort(5123, 2, false),
  unsignedInt(5125, 4, false),
  float(5126, 4, true);

  const GltfComponentType(this.glValue, this.bytes, this.signed);
  final int glValue;
  final int bytes;
  final bool signed;

  static GltfComponentType fromGlValue(int v) {
    return values.firstWhere(
      (e) => e.glValue == v,
      orElse: () => throw FormatException('Unknown glTF componentType: $v'),
    );
  }
}

/// Accessor "type" enum from spec section 5.1.1.
enum GltfAccessorType {
  scalar('SCALAR', 1),
  vec2('VEC2', 2),
  vec3('VEC3', 3),
  vec4('VEC4', 4),
  mat2('MAT2', 4),
  mat3('MAT3', 9),
  mat4('MAT4', 16);

  const GltfAccessorType(this.name_, this.componentCount);
  final String name_;
  final int componentCount;

  static GltfAccessorType fromName(String s) {
    return values.firstWhere(
      (e) => e.name_ == s,
      orElse: () => throw FormatException('Unknown glTF accessor type: $s'),
    );
  }
}

class GltfAccessor {
  GltfAccessor({
    required this.componentType,
    required this.count,
    required this.type,
    this.bufferView,
    this.byteOffset = 0,
    this.normalized = false,
    this.min,
    this.max,
    this.sparse,
  });

  final GltfComponentType componentType;
  final int count;
  final GltfAccessorType type;

  /// Index into [GltfDocument.bufferViews], or null when the accessor has no
  /// dense storage (spec default: a zero-filled base, sparse-only data).
  final int? bufferView;
  final int byteOffset;
  final bool normalized;

  /// Componentwise min/max bounds, when supplied by the glTF asset. The
  /// spec requires these on POSITION accessors, so consumers can use them
  /// to skip a vertex scan when computing bounding volumes.
  final List<double>? min;
  final List<double>? max;

  /// Sparse storage overriding select elements of the base data, or null
  /// when the accessor is fully dense.
  final GltfAccessorSparse? sparse;
}

/// A glTF accessor's `sparse` object (spec section 5.1.1). Overrides
/// [count] elements of the accessor's base data with values named by
/// [indicesBufferView]/[valuesBufferView].
class GltfAccessorSparse {
  GltfAccessorSparse({
    required this.count,
    required this.indicesBufferView,
    this.indicesByteOffset = 0,
    required this.indicesComponentType,
    required this.valuesBufferView,
    this.valuesByteOffset = 0,
  });

  /// Number of overridden elements.
  final int count;

  /// Index into [GltfDocument.bufferViews] holding the element indices.
  final int indicesBufferView;
  final int indicesByteOffset;

  /// Component type of the indices (unsignedByte, unsignedShort, or
  /// unsignedInt per spec).
  final GltfComponentType indicesComponentType;

  /// Index into [GltfDocument.bufferViews] holding the override values, laid
  /// out like the accessor's own component type/count.
  final int valuesBufferView;
  final int valuesByteOffset;
}

class GltfBufferView {
  GltfBufferView({
    required this.buffer,
    required this.byteLength,
    this.byteOffset = 0,
    this.byteStride,
    this.meshopt,
  });

  final int buffer;
  final int byteLength;
  final int byteOffset;
  final int? byteStride;

  /// Set when the view's data is stored compressed by the
  /// `EXT_meshopt_compression` extension. [buffer], [byteOffset] and
  /// [byteLength] then describe the uncompressed fallback storage, which the
  /// decoding path never reads.
  final GltfMeshoptCompression? meshopt;
}

/// The `EXT_meshopt_compression` extension object on a buffer view, locating
/// and describing the compressed source data.
class GltfMeshoptCompression {
  GltfMeshoptCompression({
    required this.buffer,
    required this.byteLength,
    required this.byteStride,
    required this.count,
    required this.mode,
    this.byteOffset = 0,
    this.filter = 'NONE',
  });

  final int buffer;
  final int byteOffset;
  final int byteLength;

  /// Size of one decoded element. Not the same thing as the view's
  /// [GltfBufferView.byteStride], which stays absent for index data.
  final int byteStride;
  final int count;

  /// `ATTRIBUTES`, `TRIANGLES`, or `INDICES`. Kept as written so the decoder
  /// reports an unknown value instead of the parser guessing one.
  final String mode;

  /// `NONE`, `OCTAHEDRAL`, `QUATERNION`, or `EXPONENTIAL`.
  final String filter;

  /// Size of the decoded data.
  int get decodedByteLength => count * byteStride;

  GltfMeshoptCompression rebased({
    required int buffer,
    required int byteOffset,
  }) {
    return GltfMeshoptCompression(
      buffer: buffer,
      byteOffset: byteOffset,
      byteLength: byteLength,
      byteStride: byteStride,
      count: count,
      mode: mode,
      filter: filter,
    );
  }
}

class GltfBuffer {
  GltfBuffer({
    required this.byteLength,
    this.uri,
    this.meshoptFallback = false,
  });
  final int byteLength;
  final String? uri;

  /// Whether the buffer is tagged as an `EXT_meshopt_compression` fallback.
  /// Only compressed views may reference it, so the decoding path never loads
  /// it.
  final bool meshoptFallback;
}

class GltfMaterial {
  GltfMaterial({
    this.name,
    this.pbrMetallicRoughness,
    this.normalTexture,
    this.occlusionTexture,
    this.emissiveTexture,
    this.emissiveFactor = const [0.0, 0.0, 0.0],
    this.alphaMode = 'OPAQUE',
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.unlit = false,
    this.anisotropy,
    this.clearcoat,
    this.diffuseTransmission,
    this.dispersion = 0.0,
    this.emissiveStrength = 1.0,
    this.ior = 1.5,
    this.iridescence,
    this.sheen,
    this.specular,
    this.transmission,
    this.volume,
  });

  final String? name;
  final GltfPbrMetallicRoughness? pbrMetallicRoughness;
  final GltfTextureInfo? normalTexture;
  final GltfTextureInfo? occlusionTexture;
  final GltfTextureInfo? emissiveTexture;
  final List<double> emissiveFactor;
  final String alphaMode;
  final double alphaCutoff;
  final bool doubleSided;
  final bool unlit;
  final GltfMaterialAnisotropy? anisotropy;
  final GltfMaterialClearcoat? clearcoat;
  final GltfMaterialDiffuseTransmission? diffuseTransmission;
  final double dispersion;
  final double emissiveStrength;
  final double ior;
  final GltfMaterialIridescence? iridescence;
  final GltfMaterialSheen? sheen;
  final GltfMaterialSpecular? specular;
  final GltfMaterialTransmission? transmission;
  final GltfMaterialVolume? volume;

  bool get requiresPhysicalMaterial =>
      anisotropy != null ||
      clearcoat != null ||
      diffuseTransmission != null ||
      dispersion != 0.0 ||
      ior != 1.5 ||
      iridescence != null ||
      sheen != null ||
      specular != null ||
      transmission != null ||
      volume != null;
}

class GltfMaterialAnisotropy {
  GltfMaterialAnisotropy({
    this.strength = 0.0,
    this.rotation = 0.0,
    this.texture,
  });

  final double strength;
  final double rotation;
  final GltfTextureInfo? texture;
}

class GltfMaterialClearcoat {
  GltfMaterialClearcoat({
    this.factor = 0.0,
    this.texture,
    this.roughnessFactor = 0.0,
    this.roughnessTexture,
    this.normalTexture,
  });

  final double factor;
  final GltfTextureInfo? texture;
  final double roughnessFactor;
  final GltfTextureInfo? roughnessTexture;
  final GltfTextureInfo? normalTexture;
}

class GltfMaterialDiffuseTransmission {
  GltfMaterialDiffuseTransmission({
    this.factor = 0.0,
    this.texture,
    this.colorFactor = const [1.0, 1.0, 1.0],
    this.colorTexture,
  });

  final double factor;
  final GltfTextureInfo? texture;
  final List<double> colorFactor;
  final GltfTextureInfo? colorTexture;
}

class GltfMaterialIridescence {
  GltfMaterialIridescence({
    this.factor = 0.0,
    this.texture,
    this.ior = 1.3,
    this.thicknessMinimum = 100.0,
    this.thicknessMaximum = 400.0,
    this.thicknessTexture,
  });

  final double factor;
  final GltfTextureInfo? texture;
  final double ior;
  final double thicknessMinimum;
  final double thicknessMaximum;
  final GltfTextureInfo? thicknessTexture;
}

class GltfMaterialSheen {
  GltfMaterialSheen({
    this.colorFactor = const [0.0, 0.0, 0.0],
    this.colorTexture,
    this.roughnessFactor = 0.0,
    this.roughnessTexture,
  });

  final List<double> colorFactor;
  final GltfTextureInfo? colorTexture;
  final double roughnessFactor;
  final GltfTextureInfo? roughnessTexture;
}

class GltfMaterialSpecular {
  GltfMaterialSpecular({
    this.factor = 1.0,
    this.texture,
    this.colorFactor = const [1.0, 1.0, 1.0],
    this.colorTexture,
  });

  final double factor;
  final GltfTextureInfo? texture;
  final List<double> colorFactor;
  final GltfTextureInfo? colorTexture;
}

class GltfMaterialTransmission {
  GltfMaterialTransmission({this.factor = 0.0, this.texture});

  final double factor;
  final GltfTextureInfo? texture;
}

class GltfMaterialVolume {
  GltfMaterialVolume({
    this.thicknessFactor = 0.0,
    this.thicknessTexture,
    this.attenuationDistance = double.infinity,
    this.attenuationColor = const [1.0, 1.0, 1.0],
  });

  final double thicknessFactor;
  final GltfTextureInfo? thicknessTexture;
  final double attenuationDistance;
  final List<double> attenuationColor;
}

class GltfPbrMetallicRoughness {
  GltfPbrMetallicRoughness({
    this.baseColorFactor = const [1.0, 1.0, 1.0, 1.0],
    this.baseColorTexture,
    this.metallicFactor = 1.0,
    this.roughnessFactor = 1.0,
    this.metallicRoughnessTexture,
  });

  final List<double> baseColorFactor;
  final GltfTextureInfo? baseColorTexture;
  final double metallicFactor;
  final double roughnessFactor;
  final GltfTextureInfo? metallicRoughnessTexture;
}

class GltfTextureInfo {
  GltfTextureInfo({
    required this.index,
    this.texCoord = 0,
    this.scale,
    this.strength,
    this.transform,
  });
  final int index;
  final int texCoord;

  /// Set on normal textures (otherwise null).
  final double? scale;

  /// Set on occlusion textures (otherwise null).
  final double? strength;

  final GltfTextureTransform? transform;
}

class GltfTextureTransform {
  GltfTextureTransform({
    this.offset = const [0.0, 0.0],
    this.rotation = 0.0,
    this.scale = const [1.0, 1.0],
    this.texCoord,
  });

  final List<double> offset;
  final double rotation;
  final List<double> scale;
  final int? texCoord;
}

class GltfTexture {
  GltfTexture({this.source, this.sampler, this.basisuSource});
  final int? source;
  final int? sampler;

  /// KHR_texture_basisu image index (a KTX2 image), preferred over [source]
  /// when present.
  final int? basisuSource;
}

class GltfImage {
  GltfImage({this.uri, this.bufferView, this.mimeType});
  final String? uri;
  final int? bufferView;
  final String? mimeType;
}

class GltfSampler {
  GltfSampler({
    this.magFilter,
    this.minFilter,
    this.wrapS = 10497,
    this.wrapT = 10497,
  });
  final int? magFilter;
  final int? minFilter;
  final int wrapS;
  final int wrapT;
}

class GltfSkin {
  GltfSkin({
    this.name,
    this.inverseBindMatrices,
    this.skeleton,
    this.joints = const [],
  });
  final String? name;
  final int? inverseBindMatrices;
  final int? skeleton;
  final List<int> joints;
}

class GltfAnimation {
  GltfAnimation({
    this.name,
    this.channels = const [],
    this.samplers = const [],
  });
  final String? name;
  final List<GltfAnimationChannel> channels;
  final List<GltfAnimationSampler> samplers;
}

class GltfAnimationChannel {
  GltfAnimationChannel({
    required this.sampler,
    required this.targetNode,
    required this.targetPath,
  });
  final int sampler;
  final int? targetNode;

  /// One of 'translation', 'rotation', 'scale', 'weights'.
  final String targetPath;
}

class GltfAnimationSampler {
  GltfAnimationSampler({
    required this.input,
    required this.output,
    this.interpolation = 'LINEAR',
  });
  final int input;
  final int output;
  final String interpolation;
}
