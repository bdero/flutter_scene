import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/engine_lighting.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/material.dart' as material_internal;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _FakeTextureSource implements TextureSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('one material exposes core and layered physical properties', () {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.2, 0.3, 0.4, 1.0)
      ..metallicFactor = 0.25
      ..roughnessFactor = 0.6
      ..clearcoat = 0.8
      ..clearcoatRoughness = 0.15
      ..sheenColor = Vector4(0.1, 0.2, 0.3, 1.0)
      ..anisotropy = 0.5
      ..iridescence = 0.4;

    expect(material.baseColorFactor, Vector4(0.2, 0.3, 0.4, 1.0));
    expect(material.metallicFactor, 0.25);
    expect(material.roughnessFactor, 0.6);
    expect(material.clearcoat, 0.8);
    expect(material.clearcoatRoughness, 0.15);
    expect(material.sheenColor, Vector4(0.1, 0.2, 0.3, 1.0));
    expect(material.anisotropy, 0.5);
    expect(material.iridescence, 0.4);
    expect(material.isOpaque(), isTrue);
  });

  test('transmission updates opacity and cached render requirements', () {
    final revision = material_internal.materialSceneInputsRevision;
    final material = PhysicallyBasedMaterial()..transmission = 0.75;

    expect(material.isOpaque(), isFalse);
    expect(material.sceneInputs, hasLength(2));
    expect(material.translucentDepthWrite, isTrue);
    expect(material_internal.materialSceneInputsRevision, revision + 1);

    material.transmission = 0.5;
    expect(material_internal.materialSceneInputsRevision, revision + 1);

    material.transmission = 0.0;

    expect(material.isOpaque(), isTrue);
    expect(material.sceneInputs, isEmpty);
    expect(material.translucentDepthWrite, isFalse);
    expect(material_internal.materialSceneInputsRevision, revision + 2);
  });

  test('transmission reports a conservative scene-color sample footprint', () {
    final material = PhysicallyBasedMaterial()
      ..transmission = 1
      ..thickness = 0.7
      ..roughnessFactor = 0.08
      ..ior = 1.45;

    expect(material.sceneColorSampleBoundsExpansion, 0.7);
    expect(material.sceneColorSampleFilterLodFraction, closeTo(0.072, 1e-9));
  });

  test('the lightmap slot defaults to UV1 and an identity transform', () {
    final material = PhysicallyBasedMaterial();

    expect(material.lightmapTexture, isNull);
    expect(material.lightmapTextureTexCoord, 1);
    expect(material.lightmapTextureTransform.isIdentity, isTrue);
    expect(material.lightmapIntensity, 1.0);
    expect(material.lightmapRgbm, isFalse);
  });

  test('the lightmap slot round-trips its transform and texcoord', () {
    final texture = _FakeTextureSource();
    final transform = TextureTransform(
      offset: Vector2(0.25, 0.5),
      scale: Vector2(2.0, 3.0),
      rotation: 0.75,
    );
    final material = PhysicallyBasedMaterial()
      ..lightmapTexture = texture
      ..lightmapTextureTransform = transform
      ..lightmapTextureTexCoord = 0
      ..lightmapIntensity = 2.5
      ..lightmapRgbm = true;

    expect(material.lightmapTexture, same(texture));
    expect(material.lightmapTextureTransform, same(transform));
    expect(material.lightmapTextureTexCoord, 0);
    expect(material.lightmapIntensity, 2.5);
    expect(material.lightmapRgbm, isTrue);

    material.lightmapTextureTexCoord = 7;
    expect(material.lightmapTextureTexCoord, 1);
  });

  test('binding a lightmap flips the variant key without going physical', () {
    final material = PhysicallyBasedMaterial();
    final bit = PhysicallyBasedMaterial.lightmapVariantBit;

    expect(material.variantKey & bit, 0);

    material.lightmapTexture = _FakeTextureSource();
    expect(material.variantKey & bit, bit);
    // The lightmap bit sits outside the physical-feature mask, so a plain
    // lightmapped material keeps the standard shader path.
    expect(material.variantKey & 0x7f, 0);
    expect(material.hasPhysicalConfiguration, isFalse);

    material.lightmapTexture = null;
    expect(material.variantKey & bit, 0);
  });

  test('the lightmap uniform carries the transform, intensity, and rgbm', () {
    final info = Float32List(12);
    EngineLightingUniforms.packLightmapInfo(
      info,
      transform: TextureTransform(
        offset: Vector2(0.25, 0.5),
        scale: Vector2(2.0, 3.0),
      ),
      texCoord: 1,
      intensity: 2.5,
      rgbm: true,
    );

    expect(info.sublist(0, 4), [0.25, 0.5, 2.0, 3.0]);
    expect(info[4], 1.0); // cos(0)
    expect(info[5], 0.0); // sin(0)
    expect(info[6], 1.0); // UV set
    expect(info[7], 1.0); // RGBM decode
    expect(info[8], 2.5); // intensity

    EngineLightingUniforms.packLightmapInfo(
      info,
      transform: TextureTransform(),
      texCoord: 0,
      intensity: 1.0,
      rgbm: false,
    );
    expect(info[6], 0.0);
    expect(info[7], 0.0);
  });

  test('scalar ior and specular stay on the standard shader', () {
    final material = PhysicallyBasedMaterial()
      ..ior = 2.0
      ..specular = 0.5
      ..specularColor = Vector4(0.9, 0.8, 0.7, 1.0);

    // No physical feature bit, so the draw keeps the standard shader.
    expect(material.variantKey & 0x7f, 0);
    // Serialization still has to preserve them.
    expect(material.hasPhysicalConfiguration, isTrue);

    // A specular texture is what needs the physical variant.
    material.specularTexture = _FakeTextureSource();
    expect(material.variantKey & 0x7f, isNot(0));
    material.specularTexture = null;
    expect(material.variantKey & 0x7f, 0);
    material.specularColorTexture = _FakeTextureSource();
    expect(material.variantKey & 0x7f, isNot(0));
  });

  test('the folded dielectric F0 matches the physical formula', () {
    final defaults = PhysicallyBasedMaterial.dielectricSpecularF0(
      ior: 1.5,
      specular: 1.0,
      specularColor: Vector4.all(1.0),
    );
    expect(
      defaults.x,
      closeTo(EngineLightingUniforms.defaultDielectricF0, 1e-7),
    );
    expect(
      defaults.y,
      closeTo(EngineLightingUniforms.defaultDielectricF0, 1e-7),
    );
    expect(
      defaults.z,
      closeTo(EngineLightingUniforms.defaultDielectricF0, 1e-7),
    );

    // ((2 - 1) / (2 + 1))^2 = 1 / 9.
    final glass = PhysicallyBasedMaterial.dielectricSpecularF0(
      ior: 2.0,
      specular: 1.0,
      specularColor: Vector4.all(1.0),
    );
    expect(glass.x, closeTo(1 / 9, 1e-7));

    // The specular factor and color scale the F0 per channel.
    final tinted = PhysicallyBasedMaterial.dielectricSpecularF0(
      ior: 1.5,
      specular: 0.5,
      specularColor: Vector4(1.0, 0.5, 0.0, 1.0),
    );
    expect(tinted.x, closeTo(0.02, 1e-7));
    expect(tinted.y, closeTo(0.01, 1e-7));
    expect(tinted.z, 0.0);

    // Vector3 stores float32, hence the tolerances above. Clamped to [0, 1]
    // like the shader, and an ior below 1 reads as 1.
    final clamped = PhysicallyBasedMaterial.dielectricSpecularF0(
      ior: 100.0,
      specular: 1.0,
      specularColor: Vector4.all(30.0),
    );
    expect(clamped.x, 1.0);
    final air = PhysicallyBasedMaterial.dielectricSpecularF0(
      ior: 0.5,
      specular: 1.0,
      specularColor: Vector4.all(1.0),
    );
    expect(air.x, 0.0);
  });
}
