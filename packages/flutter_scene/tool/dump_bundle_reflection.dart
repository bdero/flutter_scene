// Dumps a shader bundle's Vulkan-entry reflection so the WGSL binding
// correlation can be checked against ground truth.
//
//   dart tool/dump_bundle_reflection.dart <bundle> [outDir]
//
// With outDir, also writes each Vulkan SPIR-V payload as <index>_<name>.spv so
// the same index can be fed to tint and diffed against this reflection.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dump_bundle_reflection.dart <bundle> [outDir]');
    exit(64);
  }
  final bytes = File(args[0]).readAsBytesSync();
  final bundle = fb.ShaderBundle(bytes);
  final outDir = args.length > 1 ? Directory(args[1]) : null;
  outDir?.createSync(recursive: true);

  final shaders = bundle.shaders ?? const [];
  print('format_version=${bundle.formatVersion} shaders=${shaders.length}');
  for (var i = 0; i < shaders.length; i++) {
    final s = shaders[i];
    final v = s.vulkan;
    if (v == null) {
      print('[$i] ${s.name}: NO VULKAN ENTRY');
      continue;
    }
    print('[$i] ${s.name}  stage=${v.stage}  entry=${v.entrypoint}');
    for (final u in v.uniformStructs ?? const []) {
      print(
        '     ubo   name=${u.name} set=${u.extRes0} binding=${u.binding} '
        'size=${u.sizeInBytes}',
      );
    }
    for (final t in v.uniformTextures ?? const []) {
      print('     tex   name=${t.name} set=${t.extRes0} binding=${t.binding}');
    }
    if (outDir != null) {
      final spv = Uint8List.fromList(v.shader ?? const []);
      final safe = (s.name ?? 'unnamed').replaceAll(
        RegExp(r'[^A-Za-z0-9_]'),
        '_',
      );
      File('${outDir.path}/${i}_$safe.spv').writeAsBytesSync(spv);
    }
  }
}
