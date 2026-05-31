// Verifies that hook/build.dart produces a CodeAsset that points at a
// real file. Uses code_assets's testCodeBuildHook so the assertion
// runs without a full Flutter app context.
//
// The hook invokes cargo, so this test requires a working Rust
// toolchain on PATH; it is skipped when `cargo` is not found.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  test(
    'build hook emits a code asset for the host OS',
    () async {
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
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

bool _haveCargo() {
  try {
    final result = Process.runSync('cargo', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
