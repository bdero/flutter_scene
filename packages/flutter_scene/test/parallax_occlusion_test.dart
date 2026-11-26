// Covers parallax occlusion's build side: the `material_features` user-define,
// the lazily loaded parallax bundle and its entries, the physical twins, the
// height packing, and that every other lit shader stays untouched.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/fmat/build_materials.dart'
    show emitFragmentShaderVariants;
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart'
    show isParallaxSilhouetteEntry, wrapEngineManifest;
import 'package:flutter_scene/src/generated_assets/material_features.dart';
import 'package:flutter_scene/src/render/pass_camera.dart';
import 'package:flutter_scene/src/texture/build_textures.dart'
    show packParallaxHeight;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// The parallax occlusion identifiers, as opposed to the box-projected
// reflection ones (ParallaxCorrectReflection and the parallax box).
final RegExp _occlusionIdentifier = RegExp(
  r'Parallax(Ray|Hit|Begin|Engine|March|Slot|Perturb|SelfShadow|Silhouette|'
  r'Tangent|Layer|Surface|Exit|Occlusion|Info)|parallax_(info|uv|ray|hit|'
  r'offset|sun|surface)',
);

Map<String, Object?> _parallaxManifest() =>
    (jsonDecode(File('shaders/parallax.shaderbundle.json').readAsStringSync())
            as Map)
        .cast<String, Object?>();

// The lines of [source] outside every `#ifdef` (or `#if defined`) block on a
// FLUTTER_SCENE_PARALLAX_* define, keeping the `#else` side of such a block.
List<String> _linesOutsideParallaxDefines(String source) {
  final outside = <String>[];
  // Per open conditional: whether it is a parallax one, and whether its
  // current branch is the parallax side.
  final stack = <(bool, bool)>[];
  bool inParallax() => stack.any((frame) => frame.$1 && frame.$2);
  for (final line in const LineSplitter().convert(source)) {
    final directive = line.trim();
    if (directive.startsWith('#if')) {
      final parallax =
          directive.startsWith('#ifdef FLUTTER_SCENE_PARALLAX_') ||
          directive.startsWith('#if defined(FLUTTER_SCENE_PARALLAX_');
      stack.add((parallax, true));
      continue;
    }
    if (directive.startsWith('#else') || directive.startsWith('#elif')) {
      final (parallax, _) = stack.removeLast();
      stack.add((parallax, false));
      if (!inParallax()) outside.add(line);
      continue;
    }
    if (directive.startsWith('#endif')) {
      stack.removeLast();
      continue;
    }
    if (!inParallax()) outside.add(line);
  }
  return outside;
}

