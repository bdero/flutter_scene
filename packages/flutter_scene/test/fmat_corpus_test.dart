// Builds every `.fmat` in the workspace, plus the regression corpus under
// test/fmat_corpus/, into a real shader bundle the way the build hook does,
// and checks what each entry compiled to. Every material is also built with a
// depth-pass feature forced on (`alpha_to_coverage` when opaque,
// `effects_depth` when blended), so a change to how depth passes are emitted
// runs against every material's real hooks and helpers, not only the ones
// that opt in.
//
// A material as written must build every entry cleanly. A forced variant may
// fall back the way the build hook does, dropping depth passes that fail, but
// must still produce a clean bundle, since that is what an app would ship.
// Add the material from every fmat bug report to test/fmat_corpus/,
// minimized, so the corpus only grows.
@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/build.dart'
    show shaderBundleImpellercArguments;
import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/build_materials.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/depth_surface_fallback.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat_emitter.dart'
    show depthSurfaceEntryName, materialHasDepthSurface;
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/shader_bundle_lint.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/generated_assets/tint_binary.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/generated_assets/wgsl_sidecar.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every material builds and passes the bundle lint', () async {
    final impellerc = await findImpellerC();
    final translator = await _tintTranslator();
    final repo = Directory.current.uri.resolve('../../');
    final sources = _corpus(repo);
    expect(sources, isNotEmpty);

    final temp = Directory.systemTemp.createTempSync('fmat_corpus');
    final failures = <String>[];
    final fallbacks = <String>[];
    final jobs = <Future<void> Function()>[];
    var forced = 0;
    try {
      for (final MapEntry(key: path, value: source) in sources.entries) {
        final FmatCompilation original;
        try {
          original = compileFmat(source, fileName: path);
        } on FmatException catch (e) {
          failures.add('$path does not parse: $e');
          continue;
        }
        final variants = {path: (original, false)};
        final forcedSource = _withDepthFeature(source, original.material);
        if (forcedSource != null) {
          try {
            variants['$path (depth passes forced)'] = (
              compileFmat(forcedSource, fileName: path),
              true,
            );
            forced++;
          } on FmatException {
            // The forced flag is not valid for this material, which is fine.
          }
        }
        for (final MapEntry(key: label, value: (compiled, allowFallback))
            in variants.entries) {
          final dir = Directory.fromUri(temp.uri.resolve('${jobs.length}/'))
            ..createSync();
          jobs.add(
            () => _buildAndLint(
              label,
              compiled,
              dir,
              impellerc,
              translator,
              failures,
              fallbacks,
              allowFallback: allowFallback,
            ),
          );
        }
      }
      await _pool(jobs, Platform.numberOfProcessors);
    } finally {
      temp.deleteSync(recursive: true);
    }
    // ignore: avoid_print
    print(
      'fmat corpus: ${sources.length} materials, $forced forced variants, '
      '${jobs.length} bundles, ${fallbacks.length} fell back to engine depth '
      'passes${translator == null ? ', WGSL not checked' : ''}',
    );
    for (final fallback in fallbacks) {
      // ignore: avoid_print
      print('  fell back: $fallback');
    }
    expect(failures, isEmpty, reason: failures.join('\n\n'));
  });
}

