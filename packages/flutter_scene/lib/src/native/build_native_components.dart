/// Compiling a project's own C and C++ component sources at build time.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the project's native component sources into one bundled library
/// its Dart wrappers open over `dart:ffi`.
///
/// With no [sources], every `.c`, `.cc` and `.cpp` file under [discoveryRoot]
/// is compiled, so adding a second native component is a new file rather than
/// a build-hook edit.
///
/// The result is a single dynamic library named [libraryName]. One library
/// rather than one per source keeps the bundle small and means a wrapper can
/// call across its own sources; symbols are what separate components here,
/// not libraries.
///
/// Does nothing when the build is not producing code assets (an
/// assets-only pass, or a platform where the toolchain is unavailable), so a
/// project that gains a native component still builds everywhere its Dart
/// does.
///
/// ```dart
/// build(args, (input, output) async {
///   await buildNativeComponents(buildInput: input, buildOutput: output);
/// });
/// ```
/// {@category Assets and loading}
Future<void> buildNativeComponents({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? sources,
  String discoveryRoot = 'native/',
  String libraryName = 'native_components',
  List<String> includeDirectories = const [],
  Map<String, String?> defines = const {},
  bool cppStandardLibrary = true,
}) async {
  if (!buildInput.config.buildCodeAssets) return;

  final root = buildInput.packageRoot;
  final discovered =
      sources ?? _discoverSources(root.resolve(discoveryRoot).toFilePath());
  if (discovered.isEmpty) return;

  final builder = CBuilder.library(
    name: libraryName,
    assetName: libraryName,
    sources: [
      for (final source in discovered) root.resolve(source).toFilePath(),
    ],
    includes: [
      for (final include in includeDirectories)
        root.resolve(include).toFilePath(),
    ],
    defines: defines,
    // C++ sources need the standard library linked; a pure C component does
    // not, and linking it anyway is harmless but not free on every target.
    language: cppStandardLibrary && discovered.any(_isCpp)
        ? Language.cpp
        : Language.c,
  );

  await builder.run(input: buildInput, output: buildOutput, logger: null);
}

bool _isCpp(String path) =>
    path.endsWith('.cpp') || path.endsWith('.cc') || path.endsWith('.cxx');

/// Every C or C++ source directly under [directory], sorted so a build is
/// reproducible rather than filesystem-ordered.
List<String> _discoverSources(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return const [];
  final files = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    if (path.endsWith('.c') || _isCpp(path)) files.add(path);
  }
  files.sort();
  return files;
}
