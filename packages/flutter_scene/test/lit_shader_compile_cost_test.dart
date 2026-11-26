// Guards the compile cost and the derivatives of the standard lit shaders on
// backends that compile GLSL at run time, ANGLE's Direct3D backend (Impeller on
// Windows) above all. There a pipeline's first use translates the fragment
// shader to HLSL and runs the Direct3D compiler, and nothing keeps the result
// between launches, so every launch pays it. Three patterns in the generated
// OpenGL ES source made that slow or wrong:
//
//  * An implicit-LOD `texture()` inside a loop. ANGLE marks such a loop
//    `[loop]` and every branch around it `[flatten]`, and reads the texture
//    at LOD 0 anyway. SPIRV-Cross emits an early `return` as a one-iteration
//    `do { } while (false)`, so a function that returns early before such a
//    read is enough.
//  * A screen-space derivative (`dFdx`, `dFdy`, `fwidth`) inside a loop. In
//    a loop that can exit early, a one-iteration one included, ANGLE writes
//    the derivative as `0.0` instead of `ddx`/`ddy`.
//  * The directional cascade sampler inlined once per cascade.
//
// All three are checked on the source the build hook's compile produces.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/build.dart'
    show shaderBundleImpellercArguments;
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart'
    show engineGlesLanguageVersion;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

const _litEntries = [
  'StandardFragment',
  'StandardNoShadowFragment',
  'StandardLeanFragment',
  'StandardLeanNoShadowFragment',
];

// Texture reads that take their LOD from screen-space derivatives.
// `textureLod`, `textureGrad` and `texelFetch` do not, and none of them
// matches because of the word boundary.
final _implicitLodRead = RegExp(r'\b(texture|textureOffset|textureProj)\s*\(');
final _derivative = RegExp(r'\b(dFdx|dFdy|fwidth)\w*\s*\(');
final _loopHead = RegExp(r'^\s*(for\s*\(|while\s*\(|do\b)');

/// The lines of [source] that read a texture at an implicit LOD inside a loop.
List<String> implicitLodReadsInLoops(String source) =>
    _linesInLoops(source, _implicitLodRead);

/// The lines of [source] that take a screen-space derivative inside a loop.
List<String> derivativesInLoops(String source) =>
    _linesInLoops(source, _derivative);

/// The lines of [source] that match [pattern] inside a loop.
///
/// impellerc inlines every function into `main`, so the loops that enclose a
/// line are the ones whose braces are open when it is reached.
List<String> _linesInLoops(String source, RegExp pattern) {
  final found = <String>[];
  // The brace depth at which each open loop's body started.
  final loops = <int>[];
  var depth = 0;
  var pendingLoop = false;
  for (final line in const LineSplitter().convert(source)) {
    if (_loopHead.hasMatch(line)) pendingLoop = true;
    if (loops.isNotEmpty && pattern.hasMatch(line)) {
      found.add(line.trim());
    }
    for (final char in line.codeUnits) {
      if (char == 0x7B) {
        depth++;
        if (pendingLoop) {
          loops.add(depth);
          pendingLoop = false;
        }
      } else if (char == 0x7D) {
        if (loops.isNotEmpty && loops.last == depth) loops.removeLast();
        depth--;
      }
    }
  }
  return found;
}

void main() {
  test('implicitLodReadsInLoops finds a read in a one-iteration loop', () {
    const source = '''
void main()
{
    vec4 a = texture(s, uv);
    do
    {
        if (early)
        {
            break;
        }
        vec4 b = texture(s, uv);
        vec4 c = textureLod(s, uv, 0.0);
    } while (false);
    for (int i = 0; i < n; i++)
    {
        vec4 d = textureOffset(s, uv, ivec2(1, 0));
        vec4 f = texelFetch(s, ivec2(0), 0);
    }
    vec4 e = texture(s, uv);
}
''';
    expect(implicitLodReadsInLoops(source), [
      'vec4 b = texture(s, uv);',
      'vec4 d = textureOffset(s, uv, ivec2(1, 0));',
    ]);
  });

  test('derivativesInLoops finds a derivative in a one-iteration loop', () {
    const source = '''
void main()
{
    vec3 a = dFdx(n);
    do
    {
        if (early)
        {
            break;
        }
        vec3 b = dFdy(n);
    } while (false);
    for (int i = 0; i < n; i++)
    {
        float c = fwidth(uv.x);
        vec4 d = textureGrad(s, uv, a.xy, a.xy);
    }
}
''';
    expect(derivativesInLoops(source), [
      'vec3 b = dFdy(n);',
      'float c = fwidth(uv.x);',
    ]);
  });

  group('the lit shaders, compiled for OpenGL ES', () {
    // Each entry's generated OpenGL ES source, compiled once for the group.
    Future<Map<String, String>>? compiled;
    Future<Map<String, String>> compile() async {
      final manifest =
          jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
              as Map<String, dynamic>;
      final impellerc = await findImpellerC();
      final temp = Directory.systemTemp.createTempSync('lit_compile_cost');
      try {
        final entries = {
          for (final name in _litEntries)
            name: {
              'type': 'fragment',
              'file': File(
                (manifest[name] as Map<String, dynamic>)['file'] as String,
              ).absolute.path,
            },
        };
        final output = File.fromUri(temp.uri.resolve('lit.shaderbundle'));
        final shaders = Directory.current.uri.resolve('shaders/');
        final result = await Process.run(
          impellerc.toFilePath(),
          shaderBundleImpellercArguments(
            outputBundleFilePath: output.uri,
            manifestJson: jsonEncode(entries),
            manifestDirectory: shaders,
            shaderLibDirectory: impellerc.resolve('./shader_lib/'),
            includeDirectories: [shaders],
            glesLanguageVersion: engineGlesLanguageVersion,
          ),
        );
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        return {
          for (final shader
              in fb.ShaderBundle(output.readAsBytesSync()).shaders ??
                  const <fb.Shader>[])
            shader.name!: utf8.decode(
              shader.openglEs!.shader!,
              allowMalformed: true,
            ),
        };
      } finally {
        temp.deleteSync(recursive: true);
      }
    }

    test('read no texture at an implicit LOD inside a loop', () async {
      final sources = await (compiled ??= compile());
      for (final name in _litEntries) {
        expect(
          implicitLodReadsInLoops(sources[name]!),
          isEmpty,
          reason:
              '$name reads a texture at an implicit LOD inside a loop. Read '
              'it with textureLod or textureGrad, or give the enclosing '
              'function a single return.',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('take no derivative inside a loop', () async {
      final sources = await (compiled ??= compile());
      for (final name in _litEntries) {
        expect(
          derivativesInLoops(sources[name]!),
          isEmpty,
          reason:
              '$name takes a derivative inside a loop, which ANGLE writes as '
              '0.0. Give the enclosing function a single return.',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 10)));

    test(
      'sample the directional cascades from one copy of the sampler',
      () async {
        final sources = await (compiled ??= compile());
        // One copy of SampleCascade reads the shadow atlas about 30 times (the
        // blocker search, the probes, the bilinear taps and the kernel loop's
        // one tap). The spot and point shadows of the full entries add a few
        // more. Four inlined copies read it more than 100 times.
        final atlasRead = RegExp(r'textureLod\(shadow_map\b');
        for (final name in ['StandardFragment', 'StandardLeanFragment']) {
          expect(
            atlasRead.allMatches(sources[name]!).length,
            lessThan(60),
            reason: '$name inlines the cascade sampler more than once.',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
