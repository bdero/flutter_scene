import 'package:vector_math/vector_math.dart';

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
}

class GltfScene {
  GltfScene({this.name, this.nodes = const []});
  final String? name;
  final List<int> nodes;
}

class GltfNode {
  GltfNode({
    this.name,
    this.mesh,
    this.skin,
    this.children = const [],
    this.matrix,
    this.translation,
    this.rotation,
    this.scale,
  });

  final String? name;
  final int? mesh;
  final int? skin;
  final List<int> children;

  /// If [matrix] is set, [translation]/[rotation]/[scale] are ignored.
  final Matrix4? matrix;
  final Vector3? translation;
  final Quaternion? rotation;
  final Vector3? scale;
}

class GltfMesh {
  GltfMesh({this.name, this.primitives = const []});
  final String? name;
  final List<GltfMeshPrimitive> primitives;
}

class GltfMeshPrimitive {
  GltfMeshPrimitive({
    this.attributes = const {},
    this.indices,
    this.material,
    this.mode = 4,
  });

  /// Maps glTF attribute names ('POSITION', 'NORMAL', 'TEXCOORD_0',
  /// 'COLOR_0', 'JOINTS_0', 'WEIGHTS_0', 'TANGENT') to accessor indexes.
  final Map<String, int> attributes;
  final int? indices;
  final int? material;

  /// Primitive topology. 4 = TRIANGLES (the only mode flutter_scene supports).
  final int mode;
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
  });

  final GltfComponentType componentType;
  final int count;
  final GltfAccessorType type;
  final int? bufferView;
  final int byteOffset;
  final bool normalized;
}

class GltfBufferView {
  GltfBufferView({
    required this.buffer,
    required this.byteLength,
    this.byteOffset = 0,
    this.byteStride,
  });

  final int buffer;
  final int byteLength;
  final int byteOffset;
  final int? byteStride;
}

class GltfBuffer {
  GltfBuffer({required this.byteLength, this.uri});
  final int byteLength;
  final String? uri;
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
  });
  final int index;
  final int texCoord;

  /// Set on normal textures (otherwise null).
  final double? scale;

  /// Set on occlusion textures (otherwise null).
  final double? strength;
}

class GltfTexture {
  GltfTexture({this.source, this.sampler});
  final int? source;
  final int? sampler;
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
