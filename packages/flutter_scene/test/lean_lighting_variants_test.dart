// Covers the lean-lighting tier of the standard lit shader: every full entry
// has a lean twin in the base bundle, and each twin keeps its full entry's
// binding interface (blocks and their layouts, samplers, stage inputs) on
// every backend of a bundle compiled the way the build hook compiles one, so
// the engine binds both identically.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

const _twins = {
  'StandardFragment': 'StandardLeanFragment',
  'StandardCubeFragment': 'StandardLeanCubeFragment',
  'StandardNoShadowFragment': 'StandardLeanNoShadowFragment',
  'StandardNoShadowCubeFragment': 'StandardLeanNoShadowCubeFragment',
  'StandardLightmapFragment': 'StandardLightmapLeanFragment',
  'StandardLightmapCubeFragment': 'StandardLightmapLeanCubeFragment',
  'StandardLightmapNoShadowFragment': 'StandardLightmapLeanNoShadowFragment',
  'StandardLightmapNoShadowCubeFragment':
      'StandardLightmapLeanNoShadowCubeFragment',
};

// Slot numbers are assigned per compiled program, and the engine binds by
// name, so they may differ between twins. Whether a resource kept a slot at
// all may not: each backend's compile prunes a declared but unread resource,
// leaving binding 0 or 0xFFFFFFFF, or a backend index (`ext_res_0`, the Metal
// buffer or texture index) of 0xFFFFFFFF. Binding a pruned resource fails.
bool _pruned(int binding, int backendIndex) =>
    binding == 0 || binding == 0xFFFFFFFF || backendIndex == 0xFFFFFFFF;

// One backend's binding interface, keyed by resource.
Map<String, String> _interfaceOf(fb.BackendShader backend) => {
  for (final block
      in backend.uniformStructs ?? const <fb.ShaderUniformStruct>[])
    'block ${block.name}':
        '${block.sizeInBytes} '
        '${[for (final field in block.fields ?? const <fb.ShaderUniformStructField>[]) '${field.name}@${field.offsetInBytes}'].join(',')} '
        'pruned=${_pruned(block.binding, block.extRes0)}',
  for (final texture
      in backend.uniformTextures ?? const <fb.ShaderUniformTexture>[])
    'sampler ${texture.name}':
        'pruned=${_pruned(texture.binding, texture.extRes0)}',
  for (final input in backend.inputs ?? const <fb.ShaderInput>[])
    'input ${input.name}': '${input.location} ${input.type}',
};

void main() {
  test('every standard entry has a lean twin', () {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;
    _twins.forEach((full, lean) {
      expect(manifest, contains(full));
      expect(manifest, contains(lean), reason: '$full has no lean twin');
      final source = File(
        (manifest[lean] as Map<String, dynamic>)['file'] as String,
      ).readAsStringSync();
      final fullFile = (manifest[full] as Map<String, dynamic>)['file']
          .toString()
          .split('/')
          .last;
      expect(source, contains('#define FLUTTER_SCENE_LEAN_LIGHTING'));
      expect(source, contains('#include <$fullFile>'));
    });
  });

  test(
    'lean twins keep their full entry binding interface on every backend',
    () async {
      final manifest =
          jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
              as Map<String, dynamic>;
      final impellerc = await findImpellerC();
      final temp = Directory.systemTemp.createTempSync('lean_lighting');
      try {
        // One bundle holding every twin, compiled with the build hook's
        // arguments (shaderBundleImpellercArguments in flutter_gpu_shaders).
        final entries = {
          for (final name in [..._twins.keys, ..._twins.values])
            name: {
              'type': 'fragment',
              'file': File(
                (manifest[name] as Map<String, dynamic>)['file'] as String,
              ).absolute.path,
            },
        };
        final output = File.fromUri(temp.uri.resolve('twins.shaderbundle'));
        final result = await Process.run(impellerc.toFilePath(), [
          '--sl=${output.path}',
          '--shader-bundle=${jsonEncode(entries)}',
          '--gles-language-version=300',
          '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
          '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
        ]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');

        final shaders = {
          for (final shader
              in fb.ShaderBundle(output.readAsBytesSync()).shaders ??
                  const <fb.Shader>[])
            shader.name!: shader,
        };
        _twins.forEach((full, lean) {
          final f = shaders[full]!;
          final l = shaders[lean]!;
          final backends = {
            'Metal macOS': (f.metalDesktop, l.metalDesktop),
            'Metal iOS': (f.metalIos, l.metalIos),
            'OpenGL ES': (f.openglEs, l.openglEs),
            'Vulkan': (f.vulkan, l.vulkan),
          };
          backends.forEach((backend, pair) {
            final (fullShader, leanShader) = pair;
            expect(
              leanShader == null,
              fullShader == null,
              reason: '$lean and $full disagree on carrying $backend',
            );
            if (fullShader == null || leanShader == null) return;
            expect(
              _interfaceOf(leanShader),
              _interfaceOf(fullShader),
              reason: '$lean differs from $full on $backend',
            );
          });
        });
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
