// Covers the buildTextures build hook (cooking loose images into `.fstex`
// containers and registering them as DataAssets) and the TextureRegistry's
// source-path resolution. Mirrors the buildScenes coverage.

import 'dart:io';
import 'dart:typed_data';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_scene/src/importer/src/gltf/types.dart';
import 'package:flutter_scene/src/texture/build_textures.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/texture_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';
import 'package:image/image.dart' as img;

void main() {
  test('textureDataAssetName computes a stable DataAsset name', () {
    expect(
      textureDataAssetName('assets/shadow_plane.fstex'),
      'flutter_scene/texture/assets/shadow_plane.fstex',
    );
  });

  test('cooks an image, writes a mipped .fstex, and emits a DataAsset', () {
    final temp = Directory.systemTemp.createTempSync('texture_build');
    try {
      final pngUri = temp.uri.resolve('assets/checker.png');
      File.fromUri(pngUri)
        ..createSync(recursive: true)
        ..writeAsBytesSync(_checkerPng(64));

      final input = _buildInput(packageRoot: temp.uri, buildDataAssets: true);
      final outputBuilder = BuildOutputBuilder();

      buildTextures(
        buildInput: input,
        buildOutput: outputBuilder,
        textures: ['assets/checker.png'],
        assetMode: TextureAssetMode.dataAssetsIfAvailable,
      );

      final fstexPath = temp.uri.resolve('build/textures/assets/checker.fstex');
      expect(File.fromUri(fstexPath).existsSync(), isTrue);

      // The cooked container decodes and carries the engine mip chain.
      final texture = readKtx2(File.fromUri(fstexPath).readAsBytesSync());
      expect(texture.levels, hasLength(engineMipLevelCount(64, 64)));
      final decoded = decodeKtx2Level(texture);
      expect(decoded.width, 64);
      expect(decoded.height, 64);

      final output = outputBuilder.build();
      final data = output.assets.data;
      expect(data, hasLength(1));
      expect(data.single.package, 'example_app');
      expect(data.single.name, 'flutter_scene/texture/assets/checker.fstex');
      expect(output.dependencies, contains(pngUri));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('rejects images that are not block-aligned', () {
    final temp = Directory.systemTemp.createTempSync('texture_build');
    try {
      final pngUri = temp.uri.resolve('assets/odd.png');
      File.fromUri(pngUri)
        ..createSync(recursive: true)
        ..writeAsBytesSync(_checkerPng(30));

      expect(
        () => buildTextures(
          buildInput: _buildInput(packageRoot: temp.uri, buildDataAssets: true),
          buildOutput: BuildOutputBuilder(),
          textures: ['assets/odd.png'],
        ),
        throwsA(predicate((e) => e.toString().contains('multiples of 4'))),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('cooks a normal map with vector-renormalizing mips', () {
    final temp = Directory.systemTemp.createTempSync('texture_build');
    try {
      // Opposed +x/-x tangent normals cancel; only the normal-content
      // downsample falls back to +z (blue).
      final image = img.Image(width: 8, height: 8, numChannels: 4);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          image.setPixelRgba(x, y, x.isEven ? 255 : 0, 128, 128, 255);
        }
      }
      final pngUri = temp.uri.resolve('assets/bump.png');
      File.fromUri(pngUri)
        ..createSync(recursive: true)
        ..writeAsBytesSync(img.encodePng(image));

      buildTextures(
        buildInput: _buildInput(packageRoot: temp.uri, buildDataAssets: true),
        buildOutput: BuildOutputBuilder(),
        textures: ['assets/bump.png'],
        contents: {'assets/bump.png': TextureContent.normal},
      );

      final texture = readKtx2(
        File.fromUri(
          temp.uri.resolve('build/textures/assets/bump.fstex'),
        ).readAsBytesSync(),
      );
      final mip = decodeKtx2Level(texture, level: 1);
      expect(mip.rgba[2], greaterThan(200));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('rejects contents keys that are not listed textures', () {
    final temp = Directory.systemTemp.createTempSync('texture_build');
    try {
      expect(
        () => buildTextures(
          buildInput: _buildInput(packageRoot: temp.uri, buildDataAssets: true),
          buildOutput: BuildOutputBuilder(),
          textures: ['assets/dirt.png'],
          contents: {'assets/dirt_normal.png': TextureContent.normal},
        ),
        throwsA(predicate((e) => e.toString().contains('dirt_normal'))),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('emitter derives texture roles from glTF material slots', () {
    final doc = GltfDocument(
      textures: [for (var i = 0; i < 5; i++) GltfTexture(source: i)],
      materials: [
        GltfMaterial(
          pbrMetallicRoughness: GltfPbrMetallicRoughness(
            baseColorTexture: GltfTextureInfo(index: 0),
            metallicRoughnessTexture: GltfTextureInfo(index: 1),
          ),
          normalTexture: GltfTextureInfo(index: 2),
          occlusionTexture: GltfTextureInfo(index: 3),
        ),
        // Reuses the metallic-roughness texture as a base color; the color
        // interpretation outranks data.
        GltfMaterial(
          pbrMetallicRoughness: GltfPbrMetallicRoughness(
            baseColorTexture: GltfTextureInfo(index: 1),
          ),
        ),
      ],
    );
    expect(gltfTextureContents(doc), [
      TextureContent.color, // base color
      TextureContent.color, // metallic-roughness shared with a color slot
      TextureContent.normal, // normal map
      TextureContent.data, // occlusion
      TextureContent.color, // unreferenced defaults to color
    ]);
  });

  test('registry resolves source paths with or without extension', () async {
    final registry = await TextureRegistry.load(
      assetKeys: [
        'packages/example_app/flutter_scene/texture/assets/shadow_plane.fstex',
        'packages/other_pkg/flutter_scene/texture/assets/dirt.fstex',
        'packages/example_app/assets/unrelated.png',
      ],
    );
    const key =
        'packages/example_app/flutter_scene/texture/assets/shadow_plane.fstex';
    expect(registry.resolveKey('assets/shadow_plane.png'), key);
    expect(registry.resolveKey('assets/shadow_plane'), key);
    expect(
      registry.resolveKey('assets/dirt.png', package: 'other_pkg'),
      'packages/other_pkg/flutter_scene/texture/assets/dirt.fstex',
    );
    expect(
      () => registry.resolveKey('assets/missing.png'),
      throwsA(isA<StateError>()),
    );
  });

  test('registry rejects ambiguous matches without a package', () async {
    final registry = await TextureRegistry.load(
      assetKeys: [
        'packages/pkg_a/flutter_scene/texture/assets/dirt.fstex',
        'packages/pkg_b/flutter_scene/texture/assets/dirt.fstex',
      ],
    );
    expect(
      () => registry.resolveKey('assets/dirt.png'),
      throwsA(isA<StateError>()),
    );
    expect(
      registry.resolveKey('assets/dirt.png', package: 'pkg_a'),
      'packages/pkg_a/flutter_scene/texture/assets/dirt.fstex',
    );
  });
}

BuildInput _buildInput({
  required Uri packageRoot,
  required bool buildDataAssets,
}) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'example_app',
      outputDirectoryShared: packageRoot.resolve('.dart_tool/hook/'),
      outputFile: packageRoot.resolve('.dart_tool/hook/output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  if (buildDataAssets) {
    DataAssetsExtension().setupBuildInput(builder);
  }
  return builder.build();
}

Uint8List _checkerPng(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final checker = ((x >> 2) + (y >> 2)).isEven;
      image.setPixelRgba(
        x,
        y,
        checker ? 220 : 40,
        checker ? 120 : 160,
        90,
        255,
      );
    }
  }
  return img.encodePng(image);
}
