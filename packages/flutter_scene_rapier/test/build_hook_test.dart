// Verifies that hook/build.dart produces a CodeAsset that points at a
// real library file, both for the host OS and for an iOS cross-build.
// Uses code_assets's testCodeBuildHook so the assertions run without a
// full Flutter app context.
//
// The hook invokes cargo, so these tests require a working Rust
// toolchain on PATH; they are skipped when `cargo` is not found. The
// iOS test additionally requires an Xcode toolchain and so only runs on
// a macOS host.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  test('build hook emits a code asset for the host OS', () async {
    if (!_haveCargo()) {
      return;
    }

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      check: (input, output) {
        final assets = output.assets.code;
        expect(assets, hasLength(1));
        final asset = assets.single;
        expect(
          asset.id,
          'package:flutter_scene_rapier/flutter_scene_rapier_native',
        );
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(File.fromUri(asset.file!).existsSync(), isTrue);
      },
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('build hook cross-builds an iOS device code asset', () async {
    if (!_haveCargo() || !Platform.isMacOS) {
      return;
    }

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.iOS,
      targetArchitecture: Architecture.arm64,
      targetIOSSdk: IOSSdk.iPhoneOS,
      check: (input, output) {
        final assets = output.assets.code;
        expect(assets, hasLength(1));
        final asset = assets.single;
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        final file = File.fromUri(asset.file!);
        expect(file.existsSync(), isTrue);
        // The emitted library must come from the iOS device target dir,
        // not the host build, so a Mach-O for the device gets bundled.
        expect(file.path, contains('aarch64-apple-ios'));
      },
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('build hook cross-builds an Android arm64 code asset', () async {
    final ndkClang = _findAndroidNdkClang();
    if (!_haveCargo() || ndkClang == null) {
      return;
    }

    final binDir = File(ndkClang).parent;
    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      targetAndroidNdkApi: 30,
      // The hook links with cCompiler.compiler; the linker / archiver
      // are required by the config but unused on the Android path.
      cCompiler: CCompilerConfig(
        compiler: Uri.file(ndkClang),
        linker: Uri.file(ndkClang),
        archiver: Uri.file('${binDir.path}/llvm-ar'),
      ),
      check: (input, output) {
        final assets = output.assets.code;
        expect(assets, hasLength(1));
        final asset = assets.single;
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        final file = File.fromUri(asset.file!);
        expect(file.existsSync(), isTrue);
        expect(file.path, contains('aarch64-linux-android'));
      },
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}

bool _haveCargo() {
  try {
    final result = Process.runSync('cargo', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

// Locates an Android NDK clang on this machine, or null if none is found
// (the Android cross-build test then skips). Checks the NDK environment
// variables, then versioned `ndk/` directories under the usual SDK roots.
String? _findAndroidNdkClang() {
  final env = Platform.environment;

  for (final root in [
    env['ANDROID_NDK_HOME'],
    env['ANDROID_NDK_ROOT'],
    env['ANDROID_NDK_LATEST_HOME'],
  ]) {
    if (root == null) continue;
    final clang = _clangUnderNdk(Directory(root));
    if (clang != null) return clang;
  }

  final sdkRoots = <String>[
    if (env['ANDROID_SDK_ROOT'] != null) env['ANDROID_SDK_ROOT']!,
    if (env['ANDROID_SDK_ROOT'] != null) '${env['ANDROID_SDK_ROOT']}/sdk',
    if (env['ANDROID_HOME'] != null) env['ANDROID_HOME']!,
    if (env['HOME'] != null) '${env['HOME']}/Library/Android/sdk',
  ];
  for (final sdkRoot in sdkRoots) {
    final ndkDir = Directory('$sdkRoot/ndk');
    if (!ndkDir.existsSync()) continue;
    final versions = ndkDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final version in versions) {
      final clang = _clangUnderNdk(version);
      if (clang != null) return clang;
    }
  }
  return null;
}

// Returns <ndk>/toolchains/llvm/prebuilt/<host>/bin/clang if it exists.
String? _clangUnderNdk(Directory ndk) {
  final prebuilt = Directory('${ndk.path}/toolchains/llvm/prebuilt');
  if (!prebuilt.existsSync()) return null;
  for (final host in prebuilt.listSync().whereType<Directory>()) {
    final clang = File('${host.path}/bin/clang');
    if (clang.existsSync()) return clang.path;
  }
  return null;
}
