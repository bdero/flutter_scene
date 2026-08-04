import '../texture/mipmap.dart';
import 'src/gltf/types.dart';

/// Derives each glTF texture's mip-downsampling role from its material slots.
List<TextureContent> gltfTextureContents(GltfDocument doc) {
  const priority = {
    TextureContent.data: 0,
    TextureContent.color: 1,
    TextureContent.normal: 2,
  };
  final contents = List<TextureContent>.filled(
    doc.textures.length,
    TextureContent.color,
  );
  final marked = List<bool>.filled(doc.textures.length, false);

  void mark(GltfTextureInfo? info, TextureContent content) {
    final index = info?.index;
    if (index == null || index < 0 || index >= contents.length) return;
    if (marked[index] && priority[contents[index]]! >= priority[content]!) {
      return;
    }
    marked[index] = true;
    contents[index] = content;
  }

  for (final material in doc.materials) {
    final pbr = material.pbrMetallicRoughness;
    mark(pbr?.baseColorTexture, TextureContent.color);
    mark(material.emissiveTexture, TextureContent.color);
    mark(material.normalTexture, TextureContent.normal);
    mark(pbr?.metallicRoughnessTexture, TextureContent.data);
    mark(material.occlusionTexture, TextureContent.data);
    mark(material.anisotropy?.texture, TextureContent.data);
    mark(material.clearcoat?.texture, TextureContent.data);
    mark(material.clearcoat?.roughnessTexture, TextureContent.data);
    mark(material.clearcoat?.normalTexture, TextureContent.normal);
    mark(material.diffuseTransmission?.texture, TextureContent.data);
    mark(material.diffuseTransmission?.colorTexture, TextureContent.color);
    mark(material.iridescence?.texture, TextureContent.data);
    mark(material.iridescence?.thicknessTexture, TextureContent.data);
    mark(material.sheen?.colorTexture, TextureContent.color);
    mark(material.sheen?.roughnessTexture, TextureContent.data);
    mark(material.specular?.texture, TextureContent.data);
    mark(material.specular?.colorTexture, TextureContent.color);
    mark(material.transmission?.texture, TextureContent.data);
    mark(material.volume?.thicknessTexture, TextureContent.data);
  }
  return contents;
}
