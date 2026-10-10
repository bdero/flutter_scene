// Builds the WGSL sidecar for an untrimmed shader bundle with a local
// flutter_scene_tint, the same code path the build hook runs, and checks every
// translated texture declaration against the sample-type reader.
//
//   dart tool/build_wgsl_sidecar.dart <bundle> <flutter_scene_tint> [out.json]
//
// Fails if any shader does not translate, if a binding disagrees with the
// predicted layout, or if a texture declaration has a shape the WebGPU backend
// cannot lay out.
//
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene/src/generated_assets/wgsl_sidecar.dart';
import 'package:flutter_scene/src/gpu/shared/gpu_sample_types.dart';
import 'package:flutter_scene/src/gpu/shared/wgsl_bindings.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: build_wgsl_sidecar.dart <bundle> <flutter_scene_tint> [out.json]',
    );
    exit(64);
  }
  final bundle = File(args[0]).readAsBytesSync();
  final version = Process.runSync(args[1], ['--version']);
  final translator = TintProcessTranslator(
    args[1],
    (version.stdout as String).trim(),
  );

  final watch = Stopwatch()..start();
  final String json;
  try {
    json = await buildWgslSidecar(
      bundle,
      translator,
      shippedBundleHash: 'unshipped',
    );
  } on WgslSidecarException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
  final elapsed = watch.elapsedMilliseconds;

  final shaders = (jsonDecode(json) as Map)['shaders'] as Map;
  final textureTypes = <String, int>{};
  final unreadable = <String>[];
  var bytes = 0;
  for (final MapEntry(:key, :value) in shaders.entries) {
    final wgsl = (value as Map)['wgsl'] as String;
    bytes += wgsl.length;
    for (final d in parseWgslDeclarations(wgsl)) {
      if (d.kind != WgslDeclarationKind.texture) continue;
      textureTypes[d.type] = (textureTypes[d.type] ?? 0) + 1;
      if (wgslTextureShape(d.type) == null) unreadable.add('$key: ${d.type}');
    }
  }
  stdout.writeln(
    'translated ${shaders.length} shaders in ${elapsed}ms, '
    '${(bytes / 1024).toStringAsFixed(0)} KiB of WGSL, bindings verified',
  );
  stdout.writeln('texture declarations: $textureTypes');
  if (args.length > 2) File(args[2]).writeAsStringSync(json);
  if (unreadable.isNotEmpty) {
    stderr.writeln('unreadable texture shapes:\n${unreadable.join('\n')}');
    exit(1);
  }
}
