// Guards the GPU morph path's shader structure: the morphed variants exist
// in the base bundle, the shared bodies stay define-guarded so unmorphed
// shaders compile unchanged, morphing happens before skinning, and the
// morphed entries compile (with the expected uniforms) on every backend
// impellerc targets.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_test/flutter_test.dart';

bool _hasNamedResource(Object? value, String name) {
  if (value is Map) {
    if (value['name'] == name) return true;
    return value.values.any((entry) => _hasNamedResource(entry, name));
  }
  if (value is List) {
    return value.any((entry) => _hasNamedResource(entry, name));
  }
  return false;
}

void main() {
  test('the base bundle carries the morphed vertex variants', () {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(
      manifest['MorphedUnskinnedVertex']['file'],
      'shaders/flutter_scene_morphed_unskinned.vert',
    );
    expect(
      manifest['MorphedSkinnedVertex']['file'],
      'shaders/flutter_scene_morphed_skinned.vert',
    );
  });

  test('unmorphed bodies stay define-guarded', () {
    for (final body in [
      'flutter_scene_unskinned_body.glsl',
      'flutter_scene_skinned_body.glsl',
    ]) {
      final source = File('shaders/$body').readAsStringSync();
      expect(source, contains('#ifdef FLUTTER_SCENE_MORPH_TARGETS'));
      // The plain path aliases the attributes through macros so the
      // preprocessed body is byte-identical to the pre-morph shader.
      expect(source, contains('#define in_position position'));
      expect(source, contains('#define in_normal normal'));
    }
    for (final wrapper in [
      'flutter_scene_morphed_unskinned.vert',
      'flutter_scene_morphed_skinned.vert',
    ]) {
      expect(
        File('shaders/$wrapper').readAsStringSync(),
        contains('#define FLUTTER_SCENE_MORPH_TARGETS'),
      );
    }
    for (final plain in [
      'flutter_scene_unskinned.vert',
      'flutter_scene_skinned.vert',
    ]) {
      expect(
        File('shaders/$plain').readAsStringSync(),
        isNot(contains('FLUTTER_SCENE_MORPH_TARGETS')),
      );
    }
  });

  test('morphing happens before the skin matrix', () {
    final body = File(
      'shaders/flutter_scene_skinned_body.glsl',
    ).readAsStringSync();
    final morphed = body.indexOf('MorphedPosition(position)');
    final skinApplied = body.indexOf('skin_matrix * vec4(in_position, 1.0)');
    expect(morphed, greaterThan(0));
    expect(skinApplied, greaterThan(morphed));
    // The world transform composes with the skin matrix over the morphed
    // position too.
    expect(body, contains('combined_transform * vec4(in_position, 1.0)'));
  });

  test('the shader cap matches the engine constant', () {
    final morph = File('shaders/flutter_scene_morph.glsl').readAsStringSync();
    expect(
      morph,
      contains('const int kMaxMorphTargets = $kMaxGpuMorphTargets;'),
    );
    expect(morph, contains('vec4 morph_pairs[kMaxMorphTargets];'));
    // Normal renormalization guards the near-zero collapse like the CPU
    // blend.
    expect(morph, contains('length_squared > 1e-12'));
  });

  test('morphed variants compile on every impellerc backend', () async {
    final temp = Directory.systemTemp.createTempSync('morph_variants');
    try {
      final impellerc = await findImpellerC();
      for (final entry in [
        'flutter_scene_morphed_unskinned',
        'flutter_scene_morphed_skinned',
      ]) {
        for (final backend in ['opengl-es', 'metal-desktop', 'vulkan']) {
          final reflection = File.fromUri(
            temp.uri.resolve('$entry.$backend.json'),
          );
          final result = await Process.run(impellerc.toFilePath(), [
            '--$backend',
            '--input-type=vert',
            '--input=shaders/$entry.vert',
            '--sl=${temp.uri.resolve('$entry.$backend.sl').toFilePath()}',
            '--spirv=${temp.uri.resolve('$entry.$backend.spirv').toFilePath()}',
            '--reflection-json=${reflection.path}',
            '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
            '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
            if (backend == 'opengl-es') '--gles-language-version=300',
          ]);
          expect(
            result.exitCode,
            0,
            reason: '$entry $backend: ${result.stdout}\n${result.stderr}',
          );
          final parsed = jsonDecode(reflection.readAsStringSync());
          expect(
            _hasNamedResource(parsed, 'MorphInfo'),
            isTrue,
            reason: '$entry $backend should reflect the MorphInfo block',
          );
          expect(
            _hasNamedResource(parsed, 'morph_texture'),
            isTrue,
            reason: '$entry $backend should reflect the morph sampler',
          );
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('GPU/CPU selection is deterministic by packed texture fit', () {
    MorphTargetData data({
      required int targetCount,
      required int vertexCount,
    }) => MorphTargetData(
      vertexCount: vertexCount,
      targetCount: targetCount,
      positionDeltas: Float32List(targetCount * vertexCount * 3),
    );

    // Fits the guaranteed dimensions: GPU path, morphed shader variant.
    final gpu = MorphedUnskinnedGeometry(data(targetCount: 4, vertexCount: 16));
    expect(gpu.usesGpuMorphing, isTrue);

    // One row per band at width 1; more bands than the guaranteed height
    // falls back to CPU blending on the plain unskinned shader.
    final cpu = MorphedUnskinnedGeometry(
      data(targetCount: kMorphTextureMaxDimension + 1, vertexCount: 1),
    );
    expect(cpu.usesGpuMorphing, isFalse);

    final skinned = MorphedSkinnedGeometry(
      data(targetCount: 4, vertexCount: 16),
    );
    expect(skinned.usesGpuMorphing, isTrue);
  });
}
