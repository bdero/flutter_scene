// Build hook for flutter_scene_rapier.
//
// Invoked by the Flutter SDK before a build to materialize the
// flutter_scene_rapier_native dynamic library and register it as a code
// asset so it gets bundled with the app and loaded at runtime by the FFI
// bindings.
//
// The library is obtained one of two ways, in this order:
//
//   1. Prebuilt download. If native_binaries.json lists the target's
//      Rust triple, the matching library is downloaded from the package's
//      release, checksum-verified, cached, and emitted. Consumers do not
//      need a Rust toolchain on this path.
//   2. Build from source. Otherwise (no manifest entry for the triple, or
//      FLUTTER_SCENE_RAPIER_BUILD_FROM_SOURCE is set) `cargo build
//      --release` is run for the target's triple. This is the path for
//      developing the shim and for targets without a prebuilt.
//
// The same dynamic-loading code asset is emitted for every platform: the
// SDK does not yet support static linking of code assets, so even iOS
// ships the cdylib (bundled into a framework by the SDK).
//
// Environment overrides:
//   FLUTTER_SCENE_RAPIER_BUILD_FROM_SOURCE=1  force a source build
//   FLUTTER_SCENE_RAPIER_PREBUILT_BASE_URL=<url>  override the manifest's
//       download base URL (for mirrors or local testing)

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_scene_rapier/src/prebuilt_binaries.dart';
import 'package:hooks/hooks.dart';

const _nativeLibraryName = 'flutter_scene_rapier_native';
const _buildFromSourceEnv = 'FLUTTER_SCENE_RAPIER_BUILD_FROM_SOURCE';
const _baseUrlOverrideEnv = 'FLUTTER_SCENE_RAPIER_PREBUILT_BASE_URL';

Future<void> main(List<String> args) async {
  await build(args, _build);
}

Future<void> _build(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) return;

  final code = input.config.code;
  final triple = _rustTriple(code);
  if (triple == null) {
    throw UnimplementedError(
      'No Rust target triple is wired up for '
      '${code.targetOS}/${code.targetArchitecture}. Add it to '
      '_rustTriple in hook/build.dart.',
    );
  }

  final libUri = await _resolveLibrary(input, code, triple, output);

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _nativeLibraryName,
      linkMode: DynamicLoadingBundled(),
      file: libUri,
    ),
  );
}

// Returns the URI of the library to bundle, preferring a verified
// prebuilt download and falling back to a source build. Also records the
// hook's dependencies so it re-runs when its inputs change.
Future<Uri> _resolveLibrary(
  BuildInput input,
  CodeConfig code,
  String triple,
  BuildOutputBuilder output,
) async {
  final forceSource = Platform.environment[_buildFromSourceEnv] == '1';

  final manifestFile = File.fromUri(
    input.packageRoot.resolve('native_binaries.json'),
  );

  if (!forceSource && manifestFile.existsSync()) {
    output.dependencies.add(manifestFile.uri);
    final manifest = NativeBinaryManifest.fromFile(manifestFile)!;
    final entry = manifest.binaries[triple];
    if (entry != null) {
      return _downloadPrebuilt(input, manifest, entry, triple);
    }
    // No prebuilt for this triple (exotic arch / custom embedder): fall
    // through to a source build below.
  }

  // Source build: depend on the native sources so edits trigger a rebuild.
  output.dependencies.addAll([
    input.packageRoot.resolve('native/Cargo.toml'),
    input.packageRoot.resolve('native/Cargo.lock'),
    input.packageRoot.resolve('native/src/lib.rs'),
  ]);
  return _buildFromSource(input, code, triple);
}

// ---------------------------------------------------------------------------
// Prebuilt download
// ---------------------------------------------------------------------------

Future<Uri> _downloadPrebuilt(
  BuildInput input,
  NativeBinaryManifest manifest,
  NativeBinaryEntry entry,
  String triple,
) async {
  final baseUrl = Platform.environment[_baseUrlOverrideEnv] ?? manifest.baseUrl;
  final url = Uri.parse('$baseUrl/${manifest.tag}/${entry.file}');

  // Cache one file per version+triple in the shared output directory so
  // repeated builds reuse it.
  final cacheFile = File.fromUri(
    input.outputDirectoryShared.resolve(
      '$_nativeLibraryName/${manifest.version}/$triple/${entry.file}',
    ),
  );

  final library = await downloadVerifiedBinary(
    url: url,
    expectedSha256: entry.sha256,
    cacheFile: cacheFile,
    label: '$_nativeLibraryName ($triple)',
  );
  return library.uri;
}

// ---------------------------------------------------------------------------
// Source build
// ---------------------------------------------------------------------------

Future<Uri> _buildFromSource(
  BuildInput input,
  CodeConfig code,
  String triple,
) async {
  await _ensureRustTarget(triple);

  final nativeDir = Directory.fromUri(input.packageRoot.resolve('native/'));
  final environment = _cargoEnvironment(code, triple);
  await _runCargo(nativeDir, triple, environment);

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
  return libUri;
}

Future<void> _runCargo(
  Directory nativeDir,
  String targetTriple,
  Map<String, String> environment,
) async {
  final result = await Process.run(
    'cargo',
    ['build', '--release', '--target', targetTriple],
    workingDirectory: nativeDir.path,
    environment: environment,
  );
  if (result.exitCode != 0) {
    throw Exception(
      'cargo build --target $targetTriple failed (${result.exitCode}) in '
      '${nativeDir.path}:\n${result.stdout}\n${result.stderr}',
    );
  }
}

