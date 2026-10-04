// Covers the WGSL sidecar step the build hook runs, with a stand-in for the
// native translator: which shaders it is asked to translate, with which
// sampler mappings, and how its output is verified and recorded.
//
// ignore_for_file: implementation_imports
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/generated_assets/wgsl_sidecar.dart';
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

Uint8List _bundle({bool withVulkan = true}) {
  fb.BackendShaderObjectBuilder fragment() => fb.BackendShaderObjectBuilder(
    stage: fb.ShaderStage.kFragment,
    entrypoint: 'main',
    inputs: const [],
    uniformStructs: [
      fb.ShaderUniformStructObjectBuilder(
        name: 'FragInfo',
        $set: 0,
        binding: 64,
        sizeInBytes: 16,
        fields: const [],
      ),
    ],
    uniformTextures: [
      fb.ShaderUniformTextureObjectBuilder(
        name: 'albedo',
        $set: 0,
        binding: 65,
      ),
      fb.ShaderUniformTextureObjectBuilder(
        name: 'normals',
        $set: 0,
        binding: 66,
      ),
    ],
    shader: const [3, 2, 35, 7],
  );
  return fb.ShaderBundleObjectBuilder(
    shaders: [
      fb.ShaderObjectBuilder(
        name: 'Lit',
        openglEs: fragment(),
        vulkan: withVulkan ? fragment() : null,
      ),
    ],
    formatVersion: 2,
  ).toBytes();
}

const _goodWgsl = '''
@group(0u) @binding(64u) var<uniform> v : S;
@group(0u) @binding(65u) var v_1 : texture_2d<f32>;
@group(0u) @binding(193u) var v_2 : sampler;
@group(0u) @binding(66u) var v_3 : texture_2d<f32>;
@group(0u) @binding(194u) var v_4 : sampler;
''';

final class _FakeTranslator implements WgslBatchTranslator {
  _FakeTranslator(this.wgsl);

  final String wgsl;
  final List<WgslTranslationJob> jobs = [];

  @override
  String get revision => 'fake 1';

  @override
  Future<Map<String, String>> translateAll(
    List<WgslTranslationJob> jobs,
  ) async {
    this.jobs.addAll(jobs);
    return {for (final job in jobs) job.name: wgsl};
  }
}

void main() {
  test('translates the Vulkan entry with samplers mapped 128 up', () async {
    final translator = _FakeTranslator(_goodWgsl);
    final json = await buildWgslSidecar(
      _bundle(),
      translator,
      shippedBundleHash: 'abc',
    );
    final job = translator.jobs.single;
    expect(job.name, 'Lit');
    expect(job.spirv, [3, 2, 35, 7]);
    expect(job.samplerBindings, {65: 193, 66: 194});

    final sidecar = jsonDecode(json) as Map<String, Object?>;
    expect(sidecar['format'], kWgslSidecarFormat);
    expect(sidecar['bundle'], 'abc');
    expect(sidecar['translator'], 'fake 1, $kSpirvPreprocessing');
    final lit = (sidecar['shaders'] as Map)['Lit'] as Map;
    expect(lit['stage'], 'fragment');
    expect(lit['wgsl'], _goodWgsl);
    expect(lit['entryPoint'], 'main');
    expect(lit['uniforms'], [
      {
        'name': 'FragInfo',
        'group': 0,
        'binding': 64,
        'size': 16,
        'fields': <Object?>[],
      },
    ]);
    expect(lit['textures'], [
      {'name': 'albedo', 'group': 0, 'binding': 65, 'sampler': 193},
      {'name': 'normals', 'group': 0, 'binding': 66, 'sampler': 194},
    ]);
    expect(lit['inputs'], <Object?>[]);
  });

  test('fails naming the shader when Tint moves a binding', () async {
    final moved = _goodWgsl.replaceFirst('194u', '67u');
    expect(
      buildWgslSidecar(
        _bundle(),
        _FakeTranslator(moved),
        shippedBundleHash: 'abc',
      ),
      throwsA(
        isA<WgslSidecarException>().having(
          (e) => e.message,
          'message',
          contains('Lit'),
        ),
      ),
    );
  });

  test('refuses a bundle already trimmed of its SPIR-V', () async {
    expect(
      buildWgslSidecar(
        _bundle(withVulkan: false),
        _FakeTranslator(_goodWgsl),
        shippedBundleHash: 'abc',
      ),
      throwsA(isA<WgslSidecarException>()),
    );
  });

  test('the sidecar sits next to its bundle', () {
    expect(
      wgslSidecarPathFor('/out/base.shaderbundle'),
      '/out/base.shaderbundle.wgsl.json',
    );
  });
}
