#include "importer.h"

#include <array>
#include <cstring>
#include <functional>
#include <iostream>
#include <iterator>
#include <memory>
#include <vector>

#include "tiny_gltf.h"

#include "conversions.h"
#include "generated/scene_flatbuffers.h"
#include "vertices_builder.h"

namespace impeller {
namespace scene {
namespace importer {

static const std::map<std::string, VerticesBuilder::AttributeType> kAttributes =
    {{"POSITION", VerticesBuilder::AttributeType::kPosition},
     {"NORMAL", VerticesBuilder::AttributeType::kNormal},
     {"TEXCOORD_0", VerticesBuilder::AttributeType::kTextureCoords},
     {"COLOR_0", VerticesBuilder::AttributeType::kColor},
     {"JOINTS_0", VerticesBuilder::AttributeType::kJoints},
     {"WEIGHTS_0", VerticesBuilder::AttributeType::kWeights}};

static bool WithinRange(int index, size_t size) {
  return index >= 0 && static_cast<size_t>(index) < size;
}

static bool MeshPrimitiveIsSkinned(const tinygltf::Primitive& primitive) {
  return primitive.attributes.find("JOINTS_0") != primitive.attributes.end() &&
         primitive.attributes.find("WEIGHTS_0") != primitive.attributes.end();
}

template <typename T>
static int32_t ResolveMaterialTexture(const tinygltf::Model& gltf,
                                      const T& texture) {
  bool is_valid = texture.texCoord == 0 && texture.index >= 0 &&
                  texture.index < static_cast<int32_t>(gltf.textures.size());
  return is_valid ? texture.index : -1;
}

static void ProcessMaterial(const tinygltf::Model& gltf,
                            const tinygltf::Material& in_material,
                            fb::MaterialT& out_material) {
  /*
  out_material.type = fb::MaterialType::kUnlit;
  out_material.base_color_factor =
      ToFBColor(in_material.pbrMetallicRoughness.baseColorFactor);
  bool base_color_texture_valid =
      in_material.pbrMetallicRoughness.baseColorTexture.texCoord == 0 &&
      in_material.pbrMetallicRoughness.baseColorTexture.index >= 0 &&
      in_material.pbrMetallicRoughness.baseColorTexture.index <
          static_cast<int32_t>(gltf.textures.size());
  out_material.base_color_texture =
      base_color_texture_valid
          // This is safe because every GLTF input texture is mapped to a
          // `Scene->texture`.
          ? in_material.pbrMetallicRoughness.baseColorTexture.index
          : -1;
  */
  out_material.type = fb::MaterialType::kPhysicallyBased;
  out_material.base_color_factor =
      ToFBColor(in_material.pbrMetallicRoughness.baseColorFactor);
  out_material.metallic_factor =
      in_material.pbrMetallicRoughness.metallicFactor;
  out_material.roughness_factor =
      in_material.pbrMetallicRoughness.roughnessFactor;
  out_material.normal_scale = in_material.normalTexture.scale;
  out_material.emissive_factor = ToFBColor3(in_material.emissiveFactor);

  out_material.base_color_texture = ResolveMaterialTexture(
      gltf, in_material.pbrMetallicRoughness.baseColorTexture);
  out_material.metallic_roughness_texture = ResolveMaterialTexture(
      gltf, in_material.pbrMetallicRoughness.metallicRoughnessTexture);
  out_material.normal_texture =
      ResolveMaterialTexture(gltf, in_material.normalTexture);
  out_material.emissive_texture =
      ResolveMaterialTexture(gltf, in_material.emissiveTexture);
  out_material.occlusion_texture = ResolveMaterialTexture(
      gltf, in_material.occlusionTexture);
}

static bool ProcessMeshPrimitive(const tinygltf::Model& gltf,
                                 const tinygltf::Primitive& primitive,
                                 fb::MeshPrimitiveT& mesh_primitive) {
  //---------------------------------------------------------------------------
  /// Vertices.
  ///

  {
    bool is_skinned = MeshPrimitiveIsSkinned(primitive);
    std::unique_ptr<VerticesBuilder> builder =
        is_skinned ? VerticesBuilder::MakeSkinned()
                   : VerticesBuilder::MakeUnskinned();

    for (const auto& attribute : primitive.attributes) {
      auto attribute_type = kAttributes.find(attribute.first);
      if (attribute_type == kAttributes.end()) {
        std::cerr << "Vertex attribute \"" << attribute.first
                  << "\" not supported." << std::endl;
        continue;
      }
      if (!is_skinned &&
          (attribute_type->second == VerticesBuilder::AttributeType::kJoints ||
           attribute_type->second ==
               VerticesBuilder::AttributeType::kWeights)) {
        // If the primitive doesn't have enough information to be skinned, skip
        // skinning-related attributes.
        continue;
      }

      const auto& accessor = gltf.accessors[attribute.second];
      const auto& view = gltf.bufferViews[accessor.bufferView];

      const auto& buffer = gltf.buffers[view.buffer];
      const unsigned char* source_start = &buffer.data[view.byteOffset];

      VerticesBuilder::ComponentType type;
      switch (accessor.componentType) {
        case TINYGLTF_COMPONENT_TYPE_BYTE:
          type = VerticesBuilder::ComponentType::kSignedByte;
          break;
        case TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE:
          type = VerticesBuilder::ComponentType::kUnsignedByte;
          break;
        case TINYGLTF_COMPONENT_TYPE_SHORT:
          type = VerticesBuilder::ComponentType::kSignedShort;
          break;
        case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
          type = VerticesBuilder::ComponentType::kUnsignedShort;
          break;
        case TINYGLTF_COMPONENT_TYPE_INT:
          type = VerticesBuilder::ComponentType::kSignedInt;
          break;
        case TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT:
          type = VerticesBuilder::ComponentType::kUnsignedInt;
          break;
        case TINYGLTF_COMPONENT_TYPE_FLOAT:
          type = VerticesBuilder::ComponentType::kFloat;
          break;
        default:
          std::cerr << "Skipping attribute \"" << attribute.first
                    << "\" due to invalid component type." << std::endl;
          continue;
      }

      builder->SetAttributeFromBuffer(
          attribute_type->second,     // attribute
          type,                       // component_type
          source_start,               // buffer_start
          accessor.ByteStride(view),  // stride_bytes
          accessor.count);            // count
    }

    builder->WriteFBVertices(mesh_primitive);
  }

  //---------------------------------------------------------------------------
  /// Indices.
  ///

  {
    if (!WithinRange(primitive.indices, gltf.accessors.size())) {
      std::cerr << "Mesh primitive has no index buffer. Skipping." << std::endl;
      return false;
    }

    auto index_accessor = gltf.accessors[primitive.indices];
    auto index_view = gltf.bufferViews[index_accessor.bufferView];

    auto indices = std::make_unique<fb::IndicesT>();

    switch (index_accessor.componentType) {
      case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
        indices->type = fb::IndexType::k16Bit;
        break;
      case TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT:
        indices->type = fb::IndexType::k32Bit;
        break;
      default:
        std::cerr << "Mesh primitive has unsupported index type "
                  << index_accessor.componentType << ". Skipping.";
        return false;
    }
    indices->count = index_accessor.count;
    indices->data.resize(index_view.byteLength);
    const auto* index_buffer =
        &gltf.buffers[index_view.buffer].data[index_view.byteOffset];
    std::memcpy(indices->data.data(), index_buffer, indices->data.size());

    mesh_primitive.indices = std::move(indices);
  }

  //---------------------------------------------------------------------------
  /// Material.
  ///

  {
    auto material = std::make_unique<fb::MaterialT>();
    if (primitive.material >= 0 &&
        primitive.material < static_cast<int>(gltf.materials.size())) {
      ProcessMaterial(gltf, gltf.materials[primitive.material], *material);
    } else {
      material->type = fb::MaterialType::kUnlit;
    }
    mesh_primitive.material = std::move(material);
  }

  return true;
}

static void ProcessNode(const tinygltf::Model& gltf,
                        const tinygltf::Node& in_node,
                        fb::NodeT& out_node) {
  out_node.name = in_node.name;
  out_node.children = in_node.children;

  //---------------------------------------------------------------------------
  /// Transform.
  ///

  Matrix transform;
  if (in_node.scale.size() == 3) {
    transform = Matrix::MakeScale({static_cast<Scalar>(in_node.scale[0]),
                                   static_cast<Scalar>(in_node.scale[1]),
                                   static_cast<Scalar>(in_node.scale[2])}) *
                transform;
  } else if (in_node.scale.size() != 0) {
    std::cerr << "Unhandled scale size: " << in_node.scale.size() << std::endl;
  }
  if (in_node.rotation.size() == 4) {
    transform = Matrix::MakeRotation(
                    Quaternion{static_cast<Scalar>(in_node.rotation[0]),
                               static_cast<Scalar>(in_node.rotation[1]),
                               static_cast<Scalar>(in_node.rotation[2]),
                               static_cast<Scalar>(in_node.rotation[3])}) *
                transform;
  } else if (in_node.rotation.size() != 0) {
    std::cerr << "Unhandled rotation size: " << in_node.rotation.size()
              << std::endl;
  }
  if (in_node.translation.size() == 3) {
    transform =
        Matrix::MakeTranslation({static_cast<Scalar>(in_node.translation[0]),
                                 static_cast<Scalar>(in_node.translation[1]),
                                 static_cast<Scalar>(in_node.translation[2])}) *
        transform;
  } else if (in_node.translation.size() != 0) {
    std::cerr << "Unhandled translation size: " << in_node.translation.size()
              << std::endl;
  }
  if (in_node.matrix.size() == 16) {
    if (!transform.IsIdentity()) {
      std::cerr << "The `matrix` attribute of node (name: " << in_node.name
                << ") is set in addition to one or more of the "
                   "`translation/rotation/scale` attributes. Using only the "
                   "`matrix` attribute.";
    }
    transform = ToMatrix(in_node.matrix);
  }
  out_node.transform = ToFBMatrixUniquePtr(transform);

  //---------------------------------------------------------------------------
  /// Static meshes.
  ///

  if (WithinRange(in_node.mesh, gltf.meshes.size())) {
    auto& mesh = gltf.meshes[in_node.mesh];
    for (const auto& primitive : mesh.primitives) {
      auto mesh_primitive = std::make_unique<fb::MeshPrimitiveT>();
      if (!ProcessMeshPrimitive(gltf, primitive, *mesh_primitive)) {
        continue;
      }
      out_node.mesh_primitives.push_back(std::move(mesh_primitive));
    }
  }

  //---------------------------------------------------------------------------
  /// Skin.
  ///

  if (WithinRange(in_node.skin, gltf.skins.size())) {
    auto& skin = gltf.skins[in_node.skin];

    auto ipskin = std::make_unique<fb::SkinT>();
    ipskin->joints = skin.joints;
    {
      std::vector<fb::Matrix> matrices;
      auto& matrix_accessor = gltf.accessors[skin.inverseBindMatrices];
      auto& matrix_view = gltf.bufferViews[matrix_accessor.bufferView];
      auto& matrix_buffer = gltf.buffers[matrix_view.buffer];
      for (size_t matrix_i = 0; matrix_i < matrix_accessor.count; matrix_i++) {
        auto* s = reinterpret_cast<const float*>(
            matrix_buffer.data.data() + matrix_view.byteOffset +
            matrix_accessor.ByteStride(matrix_view) * matrix_i);
        Matrix m{s[0],  s[1],  s[2],  s[3],   //
                 s[4],  s[5],  s[6],  s[7],   //
                 s[8],  s[9],  s[10], s[11],  //
                 s[12], s[13], s[14], s[15]};
        matrices.push_back(ToFBMatrix(m));
      }
      ipskin->inverse_bind_matrices = std::move(matrices);
    }
    ipskin->skeleton = skin.skeleton;
    out_node.skin = std::move(ipskin);
  }
}

static void ProcessTexture(const tinygltf::Model& gltf,
                           const tinygltf::Texture& in_texture,
                           fb::TextureT& out_texture) {
  if (!WithinRange(in_texture.source, gltf.images.size())) {
    return;
  }
  auto& image = gltf.images[in_texture.source];

  auto embedded = std::make_unique<fb::EmbeddedImageT>();
  embedded->bytes = image.image;
  size_t bytes_per_component = 0;
  switch (image.pixel_type) {
    case TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE:
      embedded->component_type = fb::ComponentType::k8Bit;
      bytes_per_component = 1;
      break;
    case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
      embedded->component_type = fb::ComponentType::k16Bit;
      bytes_per_component = 2;
      break;
    default:
      std::cerr << "Texture component type " << image.pixel_type
                << " not supported." << std::endl;
      return;
  }
  if (image.image.size() !=
      bytes_per_component * image.component * image.width * image.height) {
    std::cerr << "Decompressed texture had unexpected buffer size. Skipping."
              << std::endl;
    return;
  }
  embedded->component_count = image.component;
  embedded->width = image.width;
  embedded->height = image.height;
  out_texture.embedded_image = std::move(embedded);
  out_texture.uri = image.uri;
}

static void ProcessAnimation(const tinygltf::Model& gltf,
                             const tinygltf::Animation& in_animation,
                             fb::AnimationT& out_animation) {
  out_animation.name = in_animation.name;

  // std::vector<impeller::fb::ChannelT> channels;
  std::vector<impeller::fb::ChannelT> translation_channels;
  std::vector<impeller::fb::ChannelT> rotation_channels;
  std::vector<impeller::fb::ChannelT> scale_channels;
  for (auto& in_channel : in_animation.channels) {
    auto out_channel = fb::ChannelT();

    out_channel.node = in_channel.target_node;
    auto& sampler = in_animation.samplers[in_channel.sampler];

    /// Keyframe times.
    auto& times_accessor = gltf.accessors[sampler.input];
    if (times_accessor.count <= 0) {
      continue;  // Nothing to record.
    }
    {
      auto& times_bufferview = gltf.bufferViews[times_accessor.bufferView];
      auto& times_buffer = gltf.buffers[times_bufferview.buffer];
      if (times_accessor.componentType != TINYGLTF_COMPONENT_TYPE_FLOAT) {
        std::cerr << "Unexpected component type \""
                  << times_accessor.componentType
                  << "\" for animation channel times accessor. Skipping."
                  << std::endl;
        continue;
      }
      if (times_accessor.type != TINYGLTF_TYPE_SCALAR) {
        std::cerr << "Unexpected type \"" << times_accessor.type
                  << "\" for animation channel times accessor. Skipping."
                  << std::endl;
        continue;
      }
      for (size_t time_i = 0; time_i < times_accessor.count; time_i++) {
        const float* time_p = reinterpret_cast<const float*>(
            times_buffer.data.data() + times_bufferview.byteOffset +
            times_accessor.ByteStride(times_bufferview) * time_i);
        out_channel.timeline.push_back(*time_p);
      }
    }

    /// Keyframe values.
    auto& values_accessor = gltf.accessors[sampler.output];
    if (values_accessor.count != times_accessor.count) {
      std::cerr << "Mismatch between time and value accessors for animation "
                   "channel. Skipping."
                << std::endl;
      continue;
    }
    {
      auto& values_bufferview = gltf.bufferViews[values_accessor.bufferView];
      auto& values_buffer = gltf.buffers[values_bufferview.buffer];
      if (values_accessor.componentType != TINYGLTF_COMPONENT_TYPE_FLOAT) {
        std::cerr << "Unexpected component type \""
                  << values_accessor.componentType
                  << "\" for animation channel values accessor. Skipping."
                  << std::endl;
        continue;
      }
      if (in_channel.target_path == "translation") {
        if (values_accessor.type != TINYGLTF_TYPE_VEC3) {
          std::cerr << "Unexpected type \"" << values_accessor.type
                    << "\" for animation channel \"translation\" accessor. "
                       "Skipping."
                    << std::endl;
          continue;
        }
        fb::TranslationKeyframesT keyframes;
        for (size_t value_i = 0; value_i < values_accessor.count; value_i++) {
          const float* value_p = reinterpret_cast<const float*>(
              values_buffer.data.data() + values_bufferview.byteOffset +
              values_accessor.ByteStride(values_bufferview) * value_i);
          keyframes.values.push_back(
              fb::Vec3(value_p[0], value_p[1], value_p[2]));
        }
        out_channel.keyframes.Set(std::move(keyframes));
        translation_channels.push_back(std::move(out_channel));
      } else if (in_channel.target_path == "rotation") {
        if (values_accessor.type != TINYGLTF_TYPE_VEC4) {
          std::cerr << "Unexpected type \"" << values_accessor.type
                    << "\" for animation channel \"rotation\" accessor. "
                       "Skipping."
                    << std::endl;
          continue;
        }
        fb::RotationKeyframesT keyframes;
        for (size_t value_i = 0; value_i < values_accessor.count; value_i++) {
          const float* value_p = reinterpret_cast<const float*>(
              values_buffer.data.data() + values_bufferview.byteOffset +
              values_accessor.ByteStride(values_bufferview) * value_i);
          keyframes.values.push_back(
              fb::Vec4(value_p[0], value_p[1], value_p[2], value_p[3]));
        }
        out_channel.keyframes.Set(std::move(keyframes));
        rotation_channels.push_back(std::move(out_channel));
      } else if (in_channel.target_path == "scale") {
        if (values_accessor.type != TINYGLTF_TYPE_VEC3) {
          std::cerr << "Unexpected type \"" << values_accessor.type
                    << "\" for animation channel \"scale\" accessor. "
                       "Skipping."
                    << std::endl;
          continue;
        }
        fb::ScaleKeyframesT keyframes;
        for (size_t value_i = 0; value_i < values_accessor.count; value_i++) {
          const float* value_p = reinterpret_cast<const float*>(
              values_buffer.data.data() + values_bufferview.byteOffset +
              values_accessor.ByteStride(values_bufferview) * value_i);
          keyframes.values.push_back(
              fb::Vec3(value_p[0], value_p[1], value_p[2]));
        }
        out_channel.keyframes.Set(std::move(keyframes));
        scale_channels.push_back(std::move(out_channel));
      } else {
        std::cerr << "Unsupported animation channel target path \""
                  << in_channel.target_path << "\". Skipping." << std::endl;
        continue;
      }
    }
  }

  std::vector<std::unique_ptr<impeller::fb::ChannelT>> channels;
  for (const auto& channel_list :
       {translation_channels, rotation_channels, scale_channels}) {
    for (const auto& channel : channel_list) {
      channels.push_back(std::make_unique<fb::ChannelT>(channel));
    }
  }
  out_animation.channels = std::move(channels);
}

bool ParseGLTF(const std::vector<char>& input_bytes, fb::SceneT& out_scene) {
  tinygltf::Model gltf;

  {
    tinygltf::TinyGLTF loader;
    std::string error;
    std::string warning;
    bool success = loader.LoadBinaryFromMemory(
        &gltf, &error, &warning,
        reinterpret_cast<const unsigned char*>(input_bytes.data()),
        input_bytes.size());
    if (!warning.empty()) {
      std::cerr << "Warning while loading GLTF: " << warning << std::endl;
    }
    if (!error.empty()) {
      std::cerr << "Error while loading GLTF: " << error << std::endl;
    }
    if (!success) {
      return false;
    }
  }

  const tinygltf::Scene& scene = gltf.scenes[gltf.defaultScene];
  out_scene.children = scene.nodes;

  out_scene.transform =
      ToFBMatrixUniquePtr(Matrix::MakeScale(Vector3{1, 1, -1}));

  std::cerr << "Processing " << gltf.textures.size() << " texture"
            << (gltf.textures.size() == 1 ? "" : "s") << "..." << std::endl;
  for (size_t texture_i = 0; texture_i < gltf.textures.size(); texture_i++) {
    auto texture = std::make_unique<fb::TextureT>();
    ProcessTexture(gltf, gltf.textures[texture_i], *texture);
    out_scene.textures.push_back(std::move(texture));
  }

  std::cerr << "Processing " << gltf.nodes.size() << " node"
            << (gltf.nodes.size() == 1 ? "" : "s") << "..." << std::endl;
  for (size_t node_i = 0; node_i < gltf.nodes.size(); node_i++) {
    auto node = std::make_unique<fb::NodeT>();
    // std::cerr << "Processing node " << node_i << " of " << gltf.nodes.size()
    //           << ": " << gltf.nodes[node_i].name << std::endl;
    ProcessNode(gltf, gltf.nodes[node_i], *node);
    out_scene.nodes.push_back(std::move(node));
  }

  for (size_t animation_i = 0; animation_i < gltf.animations.size();
       animation_i++) {
    auto animation = std::make_unique<fb::AnimationT>();
    ProcessAnimation(gltf, gltf.animations[animation_i], *animation);
    out_scene.animations.push_back(std::move(animation));
  }

  return true;
}

}  // namespace importer
}  // namespace scene
}  // namespace impeller