// Makes sure the Rust standard library for [triple] is installed. The
// build fails with a clear "can't find crate for `std`" otherwise. This
// is a no-op (and instant) when the target is already present. Tolerates
// a missing rustup: if rustup is not on PATH the target may still be
// installed through another channel, so let the cargo build surface the
// real error instead of failing here.
Future<void> _ensureRustTarget(String triple) async {
  try {
    final installed = await Process.run('rustup', [
      'target',
      'list',
      '--installed',
    ]);
    if (installed.exitCode == 0 &&
        (installed.stdout as String).split('\n').contains(triple)) {
      return;
    }
    await Process.run('rustup', ['target', 'add', triple]);
  } on ProcessException {
    // rustup is not available; assume the target is provided some other
    // way and let `cargo build` report a precise error if it is not.
  }
}

// Builds the extra environment variables cargo needs for the target.
// The parent environment is inherited; these entries are layered on top.
Map<String, String> _cargoEnvironment(CodeConfig code, String triple) {
  final environment = <String, String>{};

  if (code.targetOS == OS.iOS) {
    // rustc selects the iphoneos / iphonesimulator SDK from the triple
    // and resolves clang through xcrun; only the deployment target needs
    // to be forwarded.
    environment['IPHONEOS_DEPLOYMENT_TARGET'] = '${code.iOS.targetVersion}';
  } else if (code.targetOS == OS.macOS) {
    environment['MACOSX_DEPLOYMENT_TARGET'] = '${code.macOS.targetVersion}';
  } else if (code.targetOS == OS.android) {
    // Link with the NDK's clang driver (it locates its own sysroot), and
    // tell it the ABI and API level through the clang target triple. The
    // SDK supplies the NDK toolchain paths in code.cCompiler.
    final compiler = code.cCompiler?.compiler;
    if (compiler == null) {
      throw Exception(
        'Building flutter_scene_rapier_native for Android requires an NDK '
        'C compiler in the build config (code.cCompiler), but none was '
        'provided.',
      );
    }
    final api = code.android.targetNdkApi;
    final cargoTriple = triple.toUpperCase().replaceAll('-', '_');
    environment['CARGO_TARGET_${cargoTriple}_LINKER'] = compiler.toFilePath();
    // Align ELF load segments to 16 KB so the library loads on devices with
    // 16 KB memory pages (Android 15+; required on Pixel 8 and newer, and
    // for Play uploads). The Rust/NDK default is 4 KB, which the loader
    // rejects on those devices ("ELF alignment check failed").
    environment['CARGO_TARGET_${cargoTriple}_RUSTFLAGS'] =
        '-Clink-arg=--target=${_androidClangTarget(triple)}$api '
        '-Clink-arg=-Wl,-z,max-page-size=16384';
    // TODO(android-cc-crate): rapier3d and its dependencies are pure Rust
    // today, so only the final link needs the NDK. If a dependency ever
    // pulls in a C build (a build.rs using the cc crate), also set
    // CC_$triple / AR_$triple / CXX_$triple to the NDK clang / llvm-ar so
    // those compile steps target Android too.
  }

  return environment;
}

// The clang `--target` ABI string for an Android Rust triple. It matches
// the Rust triple except for 32-bit ARM, where clang spells it
// `armv7a-linux-androideabi`.
String _androidClangTarget(String rustTriple) {
  if (rustTriple == 'armv7-linux-androideabi') {
    return 'armv7a-linux-androideabi';
  }
  return rustTriple;
}

// Maps the target (OS, architecture, and for iOS the device/simulator
// SDK) to its Rust target triple, or null when the combination is not
// supported.
String? _rustTriple(CodeConfig code) {
  final arch = code.targetArchitecture;
  if (code.targetOS == OS.macOS) {
    if (arch == Architecture.arm64) return 'aarch64-apple-darwin';
    if (arch == Architecture.x64) return 'x86_64-apple-darwin';
  }
  if (code.targetOS == OS.iOS) {
    if (code.iOS.targetSdk == IOSSdk.iPhoneOS) {
      // Devices are always arm64.
      return 'aarch64-apple-ios';
    }
    // Simulator.
    if (arch == Architecture.arm64) return 'aarch64-apple-ios-sim';
    if (arch == Architecture.x64) return 'x86_64-apple-ios';
  }
  if (code.targetOS == OS.android) {
    if (arch == Architecture.arm64) return 'aarch64-linux-android';
    if (arch == Architecture.arm) return 'armv7-linux-androideabi';
    if (arch == Architecture.x64) return 'x86_64-linux-android';
    if (arch == Architecture.ia32) return 'i686-linux-android';
  }
  if (code.targetOS == OS.linux) {
    if (arch == Architecture.x64) return 'x86_64-unknown-linux-gnu';
    if (arch == Architecture.arm64) return 'aarch64-unknown-linux-gnu';
  }
  if (code.targetOS == OS.windows) {
    if (arch == Architecture.x64) return 'x86_64-pc-windows-msvc';
    if (arch == Architecture.arm64) return 'aarch64-pc-windows-msvc';
  }
  return null;
}
