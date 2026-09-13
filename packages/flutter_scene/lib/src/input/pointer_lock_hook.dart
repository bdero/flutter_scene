import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles `native/pointer_lock/` for desktop targets and registers it as the
/// code asset `pointer_lock_backend_native.dart` binds to.
///
/// A failed compile is logged and skipped rather than failing the app build;
/// `PointerLock.isSupported` then reports false.
Future<void> buildPointerLockLibrary(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  final targetOS = input.config.code.targetOS;
  const dir = 'native/pointer_lock/';
  final CBuilder builder;
  switch (targetOS) {
    case OS.macOS:
      builder = CBuilder.library(
        name: 'flutter_scene_pointer_lock',
        assetName: 'src/input/pointer_lock_backend_native.dart',
        sources: ['${dir}pointer_lock_macos.m'],
        language: Language.objectiveC,
        flags: ['-fobjc-arc'],
        frameworks: ['AppKit', 'CoreGraphics'],
      );
    case OS.windows:
      builder = CBuilder.library(
        name: 'flutter_scene_pointer_lock',
        assetName: 'src/input/pointer_lock_backend_native.dart',
        sources: ['${dir}pointer_lock_windows.c'],
        libraries: ['user32', 'comctl32'],
      );
    case OS.linux:
      builder = CBuilder.library(
        name: 'flutter_scene_pointer_lock',
        assetName: 'src/input/pointer_lock_backend_native.dart',
        sources: ['${dir}pointer_lock_linux.c'],
        libraries: ['dl'],
      );
    default:
      return;
  }
  final logger = Logger('flutter_scene.pointer_lock');
  try {
    await builder.run(input: input, output: output, logger: logger);
  } catch (error) {
    // TODO(pointer-lock): surface this as a build warning once hooks can
    // report one; today it only reaches verbose build logs.
    logger.warning(
      'Skipping pointer lock, its native library failed to build: $error',
    );
  }
}