/// Every `.fmat` the workspace ships or tests with, keyed by repo-relative
/// path.
Map<String, String> _corpus(Uri repo) {
  final roots = [
    'examples',
    'apps',
    'packages/flutter_scene/assets',
    'packages/flutter_scene/test/fmat_corpus',
  ];
  final found = <String, String>{};
  for (final root in roots) {
    final dir = Directory.fromUri(repo.resolve('$root/'));
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final path = file.path.substring(repo.toFilePath().length);
      if (!path.endsWith('.fmat') ||
          path.contains('/build/') ||
          path.contains('/.dart_tool/')) {
        continue;
      }
      found[path] = file.readAsStringSync();
    }
  }
  return Map.fromEntries(
    found.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// [source] with the depth-pass feature its blending allows switched on, or
/// null when it already has one or has no depth passes to force.
String? _withDepthFeature(String source, FmatMaterial material) {
  if (material.domain == FmatDomain.sky) return null;
  if (material.alphaToCoverage || material.effectsDepth) return null;
  final flag = material.blending == FmatBlending.opaque
      ? 'alpha_to_coverage: true,'
      : 'effects_depth: true,';
  final header = RegExp(r'material\s*\{');
  final match = header.firstMatch(source);
  if (match == null) return null;
  return source.replaceRange(match.end, match.end, '\n  $flag');
}

Future<void> _buildAndLint(
  String label,
  FmatCompilation compiled,
  Directory dir,
  Uri impellerc,
  WgslBatchTranslator? translator,
  List<String> failures,
  List<String> fallbacks, {
  required bool allowFallback,
}) async {
  final material = compiled.material;
  final lit = material.shadingModel != FmatShadingModel.unlit;
  final fragments = emitFragmentShaderVariants(
    compiled,
    generateShadowVariant: lit,
    generateLightmapVariant: lit,
  );
  final manifest = <String, Object?>{};
  final glsl = <String, String>{};
  void add(String entry, String type, String source) {
    final file = '$entry.${type == 'fragment' ? 'frag' : 'vert'}';
    File.fromUri(dir.uri.resolve(file)).writeAsStringSync(source);
    manifest[entry] = {'type': type, 'file': file};
    glsl[entry] = source;
  }

  fragments.forEach((entry, source) => add(entry, 'fragment', source));
  compiled.vertexGlsl.forEach((entry, source) => add(entry, 'vertex', source));
  final depthSurfaceOwners = {
    if (materialHasDepthSurface(material))
      for (final kind in DepthSurfaceKind.values)
        depthSurfaceEntryName(material, kind): material.name,
  };

  // Mirrors the build hook. A problem confined to the depth passes drops
  // them and rebuilds, which only a forced variant may do.
  final bundle = File.fromUri(dir.uri.resolve('out.shaderbundle'));
  var fellBack = false;
  while (true) {
    final String problem;
    final result = await Process.run(
      impellerc.toFilePath(),
      shaderBundleImpellercArguments(
        outputBundleFilePath: bundle.uri,
        manifestJson: jsonEncode(manifest),
        manifestDirectory: dir.uri,
        shaderLibDirectory: impellerc.resolve('./shader_lib'),
        includeDirectories: [Directory.current.uri.resolve('shaders/')],
        glesLanguageVersion: 300,
      ),
      workingDirectory: dir.path,
    );
    if (result.exitCode != 0) {
      problem =
          'does not build:\n'
          '${_firstErrors('${result.stderr}\n${result.stdout}')}';
    } else {
      final bytes = bundle.readAsBytesSync();
      final lint = lintShaderBundle(fb.ShaderBundle(bytes), glsl);
      String? wgsl;
      if (lint.isEmpty && translator != null) {
        try {
          await buildWgslSidecar(
            bytes,
            translator,
            shippedBundleHash: 'corpus',
          );
        } on WgslSidecarException catch (e) {
          wgsl = e.message;
        }
      }
      if (lint.isEmpty && wgsl == null) break;
      problem = lint.isNotEmpty
          ? 'fails the bundle lint:\n${describeLintProblems(lint)}'
          : 'fails the WGSL sidecar:\n$wgsl';
    }
    final depthOnly = materialsFailingOnlyInDepthPasses(
      problem,
      depthSurfaceOwners,
      manifest.keys.toSet(),
    );
    if (!allowFallback || fellBack || depthOnly == null) {
      failures.add('$label $problem');
      return;
    }
    depthSurfaceOwners.keys.forEach(manifest.remove);
    fellBack = true;
    fallbacks.add('$label, which ${problem.split('\n').first}');
  }
}

String _firstErrors(String log) {
  final errors = log
      .split('\n')
      .where((l) => l.contains('error') || l.contains('failed'))
      .take(4);
  return errors.isEmpty ? log.trim() : errors.join('\n');
}

/// The pinned `flutter_scene_tint` (or the one named by
/// `FLUTTER_SCENE_TINT`), or null on a host with no prebuilt binary.
Future<WgslBatchTranslator?> _tintTranslator() async {
  final override = Platform.environment[kTintEnv];
  final String binary;
  if (override != null && override.isNotEmpty) {
    binary = override;
  } else {
    if (tintHostKey() case final host? when kTintBinaries.containsKey(host)) {
      binary = await resolvePinnedTintBinary(
        Directory.current.uri.resolve('.dart_tool/flutter_scene_tint/'),
      );
    } else {
      return null;
    }
  }
  final version = await Process.run(binary, ['--version']);
  if (version.exitCode != 0) {
    throw StateError('$binary --version failed: ${version.stderr}');
  }
  return TintProcessTranslator(binary, (version.stdout as String).trim());
}

Future<void> _pool(List<Future<void> Function()> jobs, int width) async {
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      final job = jobs[next++];
      await job();
    }
  }

  await Future.wait([for (var i = 0; i < width; i++) worker()]);
}
