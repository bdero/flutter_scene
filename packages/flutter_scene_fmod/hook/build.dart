// Build hook for flutter_scene_fmod.
//
// FMOD's license does not permit redistributing the SDK, so unlike the
// other native backends nothing is downloaded or compiled here. When
// FMOD_SDK_PATH points at a user-downloaded FMOD Engine SDK, the core
// and studio dynamic libraries are bundled with the app as code assets;
// otherwise the hook is a no-op and the runtime falls back to its
// environment-based library search (see lib/src/ffi/fmod_library.dart).
//
// TODO(audio): wire the bundled assets to the runtime lookups (@Native
// asset ids) and add the mobile layouts (iOS xcframework, Android
// per-ABI .so) once verified against a real SDK.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _sdkPathEnv = 'FMOD_SDK_PATH';

Future<void> main(List<String> args) async {
  await build(args, _build);
}

Future<void> _build(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) return;

  final sdkRoot = Platform.environment[_sdkPathEnv];
  if (sdkRoot == null) return;

  final code = input.config.code;
  final libraries = _sdkLibraries(sdkRoot, code);
  if (libraries == null) return;

  for (final (name, path) in libraries) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        '$_sdkPathEnv is set but $path does not exist. Expected an '
        'extracted FMOD Engine SDK (the directory containing api/).',
      );
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: name,
        linkMode: DynamicLoadingBundled(),
        file: file.uri,
      ),
    );
  }
}

// (asset name, library path) pairs for the target, or null when the
// target's SDK layout is not wired up yet.
List<(String, String)>? _sdkLibraries(String sdkRoot, CodeConfig code) {
  switch (code.targetOS) {
    case OS.macOS:
      return [
        ('fmod', '$sdkRoot/api/core/lib/libfmod.dylib'),
        ('fmodstudio', '$sdkRoot/api/studio/lib/libfmodstudio.dylib'),
      ];
    case OS.windows:
      return [
        ('fmod', '$sdkRoot/api/core/lib/x64/fmod.dll'),
        ('fmodstudio', '$sdkRoot/api/studio/lib/x64/fmodstudio.dll'),
      ];
    case OS.linux:
      final arch = code.targetArchitecture == Architecture.arm64
          ? 'arm64'
          : 'x86_64';
      return [
        ('fmod', '$sdkRoot/api/core/lib/$arch/libfmod.so'),
        ('fmodstudio', '$sdkRoot/api/studio/lib/$arch/libfmodstudio.so'),
      ];
    default:
      return null;
  }
}
