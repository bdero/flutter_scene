// Build hook for flutter_scene_rapier.
//
// Invoked by the Flutter SDK before a build to materialize the
// flutter_scene_rapier_native dynamic library. Runs `cargo build
// --release` in the package's native/ directory and registers the
// resulting library as a code asset so it gets bundled with the host
// app and loaded at runtime by the FFI bindings.
//
// Stage 3 scaffold limitation: this hook only builds for the host OS.
// Cross-compilation to other targets requires the matching Rust target
// triple to be installed via `rustup target add <triple>` and is
// wired in a later stage.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _nativeLibraryName = 'flutter_scene_rapier_native';

Future<void> main(List<String> args) async {
  await build(args, _build);
}

Future<void> _build(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) return;

  final code = input.config.code;
  final hostOS = OS.current;
  if (code.targetOS != hostOS) {
    throw UnimplementedError(
      'flutter_scene_rapier currently only builds for the host OS '
      '($hostOS). Cross-compilation to ${code.targetOS} lands in a future '
      'stage of the physics rollout.',
    );
  }

  final nativeDir = Directory.fromUri(input.packageRoot.resolve('native/'));
  await _runCargo(nativeDir);

  final libFileName = code.targetOS.dylibFileName(_nativeLibraryName);
  final libUri = input.packageRoot.resolve(
    'native/target/release/$libFileName',
  );
  final libFile = File.fromUri(libUri);
  if (!libFile.existsSync()) {
    throw Exception(
      'cargo build succeeded but ${libFile.path} is missing. Check that '
      'native/Cargo.toml lists "cdylib" in [lib].crate-type.',
    );
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _nativeLibraryName,
      linkMode: DynamicLoadingBundled(),
      file: libUri,
    ),
  );

  output.dependencies.addAll([
    input.packageRoot.resolve('native/Cargo.toml'),
    input.packageRoot.resolve('native/Cargo.lock'),
    input.packageRoot.resolve('native/src/lib.rs'),
  ]);
}

Future<void> _runCargo(Directory nativeDir) async {
  final result = await Process.run('cargo', [
    'build',
    '--release',
  ], workingDirectory: nativeDir.path);
  if (result.exitCode != 0) {
    throw Exception(
      'cargo build failed (${result.exitCode}) in ${nativeDir.path}:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}
