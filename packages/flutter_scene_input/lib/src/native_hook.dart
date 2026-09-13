import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// The code asset id every `@Native` binding in this package names.
const String nativeAssetName = 'native';

/// Compiles the package's native code (pointer lock on every desktop, the HID
/// gamepad tap on macOS) and registers it as one code asset.
///
/// A failed compile is logged and skipped rather than failing the app build;
/// `PointerLock.isSupported` and the HID fallback then report unavailable.
Future<void> buildNativeLibrary(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  final targetOS = input.config.code.targetOS;
  const dir = 'native/pointer_lock/';
  const hid = 'native/hid_gamepads/';
  final CBuilder builder;
  switch (targetOS) {
    case OS.macOS:
      builder = CBuilder.library(
        name: 'flutter_scene_input_native',
        assetName: nativeAssetName,
        sources: ['${dir}pointer_lock_macos.m', '${hid}hid_gamepads_macos.m'],
        language: Language.objectiveC,
        flags: ['-fobjc-arc'],
        frameworks: ['AppKit', 'CoreGraphics', 'IOKit'],
      );
    case OS.windows:
      builder = CBuilder.library(
        name: 'flutter_scene_input_native',
        assetName: nativeAssetName,
        sources: ['${dir}pointer_lock_windows.c'],
        libraries: ['user32', 'comctl32'],
      );
    case OS.linux:
      builder = CBuilder.library(
        name: 'flutter_scene_input_native',
        assetName: nativeAssetName,
        sources: ['${dir}pointer_lock_linux.c'],
        libraries: ['dl'],
      );
    default:
      return;
  }
  final logger = Logger('flutter_scene_input.native');
  try {
    await builder.run(input: input, output: output, logger: logger);
  } catch (error) {
    // TODO(pointer-lock): surface this as a build warning once hooks can
    // report one; today it only reaches verbose build logs.
    logger.warning(
      'Skipping native input (pointer lock, HID gamepads), the library failed to build: $error',
    );
  }
}
