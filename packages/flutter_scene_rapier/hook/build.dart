// Build hook for flutter_scene_rapier.
//
// Invoked by the Flutter SDK before a build to materialize the
// flutter_scene_rapier_native dynamic library. Runs `cargo build
// --release` in the package's native/ directory and registers the
// resulting library as a code asset so it gets bundled with the host
// app and loaded at runtime by the FFI bindings.
//
// TODO(cross-compile): this hook only builds for the host OS today.
// Add the matching Rust target triples for iOS (aarch64-apple-ios,
// aarch64-apple-ios-sim, x86_64-apple-ios), Android (aarch64-,
// armv7-, x86_64-linux-android), Windows MSVC, and the Linux variants
// so cross-OS builds work too. Each platform also needs its own
// SDK / NDK / MSVC setup wired through the cargo invocation, plus the
// `rustup target add <triple>` precondition handled or documented.

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
      '($hostOS). Cross-compilation to ${code.targetOS} is not yet wired '
      'up; see the TODO at the top of this file.',
    );
  }

  final triple = _rustTriple(code.targetOS, code.targetArchitecture);
  if (triple == null) {
    throw UnimplementedError(
      'No Rust target triple is wired up for '
      '${code.targetOS}/${code.targetArchitecture}. Add it to '
      'hook/build.dart and install the matching `rustup target add` first.',
    );
  }

  final nativeDir = Directory.fromUri(input.packageRoot.resolve('native/'));
  await _runCargo(nativeDir, triple);

  final libFileName = code.targetOS.dylibFileName(_nativeLibraryName);
  final libUri = input.packageRoot.resolve(
    'native/target/$triple/release/$libFileName',
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

Future<void> _runCargo(Directory nativeDir, String targetTriple) async {
  final result = await Process.run('cargo', [
    'build',
    '--release',
    '--target',
    targetTriple,
  ], workingDirectory: nativeDir.path);
  if (result.exitCode != 0) {
    throw Exception(
      'cargo build --target $targetTriple failed (${result.exitCode}) in '
      '${nativeDir.path}:\n${result.stdout}\n${result.stderr}',
    );
  }
}

// Maps a (targetOS, targetArchitecture) to the matching Rust target
// triple. Only host-OS combinations are populated for now; see the
// TODO at the top of this file for the cross-platform matrix.
String? _rustTriple(OS os, Architecture arch) {
  if (os == OS.macOS) {
    if (arch == Architecture.arm64) return 'aarch64-apple-darwin';
    if (arch == Architecture.x64) return 'x86_64-apple-darwin';
  }
  if (os == OS.linux) {
    if (arch == Architecture.x64) return 'x86_64-unknown-linux-gnu';
    if (arch == Architecture.arm64) return 'aarch64-unknown-linux-gnu';
  }
  if (os == OS.windows) {
    if (arch == Architecture.x64) return 'x86_64-pc-windows-msvc';
  }
  return null;
}
