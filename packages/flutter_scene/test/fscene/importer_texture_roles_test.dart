// Covers the roles the glTF importer records on its texture resources, and the
// warning when a source image is too small-grained to stay compressed. The
// realizer downsamples mips by the recorded role, so a normal map that lands as
// `color` averages wrong.

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_scene/src/importer/src/gltf/types.dart';
import 'package:flutter_test/flutter_test.dart';

// A PNG of [size] x [size] mid-gray pixels, embedded as a glTF image.
Uint8List _png(int size) => Uint8List.fromList(
  img.encodePng(img.Image(width: size, height: size, numChannels: 4)),
);

// A glTF document with one image per entry of [sizes], each wired to its own
// texture, plus [material] assigning those textures to slots by index.
({GltfDocument doc, Uint8List buffer}) _document({
  required List<int> sizes,
  required GltfMaterial material,
}) {
  final views = <GltfBufferView>[];
  final bytes = BytesBuilder();
  for (final size in sizes) {
    final png = _png(size);
    views.add(
      GltfBufferView(
        buffer: 0,
        byteOffset: bytes.length,
        byteLength: png.length,
      ),
    );
    bytes.add(png);
  }
  return (
    doc: GltfDocument(
      bufferViews: views,
      images: [
        for (var i = 0; i < sizes.length; i++)
          GltfImage(bufferView: i, mimeType: 'image/png'),
      ],
      textures: [for (var i = 0; i < sizes.length; i++) GltfTexture(source: i)],
      materials: [material],
    ),
    buffer: bytes.toBytes(),
  );
}

List<String> _textureContents(SceneDocument document) => [
  for (final resource in document.resources.values)
    if (resource is TextureResource) resource.content,
];

void main() {
  test('records the material slot role on each texture resource', () {
    final built = _document(
      sizes: [4, 4, 4],
      material: GltfMaterial(
        pbrMetallicRoughness: GltfPbrMetallicRoughness(
          baseColorTexture: GltfTextureInfo(index: 0),
          metallicRoughnessTexture: GltfTextureInfo(index: 1),
        ),
        normalTexture: GltfTextureInfo(index: 2),
      ),
    );

    final document = buildSceneDocument(built.doc, built.buffer);
    expect(_textureContents(document), ['color', 'data', 'normal']);
  });

  test('records roles on compressed textures too', () {
    final built = _document(
      sizes: [4],
      material: GltfMaterial(normalTexture: GltfTextureInfo(index: 0)),
    );

    final document = buildSceneDocument(
      built.doc,
      built.buffer,
      compressTextures: true,
    );
    expect(_textureContents(document), ['normal']);
  });

  test('warns when a texture is not block aligned to stay compressed', () {
    final built = _document(
      sizes: [6],
      material: GltfMaterial(
        pbrMetallicRoughness: GltfPbrMetallicRoughness(
          baseColorTexture: GltfTextureInfo(index: 0),
        ),
      ),
    );

    final logged = <String>[];
    final previous = sceneLog;
    sceneLog = logged.add;
    final SceneDocument document;
    try {
      document = buildSceneDocument(
        built.doc,
        built.buffer,
        compressTextures: true,
      );
    } finally {
      sceneLog = previous;
    }

    expect(logged, hasLength(1));
    expect(logged.single, contains('6x6'));
    // The fallback is uncompressed, and the realizer builds its mips.
    expect(
      [
        for (final payload in document.payloads.values)
          if (payload.encoding == PayloadEncoding.image) payload.format,
      ],
      ['rgba8'],
    );
  });

  test('stays quiet when the source is block aligned', () {
    final built = _document(
      sizes: [8],
      material: GltfMaterial(
        pbrMetallicRoughness: GltfPbrMetallicRoughness(
          baseColorTexture: GltfTextureInfo(index: 0),
        ),
      ),
    );

    final logged = <String>[];
    final previous = sceneLog;
    sceneLog = logged.add;
    try {
      buildSceneDocument(built.doc, built.buffer, compressTextures: true);
    } finally {
      sceneLog = previous;
    }
    expect(logged, isEmpty);
  });
}
