// Covers the lean-lighting tier of the standard lit shader: every full entry
// has a lean twin in the base bundle, and each twin keeps its full entry's
// binding interface (samplers, blocks and their layouts, stage inputs and
// outputs) so the engine binds both identically.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
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

// The reflection sections that make up the binding interface.
const _interface = [
  'sampled_images',
  'buffers',
  'stage_inputs',
  'stage_outputs',
  'struct_definitions',
];

// Binding slots are assigned per compiled program, and the engine binds by
// name, so they may differ between twins. Whether a resource kept a slot at
// all may not: the optimizer prunes a declared but unread resource to slot 0
// (or 0xFFFFFFFF), and binding one crashes on some backends.
const _slotFields = {'binding', 'ext_res_0', 'ext_res_1'};

bool _pruned(Object? binding) => binding == 0 || binding == 0xFFFFFFFF;

Future<Map<String, Object?>> _reflect(
  Uri impellerc,
  Directory temp,
  String entry,
  String path,
) async {
  final reflection = File.fromUri(temp.uri.resolve('$entry.json'));
  final result = await Process.run(impellerc.toFilePath(), [
    '--opengl-es',
    '--gles-language-version=300',
    '--input-type=frag',
    '--input=$path',
    '--sl=${temp.uri.resolve('$entry.out').toFilePath()}',
    '--spirv=${temp.uri.resolve('$entry.spirv').toFilePath()}',
    '--reflection-json=${reflection.path}',
    '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
    '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
  ]);
  expect(
    result.exitCode,
    0,
    reason: '$entry: ${result.stdout}${result.stderr}',
  );
  return (jsonDecode(reflection.readAsStringSync()) as Map).cast();
}

// One reflection section keyed by resource name, with slot fields dropped.
Map<String, String> _byName(Map<String, Object?> reflection, String section) {
  final entries = (reflection[section] as List?) ?? const [];
  return {
    for (final entry in entries.cast<Map<String, Object?>>())
      '${entry['name']}': jsonEncode({
        for (final MapEntry(:key, :value) in entry.entries)
          if (!_slotFields.contains(key)) key: value,
        if (entry.containsKey('binding')) 'pruned': _pruned(entry['binding']),
      }),
  };
}

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

  test('lean twins keep their full entry binding interface', () async {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;
    final impellerc = await findImpellerC();
    final temp = Directory.systemTemp.createTempSync('lean_lighting');
    try {
      for (final MapEntry(key: full, value: lean) in _twins.entries) {
        final fullReflection = await _reflect(
          impellerc,
          temp,
          full,
          (manifest[full] as Map<String, dynamic>)['file'] as String,
        );
        final leanReflection = await _reflect(
          impellerc,
          temp,
          lean,
          (manifest[lean] as Map<String, dynamic>)['file'] as String,
        );
        for (final section in _interface) {
          expect(
            _byName(leanReflection, section),
            _byName(fullReflection, section),
            reason: '$lean differs from $full in $section',
          );
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
