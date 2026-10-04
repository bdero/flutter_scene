// Verifies the WgslBindingMap predictor against real Tint output.
//
//   dart tool/verify_wgsl_bindings.dart <bundle> <wgslDir>
//
// <wgslDir> holds `<index>_<name>.wgsl` produced by running tint over the
// bundle's Vulkan SPIR-V (see tool/dump_bundle_reflection.dart).
import 'dart:io';

import 'package:flutter_scene/src/gpu/shared/wgsl_bindings.dart';
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: verify_wgsl_bindings.dart <bundle> <wgslDir>');
    exit(64);
  }
  final bundle = fb.ShaderBundle(File(args[0]).readAsBytesSync());
  final dir = Directory(args[1]);

  var checked = 0, skipped = 0, failed = 0;
  final shaders = bundle.shaders ?? const [];
  for (var i = 0; i < shaders.length; i++) {
    final s = shaders[i];
    final v = s.vulkan;
    if (v == null) continue;
    final safe = (s.name ?? 'unnamed').replaceAll(
      RegExp(r'[^A-Za-z0-9_]'),
      '_',
    );
    final wgslFile = File('${dir.path}/${i}_$safe.wgsl');
    if (!wgslFile.existsSync()) {
      skipped++;
      continue;
    }

    final resources = <WgslReflectedResource>[
      for (final u in v.uniformStructs ?? const [])
        (
          name: u.name ?? '',
          binding: u.binding,
          kind: WgslResourceKind.uniformBuffer,
        ),
      for (final t in v.uniformTextures ?? const [])
        (
          name: t.name ?? '',
          binding: t.binding,
          kind: WgslResourceKind.combinedTextureSampler,
        ),
    ];

    try {
      WgslBindingMap.predict(
        resources,
      ).verifyAgainstWgsl(wgslFile.readAsStringSync(), shaderName: s.name);
      checked++;
    } on WgslBindingMismatch catch (e) {
      failed++;
      stderr.writeln('[$i] ${s.name}: $e');
    }
  }

  stdout.writeln('verified=$checked failed=$failed skipped=$skipped');
  exit(failed == 0 ? 0 : 1);
}