void main() {
  group('parseCompiledOutMaterialFeatures', () {
    test('only false leaves a feature out', () {
      expect(parseCompiledOutMaterialFeatures(null), isEmpty);
      expect(
        parseCompiledOutMaterialFeatures({
          'parallax_occlusion': true,
          'parallax_silhouette': false,
        }),
        {MaterialFeature.parallaxSilhouette},
      );
    });

    test('leaving out parallax leaves out its silhouette', () {
      expect(parseCompiledOutMaterialFeatures({'parallax_occlusion': false}), {
        MaterialFeature.parallaxOcclusion,
        MaterialFeature.parallaxSilhouette,
      });
    });

    test('rejects unknown names and non-boolean values', () {
      expect(
        () => parseCompiledOutMaterialFeatures({'parallax': false}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('parallax_occlusion'),
          ),
        ),
      );
      expect(
        () => parseCompiledOutMaterialFeatures({'parallax_occlusion': 0}),
        throwsFormatException,
      );
    });

    test('describes a set the same way whatever its order', () {
      expect(describeCompiledOutMaterialFeatures({}), '');
      expect(
        describeCompiledOutMaterialFeatures({
          MaterialFeature.parallaxSilhouette,
          MaterialFeature.parallaxOcclusion,
        }),
        'parallax_occlusion,parallax_silhouette',
      );
      expect(materialFeaturesVariantSuffix({}), '');
    });
  });

  test('a left-out material feature leaves a marker in the base bundle', () {
    final root = Directory.systemTemp.createTempSync('material_features_');
    addTearDown(() => root.deleteSync(recursive: true));
    final shaders = Directory('${root.path}/shaders')..createSync();
    final wrappers = Directory('${root.path}/wrappers')..createSync();
    File('${shaders.path}/lit.frag').writeAsStringSync('void main() {}\n');

    final wrapped = wrapEngineManifest(
      {
        'StandardFragment': {'type': 'fragment', 'file': 'shaders/lit.frag'},
      },
      wrappers.uri,
      shaders.uri,
      materialOff: {MaterialFeature.parallaxOcclusion},
    );
    expect(wrapped.keys, {
      'StandardFragment',
      'MaterialFeatureOffParallaxOcclusion',
    });
    expect(
      File.fromUri(
        wrappers.uri.resolve(
          (wrapped['StandardFragment']! as Map)['file'] as String,
        ),
      ).readAsStringSync(),
      '#include <lit.frag>\n',
    );
  });

  test('the parallax bundle twins the standard entries and the silhouette '
      'depth shaders', () {
    final manifest = _parallaxManifest();
    final base =
        (jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
                as Map)
            .cast<String, Object?>();
    final lit = manifest.keys.where((k) => !isParallaxSilhouetteEntry(k));
    final silhouette = manifest.keys.where(isParallaxSilhouetteEntry);
    expect(lit, hasLength(8));
    expect(silhouette, {
      'ParallaxCoverageFragment',
      'ParallaxDepthOnlyFragment',
      'ParallaxLinearDepthFragment',
      'ParallaxLinearDepthNormalFragment',
    });
    // Each lit entry is one define over a base entry of the same tier, so
    // the two keep the same binding interface apart from ParallaxInfo.
    for (final name in lit) {
      final twin = name.replaceFirst('Parallax', '');
      expect(base.keys, contains(twin), reason: name);
      final wrapper = File(
        (manifest[name]! as Map)['file'] as String,
      ).readAsStringSync();
      final twinFile = ((base[twin]! as Map)['file'] as String).split('/').last;
      expect(wrapper, contains('#define FLUTTER_SCENE_PARALLAX_OCCLUSION\n'));
      expect(wrapper, contains('#include <$twinFile>'), reason: name);
    }
    for (final name in silhouette) {
      final wrapper = File(
        (manifest[name]! as Map)['file'] as String,
      ).readAsStringSync();
      expect(wrapper, contains('#define FLUTTER_SCENE_PARALLAX_SILHOUETTE\n'));
    }
  });

  test('parallax code in shared shaders sits behind its defines', () {
    // What keeps every non-parallax entry compiling to the bytes it did
    // before parallax existed.
    for (final path in [
      'shaders/flutter_scene_standard.frag',
      'shaders/material_inputs.glsl',
      'shaders/material_lighting.glsl',
      'shaders/depth_mask.glsl',
      'assets/materials/physical_opaque.fmat',
    ]) {
      final outside = _linesOutsideParallaxDefines(
        File(path).readAsStringSync(),
      ).where((line) => !line.contains('#define SLOT_TEXTURE'));
      for (final line in outside) {
        // Comments may mention it, and box-projected reflections own the
        // ParallaxCorrect names.
        final code = line.split('//').first;
        expect(
          code,
          isNot(contains(_occlusionIdentifier)),
          reason: '$path: $line',
        );
      }
    }
    // A plain texture() call when parallax is off.
    expect(
      File('shaders/flutter_scene_standard.frag').readAsStringSync(),
      contains(
        '#define SLOT_TEXTURE(tex, uv, transform, rotation) texture(tex, uv)',
      ),
    );
  });

  test(
    'parallax entries compile on every backend with no extra sampler',
    () async {
      final impellerc = await findImpellerC();
      final temp = Directory.systemTemp.createTempSync('parallax_entries');
      addTearDown(() => temp.deleteSync(recursive: true));
      final base =
          (jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
                  as Map)
              .cast<String, Object?>();
      Future<int> samplers(String file, String backend, String name) async {
        final reflection = File.fromUri(temp.uri.resolve('$name.json'));
        final result = await Process.run(impellerc.toFilePath(), [
          backend,
          '--input-type=frag',
          '--input=$file',
          '--sl=${temp.uri.resolve('$name.out').toFilePath()}',
          '--spirv=${temp.uri.resolve('$name.spirv').toFilePath()}',
          '--reflection-json=${reflection.path}',
          '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
          '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
          if (backend == '--opengl-es') '--gles-language-version=300',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '$name $backend\n${result.stdout}\n${result.stderr}',
        );
        final json = jsonDecode(reflection.readAsStringSync()) as Map;
        return (json['sampled_images']! as List).length;
      }

      for (final MapEntry(:key, :value) in _parallaxManifest().entries) {
        final file = (value! as Map)['file'] as String;
        for (final backend in ['--opengl-es', '--metal-desktop', '--vulkan']) {
          final count = await samplers(file, backend, key);
          expect(count, lessThanOrEqualTo(15), reason: '$key $backend');
          if (backend != '--opengl-es' || isParallaxSilhouetteEntry(key)) {
            continue;
          }
          // The height rides the normal texture, so the lit twins declare
          // exactly the samplers their base entries do.
          final twin = key.replaceFirst('Parallax', '');
          final twinFile = (base[twin]! as Map)['file'] as String;
          expect(
            count,
            await samplers(twinFile, backend, twin),
            reason: '$key declares a sampler $twin does not',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('physical opaque ships parallax twins without a lightmap axis', () {
    const path = 'assets/materials/physical_opaque.fmat';
    final compiled = compileFmat(File(path).readAsStringSync(), fileName: path);
    final variants = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
      generateLightmapVariant: true,
      generateParallaxVariant: true,
    );
    final parallax = variants.keys.where((k) => k.contains('Parallax'));
    expect(parallax.toSet(), {
      'PhysicalOpaqueParallax',
      'PhysicalOpaqueParallaxShadow',
      'PhysicalOpaqueParallaxCube',
      'PhysicalOpaqueParallaxShadowCube',
    });
    for (final name in parallax) {
      expect(
        variants[name],
        contains('#define FLUTTER_SCENE_PARALLAX_OCCLUSION'),
        reason: name,
      );
    }
    expect(
      variants['PhysicalOpaque'],
      isNot(contains('#define FLUTTER_SCENE_PARALLAX_OCCLUSION')),
    );
  });

  test(
    'a cutout .fmat marches and cuts in its shaded and depth entries',
    () async {
      const source = '''
material {
  name: "ParallaxCutout",
  shading_model: lit,
  alpha_to_coverage: true,
  parameters: [
    { type: float, name: depth, default: 0.06 },
    { type: sampler2d, name: albedo_texture, hint: default_white },
    { type: sampler2d, name: normal_height, hint: default_normal },
  ],
}

fragment {
#include <parallax.glsl>

  void Surface(inout MaterialInputs material) {
    highp vec2 uv = GetUV0();
    ParallaxRay ray = ParallaxBeginSurfaceRay(normal_height, uv,
                                              material_params.depth);
    ParallaxHit hit = ParallaxMarch(normal_height, ray,
                                    ParallaxLayerCount(normal_height, ray, 32));
    bool inside =
        ParallaxInsideSilhouette(ray, hit, vec4(0.0, 0.0, 1.0, 1.0), 1.0);
    vec4 albedo = textureGrad(albedo_texture, uv + hit.offset, dFdx(uv),
                              dFdy(uv));
    material.base_color =
        vec4(SRGBToLinear(albedo.rgb), inside ? 1.0 : 0.0);
    material.normal = ParallaxPerturbNormal(
        normal_height, GetWorldNormal(), v_viewvector, uv, hit.offset,
        vec2(1.0));
    PrepareMaterial(material);
  }
}
''';
      final variants = emitFragmentShaderVariants(
        compileFmat(source, fileName: 'parallax_cutout.fmat'),
        generateShadowVariant: true,
      );
      // The depth passes run Surface() too, so they cut the same outline.
      expect(variants.keys, contains('ParallaxCutoutShadowSurface'));
      final impellerc = await findImpellerC();
      final temp = Directory.systemTemp.createTempSync('parallax_fmat');
      addTearDown(() => temp.deleteSync(recursive: true));
      for (final MapEntry(:key, :value) in variants.entries) {
        final input = File.fromUri(temp.uri.resolve('$key.frag'))
          ..writeAsStringSync(value);
        for (final backend in ['--opengl-es', '--metal-desktop', '--vulkan']) {
          final result = await Process.run(impellerc.toFilePath(), [
            backend,
            '--input-type=frag',
            '--input=${input.path}',
            '--sl=${temp.uri.resolve('$key.out').toFilePath()}',
            '--spirv=${temp.uri.resolve('$key.spirv').toFilePath()}',
            '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
            '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
            if (backend == '--opengl-es') '--gles-language-version=300',
          ]);
          expect(
            result.exitCode,
            0,
            reason: '$key $backend\n${result.stdout}\n${result.stderr}',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('height packs into the normal map alpha', () {
    final normal = Uint8List.fromList([128, 128, 255, 255, 10, 20, 30, 40]);
    final height = Uint8List.fromList([200, 0, 0, 255, 50, 99, 99, 99]);
    packParallaxHeight(normal, height);
    expect(normal, [128, 128, 255, 200, 10, 20, 30, 50]);
    expect(() => packParallaxHeight(normal, Uint8List(4)), throwsArgumentError);
  });

  group('PassCamera', () {
    test('recovers an orthographic view axis', () {
      final view = makeViewMatrix(
        Vector3(0, 10, 0),
        Vector3.zero(),
        Vector3(0, 0, -1),
      );
      final projection = makeOrthographicMatrix(-5, 5, -5, 5, 0.1, 50);
      final camera = PassCamera.fromViewProjection(projection * view);
      expect(camera.orthographic, isTrue);
      expect(camera.forward.x, closeTo(0, 1e-5));
      expect(camera.forward.y, closeTo(-1, 1e-5));
      expect(camera.forward.z, closeTo(0, 1e-5));
    });

    test('recovers a perspective eye and axis', () {
      final eye = Vector3(3, 4, 5);
      final view = makeViewMatrix(eye, Vector3.zero(), Vector3(0, 1, 0));
      final projection = makePerspectiveMatrix(1.0, 1.0, 0.1, 100);
      final camera = PassCamera.fromViewProjection(projection * view);
      expect(camera.orthographic, isFalse);
      expect(camera.position.x, closeTo(3, 1e-3));
      expect(camera.position.y, closeTo(4, 1e-3));
      expect(camera.position.z, closeTo(5, 1e-3));
      final toward = -eye.normalized();
      expect(camera.forward.dot(toward), closeTo(1, 1e-5));
    });
  });
}
