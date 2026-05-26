import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

import 'fmat.dart';

/// The framework GLSL files (in flutter_scene's `shaders/` directory) that a
/// generated material shader can `#include`. Declared as build dependencies so
/// editing one retriggers a consumer's material build. Transitive `#include`s
/// inside these are not tracked until `impellerc --depfile` is consumed in
/// `--shader-bundle` mode (bdero/flutter_gpu_shaders#15).
const _frameworkShaderFiles = <String>[
  'material_varyings.glsl',
  'pbr.glsl',
  'texture.glsl',
  'normals.glsl',
  'material_inputs.glsl',
  'material_engine_lighting.glsl',
  'material_lighting.glsl',
];

/// Compiles `.fmat` custom-material files into a Flutter GPU shader bundle plus
/// a parameter-metadata sidecar, for use with `ShaderMaterial` /
/// `PreprocessedMaterial` at runtime.
///
/// Call this from a consuming app's `hook/build.dart`, alongside
/// [buildModels] and `buildShaderBundleJson`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     await buildMaterials(
///       buildInput: config,
///       buildOutput: output,
///       materials: ['materials/toon.fmat'],
///     );
///   });
/// }
/// ```
///
/// Each path in [materials] is resolved relative to the package root. The
/// produced bundle is written to `build/shaderbundles/[bundleName].shaderbundle`
/// (one fragment entry per material, named by the material's `name`), and the
/// combined parameter sidecar to
/// `build/shaderbundles/[bundleName].fmat.json`. List both as assets in the
/// app's pubspec.
///
/// The generated shaders `#include` flutter_scene's framework GLSL; this hook
/// puts flutter_scene's `shaders/` directory on `impellerc`'s include path (via
/// `buildShaderBundleJson`'s `includeDirectories`), so no framework files are
/// copied into the consumer's project.
Future<void> buildMaterials({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required List<String> materials,
  String bundleName = 'materials',
}) async {
  final packageRoot = buildInput.packageRoot;

  // Locate flutter_scene's framework shader directory. flutter_scene has no
  // top-level `flutter_scene.dart` library, so resolve through this package's
  // `build_hooks.dart` (which always exists) and hop to the sibling `shaders/`.
  final frameworkLib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/build_hooks.dart'),
  );
  if (frameworkLib == null) {
    throw Exception(
      'buildMaterials could not resolve the flutter_scene package location.',
    );
  }
  final frameworkShaders = frameworkLib.resolve('../shaders/');

  // Generated GLSL and the synthesized manifest live under the package's build
  // directory; they are regenerated each run.
  final generatedDir = Directory.fromUri(
    packageRoot.resolve('build/fmat/$bundleName/'),
  );
  generatedDir.createSync(recursive: true);

  final manifest = <String, Object?>{};
  final sidecars = <String, Object?>{};
  final sourceDependencies = <Uri>[];

  for (final materialPath in materials) {
    if (!materialPath.endsWith('.fmat')) {
      throw Exception('Material files must end with ".fmat": $materialPath');
    }
    final materialUri = packageRoot.resolve(materialPath);
    final source = File(materialUri.toFilePath()).readAsStringSync();
    final compiled = compileFmat(source, fileName: materialPath);
    final entryName = compiled.material.name;

    if (manifest.containsKey(entryName)) {
      throw Exception(
        'Two materials in bundle "$bundleName" share the name "$entryName"; '
        'material names must be unique within a bundle.',
      );
    }

    final fragFileName = '$entryName.frag';
    File(
      generatedDir.uri.resolve(fragFileName).toFilePath(),
    ).writeAsStringSync(compiled.glsl);

    manifest[entryName] = <String, Object?>{
      'type': 'fragment',
      // impellerc resolves a bundle entry's `file` relative to the package
      // root (its working directory), so reference the generated shader from
      // there, not relative to the manifest.
      'file': 'build/fmat/$bundleName/$fragFileName',
    };
    sidecars[entryName] = compiled.sidecar;
    sourceDependencies.add(materialUri);
  }

  // Write the synthesized shader-bundle manifest next to the generated shaders,
  // so its `file` entries resolve relative to it.
  final manifestRelativePath =
      'build/fmat/$bundleName/$bundleName.shaderbundle.json';
  File(
    packageRoot.resolve(manifestRelativePath).toFilePath(),
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

  // Compile, with flutter_scene's shaders/ on the include path so the generated
  // shaders' framework `#include`s resolve directly (no copies).
  await buildShaderBundleJson(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifestFileName: manifestRelativePath,
    includeDirectories: [frameworkShaders],
  );

  // Write the combined parameter sidecar next to the produced bundle.
  File(
    packageRoot
        .resolve('build/shaderbundles/$bundleName.fmat.json')
        .toFilePath(),
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sidecars));

  // Declare the real inputs as dependencies. buildShaderBundleJson declares the
  // (generated) .frag files; the sources that actually drive a rebuild are the
  // .fmat files and the framework GLSL they include.
  buildOutput.dependencies.addAll(sourceDependencies);
  buildOutput.dependencies.addAll(
    _frameworkShaderFiles.map(frameworkShaders.resolve),
  );
}
