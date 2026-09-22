// Every fragment resource the engine's shaders declare must reflect at a
// binding of 64 or more. The compiler only assigns bindings to resources the
// shader reads; a declared-but-unread block keeps none and reflects at 0,
// where it collides with the vertex stage's FrameInfo. Vulkan builds one
// descriptor set layout for both stages, rejects the duplicate, and drops
// every draw with that pipeline (silently on drivers that skip validation).
// GLES resolves uniforms per stage and never notices, so this is the only
// check that catches the class without a Vulkan device.
//
// Runs against the SDK cache's impellerc, like fmat_runtime_compile_test.
// Skips when it is not found.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/fmat/fmat_emitter.dart';
import 'package:flutter_scene/src/fmat/fmat_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// impellerc's fragment-stage binding base (`SetBindingBaseOffset`).
const kFragmentBindingBase = 64;

/// Fragment shaders emitted from `.fmat` sources, one per shading model and
/// include set the emitter can produce.
const _fmatSources = <String, String>{
  'unlit': '''
material { name: "U", shading_model: unlit }
fragment { void Surface(inout MaterialInputs material) {} }
''',
  'unlit_scene_depth': '''
material { name: "UD", shading_model: unlit, engine_inputs: [scene_depth] }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(vec3(GetSceneDepth(vec2(0.0))), 1.0);
  }
}
''',
  'lit': '''
material { name: "L", shading_model: lit }
fragment { void Surface(inout MaterialInputs material) {} }
''',
  'physical': '''
material { name: "P", shading_model: physical }
fragment { void Surface(inout MaterialInputs material) {} }
''',
  'sky': '''
material { name: "S" }
sky { vec3 Sky(vec3 direction) { return vec3(direction.y); } }
''',
};

void main() async {
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    impellerc = null;
  }
  final skip = impellerc == null
      ? 'impellerc not found in the SDK cache'
      : false;

  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('binding_ranges'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  /// Compiles [source] for Vulkan and returns every fragment resource whose
  /// binding sits below the fragment base, as `name@binding`.
  Future<List<String>> lowBindings(File source) async {
    final out = tmp.path;
    final result = await Process.run(impellerc!.toFilePath(), [
      '--vulkan',
      '--input=${source.path}',
      '--include=${Directory('shaders').absolute.path}',
      '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
      '--sl=$out/out.spv',
      '--spirv=$out/out.spirv',
      '--reflection-json=$out/out.json',
    ]);
    expect(
      result.exitCode,
      0,
      reason: '${source.path} failed to compile:\n${result.stderr}',
    );
    final json =
        jsonDecode(File('$out/out.json').readAsStringSync())
            as Map<String, dynamic>;
    final resources = [
      ...?(json['buffers'] as List?),
      ...?(json['sampled_images'] as List?),
    ];
    return [
      for (final r in resources.cast<Map<String, dynamic>>())
        if ((r['binding'] as int) < kFragmentBindingBase)
          '${r['name']}@${r['binding']}',
    ];
  }

  final frags =
      Directory('shaders')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.frag'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  test('the engine ships fragment shaders to check', () {
    expect(frags, isNotEmpty);
  });

  for (final frag in frags) {
    final name = frag.uri.pathSegments.last;
    test(
      '$name reflects no fragment resource below the binding base',
      () async {
        expect(await lowBindings(frag), isEmpty);
      },
      skip: skip,
    );
  }

  final sources = {
    ..._fmatSources,
    // The engine's own catcher, the one include set the emitter builds for
    // that shading model.
    'shadow_catcher': File(
      'assets/materials/shadow_catcher.fmat',
    ).readAsStringSync(),
  };
  for (final entry in sources.entries) {
    test(
      'emitted ${entry.key} .fmat reflects no resource below the base',
      () async {
        final glsl = emitFragmentGlsl(parseFmat(entry.value));
        final file = File('${tmp.path}/${entry.key}.frag')
          ..writeAsStringSync(glsl);
        expect(await lowBindings(file), isEmpty);
      },
      skip: skip,
    );
  }
}
