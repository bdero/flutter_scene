// Builds and packages a distributable Flutter Scene Editor for the current
// host platform.
//
// Run from the app directory with the plain Dart VM (no package deps):
//
//   dart tool/package_editor.dart --platform macos [--no-build]
//       [--sign-identity "Developer ID Application: ..."]
//       [--notarize-profile <notarytool keychain profile>]
//
// The packaged bundle carries the offline shader toolchain the editor needs
// to compile .fmat materials at runtime: the SDK's impellerc, its shader_lib
// includes, flutter_scene's framework GLSL, and a tool_manifest.json that
// records the Flutter revision everything was built from. macOS packages a
// release build (Info.plist enables Impeller + Flutter GPU). Linux and
// Windows package PROFILE builds behind a launcher that sets the engine
// switches, because release builds compile out the environment switch path
// and those embedders have no project-level Flutter GPU setting yet.
// TODO(editor-dist-release): switch Linux/Windows to release builds once the
// embedders can enable Flutter GPU without environment switches.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final options = _Options.parse(args);
  final appDir = File(Platform.script.toFilePath()).parent.parent.absolute.path;
  final version = _pubspecVersion('$appDir/pubspec.yaml');

  if (options.build) {
    _clearStaleProduct(appDir, options.platform);
    // The source is written in the 3.47 stable windowing names, which is what
    // flutter.version pins, so the build needs no patching. Working on the
    // master channel is the case that patches (tool/patches/
    // window_names_master.patch), and it must be reversed before packaging.
    _requireStableWindowingNames(appDir);
    _run('flutter', [
      'build',
      options.platform,
      options.platform == 'macos' ? '--release' : '--profile',
    ], cwd: appDir);
  }

  final bundle = _builtBundle(appDir, options.platform);
  final tools = _resolveTools(appDir);
  final manifest = _toolManifest();

  switch (options.platform) {
    case 'macos':
      _packageMacos(appDir, bundle, tools, manifest, version, options);
    case 'linux':
      _packagePosixBundle(appDir, bundle, tools, manifest, version, 'linux');
    case 'windows':
      _packageWindows(appDir, bundle, tools, manifest, version);
  }
}

final class _Options {
  _Options({
    required this.platform,
    required this.build,
    this.signIdentity,
    this.notarizeProfile,
    this.keychain,
  });

  final String platform;
  final bool build;
  final String? signIdentity;
  final String? notarizeProfile;

  /// A keychain to search for the signing identity, so signing does not depend
  /// on the default search list (which a build can reset). CI passes this.
  final String? keychain;

  static _Options parse(List<String> args) {
    String? platform;
    var build = true;
    String? signIdentity;
    String? notarizeProfile;
    String? keychain;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--platform':
          platform = args[++i];
        case '--no-build':
          build = false;
        case '--sign-identity':
          signIdentity = args[++i];
        case '--notarize-profile':
          notarizeProfile = args[++i];
        case '--keychain':
          keychain = args[++i];
        default:
          _fail('Unknown argument "${args[i]}"');
      }
    }
    if (!const {'macos', 'linux', 'windows'}.contains(platform)) {
      _fail('Pass --platform macos|linux|windows');
    }
    if (platform != Platform.operatingSystem &&
        !(platform == 'macos' && Platform.isMacOS)) {
      _fail('Cross-packaging is unsupported; run on a $platform host.');
    }
    return _Options(
      platform: platform!,
      build: build,
      signIdentity: signIdentity,
      notarizeProfile: notarizeProfile,
      keychain: keychain,
    );
  }
}

// Once Gatekeeper assesses a signed bundle, macOS stamps restricted
// com.apple.provenance xattrs on it that rsync cannot rewrite, so the next
// build fails copying into the stale bundle. Xcode reassembles the product
// from its cached objects, so dropping it costs a relink rather than a
// recompile.
void _clearStaleProduct(String appDir, String platform) {
  if (platform != 'macos') {
    return;
  }
  final products = Directory('$appDir/build/macos/Build/Products/Release');
  if (!products.existsSync()) {
    return;
  }
  for (final entity in products.listSync()) {
    if (entity is Directory && entity.path.endsWith('.app')) {
      stdout.writeln('- ${entity.path}');
      entity.deleteSync(recursive: true);
    }
  }
}

/// Refuses to package a tree still carrying the master windowing rename.
///
/// `window_names_master.patch` swaps the stable `RegularWindow*` names for
/// master's shorter ones so the editor builds on that channel. Packaging with
/// it applied would ship a binary built against names the pinned
/// `flutter.version` SDK does not have, which is a build failure at best and a
/// wrong-SDK release at worst, so the reversal is checked rather than trusted
/// to a comment.
void _requireStableWindowingNames(String appDir) {
  final repoRoot = Directory(appDir).parent.parent.path;
  const patched = {
    'apps/flutter_scene_editor_app/lib/main.dart': 'RegularWindowController(',
    'packages/flutter_scene_editor/lib/src/shell/docking_shell.dart':
        'RegularWindowController>',
  };
  for (final entry in patched.entries) {
    final file = File('$repoRoot/${entry.key}');
    if (!file.existsSync()) {
      _fail('Cannot verify windowing names, missing ${entry.key}');
    }
    if (!file.readAsStringSync().contains(entry.value)) {
      _fail(
        'The windowing API is in the master names in ${entry.key}, but the '
        'release builds against the stable revision pinned by '
        'flutter.version. Reverse tool/patches/window_names_master.patch '
        '(git apply -R) before packaging.',
      );
    }
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

String _pubspecVersion(String pubspecPath) {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File(pubspecPath).readAsStringSync());
  if (match == null) _fail('No version in $pubspecPath');
  return match[1]!;
}

ProcessResult _run(
  String executable,
  List<String> args, {
  String? cwd,
  bool check = true,
}) {
  stdout.writeln('+ $executable ${args.join(' ')}');
  final result = Process.runSync(executable, args, workingDirectory: cwd);
  if (check && result.exitCode != 0) {
    _fail('$executable failed:\n${result.stdout}\n${result.stderr}');
  }
  return result;
}

// The freshly built bundle for [platform]. The .app name and the Linux arch
// directory are discovered rather than assumed, so a rename or an arm64
// host does not break packaging.
String _builtBundle(String appDir, String platform) {
  String find(String parent, bool Function(FileSystemEntity) test) {
    final dir = Directory(parent);
    if (!dir.existsSync()) _fail('Missing build output $parent; build first.');
    final hit = dir.listSync().where(test).toList();
    if (hit.length != 1) {
      _fail('Expected one bundle under $parent, found ${hit.length}');
    }
    return hit.single.path;
  }

  switch (platform) {
    case 'macos':
      return find(
        '$appDir/build/macos/Build/Products/Release',
        (e) => e.path.endsWith('.app'),
      );
    case 'linux':
      final arch = find(
        '$appDir/build/linux',
        (e) => e is Directory,
      ).split('/').last;
      return '$appDir/build/linux/$arch/profile/bundle';
    case 'windows':
      final arch = find(
        '$appDir\\build\\windows',
        (e) => e is Directory,
      ).split(Platform.pathSeparator).last;
      return '$appDir\\build\\windows\\$arch\\runner\\Profile';
  }
  throw StateError('unreachable');
}

final class _Tools {
  _Tools({
    required this.impellerc,
    required this.shaderLib,
    required this.frameworkShaders,
  });

  final String impellerc;
  final String shaderLib;
  final String frameworkShaders;
}

// impellerc + shader_lib come from the running SDK's engine artifact cache
// (the same probe set flutter_gpu_shaders uses, honoring IMPELLERC);
// flutter_scene's shaders/ comes from the workspace checkout.
_Tools _resolveTools(String appDir) {
  final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';
  String? impellerc = Platform.environment['IMPELLERC'];
  if (impellerc != null && !File(impellerc).existsSync()) {
    _fail('IMPELLERC is set but does not exist: $impellerc');
  }
  if (impellerc == null) {
    // Platform.resolvedExecutable is <sdk>/bin/cache/dart-sdk/bin/dart when
    // run through the Flutter SDK's dart; walk back to the cache.
    final segments = File(
      Platform.resolvedExecutable,
    ).absolute.uri.pathSegments;
    final cutoff = segments.lastIndexOf('dart-sdk');
    if (cutoff > 0) {
      final cache = segments.sublist(0, cutoff).join('/');
      for (final host in const [
        'darwin-x64',
        'linux-x64',
        'linux-arm64',
        'windows-x64',
        'windows-arm64',
      ]) {
        final candidate = '/$cache/artifacts/engine/$host/$exeName';
        if (File(candidate).existsSync()) {
          impellerc = candidate;
          break;
        }
      }
    }
  }
  if (impellerc == null) {
    _fail(
      'impellerc not found; run through the Flutter SDK dart or set '
      'IMPELLERC.',
    );
  }
  final shaderLib = '${File(impellerc).parent.path}/shader_lib';
  final frameworkShaders = Directory(
    '$appDir/../../packages/flutter_scene/shaders',
  ).absolute.path;
  for (final required in [shaderLib, frameworkShaders]) {
    if (!Directory(required).existsSync()) _fail('Missing $required');
  }
  return _Tools(
    impellerc: impellerc,
    shaderLib: shaderLib,
    frameworkShaders: frameworkShaders,
  );
}

// Records the toolchain identity inside the bundle, read by the editor's
// diagnostics (and folded into its compile cache key).
String _toolManifest() {
  final result = _run('flutter', ['--version', '--machine']);
  final info = (jsonDecode(result.stdout as String) as Map)
      .cast<String, Object?>();
  return const JsonEncoder.withIndent('  ').convert({
    'flutterVersion': info['flutterVersion'],
    'frameworkRevision': info['frameworkRevision'],
    'engineRevision': info['engineRevision'],
    'dartSdkVersion': info['dartSdkVersion'],
  });
}

void _copyTree(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final entity in Directory(from).listSync(recursive: true)) {
    final relative = entity.path.substring(from.length + 1);
    if (entity is Directory) {
      Directory('$to/$relative').createSync(recursive: true);
    } else if (entity is File) {
      entity.copySync('$to/$relative');
    }
  }
}

void _installTools(
  String toolDir,
  String dataDir,
  _Tools tools,
  String manifest,
) {
  Directory(toolDir).createSync(recursive: true);
  final exeName = Platform.isWindows ? 'impellerc.exe' : 'impellerc';
  final installed = File(tools.impellerc).copySync('$toolDir/$exeName');
  if (!Platform.isWindows) {
    _run('chmod', ['+x', installed.path]);
  }
  _copyTree(tools.shaderLib, '$dataDir/shader_lib');
  _copyTree(tools.frameworkShaders, '$dataDir/flutter_scene_shaders');
  File('$dataDir/tool_manifest.json').writeAsStringSync(manifest);
}

String _distDir(String appDir) =>
    (Directory('$appDir/build/dist')..createSync(recursive: true)).path;

String _arch() {
  final version = Platform.version;
  if (version.contains('arm64')) return 'arm64';
  if (version.contains('x64')) return 'x64';
  return 'unknown';
}

void _printSha256(String path) {
  final result = Platform.isWindows
      ? _run('certutil', ['-hashfile', path, 'SHA256'])
      : _run(Platform.isMacOS ? 'shasum' : 'sha256sum', [
          if (Platform.isMacOS) ...['-a', '256'],
          path,
        ]);
  stdout.writeln(result.stdout);
  stdout.writeln('Packaged $path');
}

void _packageMacos(
  String appDir,
  String app,
  _Tools tools,
  String manifest,
  String version,
  _Options options,
) {
  _installTools(
    '$app/Contents/Helpers',
    '$app/Contents/Resources',
    tools,
    manifest,
  );

  final identity = options.signIdentity;
  // Pin codesign to a specific keychain when given one; the default search
  // list can be reset by the build before signing runs.
  final keychainArgs = options.keychain != null
      ? ['--keychain', options.keychain!]
      : const <String>[];
  if (identity != null) {
    // Inner executables first, then the bundle, with the hardened runtime
    // notarization requires.
    _run('codesign', [
      '--force',
      '--options',
      'runtime',
      '--timestamp',
      ...keychainArgs,
      '-s',
      identity,
      '$app/Contents/Helpers/impellerc',
    ]);
    _run('codesign', [
      '--force',
      '--options',
      'runtime',
      '--timestamp',
      '--deep',
      ...keychainArgs,
      '-s',
      identity,
      app,
    ]);
  } else {
    // Re-seal with an ad hoc signature so the tool copies above do not leave
    // the bundle with a broken resource seal.
    _run('codesign', ['--force', '--deep', '-s', '-', app]);
  }

  // Staple the app before it is packaged, so a copy dragged out of the DMG
  // carries its own ticket and launches without asking Apple. Stapling only
  // the DMG leaves the installed app dependent on a network lookup.
  final profile = options.notarizeProfile;
  if (profile != null) {
    _notarize(app, profile, archiveFirst: true);
  }

  final dmg =
      '${_distDir(appDir)}/'
      'flutter_scene_editor-$version-macos-${_arch()}.dmg';
  final staging = Directory.systemTemp.createTempSync('editor_dmg_');
  // ditto preserves symlinks, permissions, and signatures inside the app.
  _run('ditto', [app, '${staging.path}/${app.split('/').last}']);
  _run('ln', ['-s', '/Applications', '${staging.path}/Applications']);
  if (File(dmg).existsSync()) File(dmg).deleteSync();
  _run('hdiutil', [
    'create',
    '-volname',
    'Flutter Scene Editor',
    '-srcfolder',
    staging.path,
    '-format',
    'UDZO',
    dmg,
  ]);
  staging.deleteSync(recursive: true);

  // hdiutil output is unsigned, so the DMG is signed after it exists.
  if (identity != null) {
    _run('codesign', [
      '--force',
      '--timestamp',
      ...keychainArgs,
      '-s',
      identity,
      dmg,
    ]);
  }
  if (profile != null) {
    _notarize(dmg, profile);
  }
  _printSha256(dmg);
}

// Submits [path] to the notary service and staples the returned ticket to it.
// notarytool takes an archive rather than a bundle, so an .app is zipped for
// submission while the ticket still staples to the bundle itself.
void _notarize(String path, String profile, {bool archiveFirst = false}) {
  var submission = path;
  Directory? staging;
  if (archiveFirst) {
    staging = Directory.systemTemp.createTempSync('editor_notarize_');
    submission = '${staging.path}/${path.split('/').last}.zip';
    // keepParent keeps the .app wrapper the notary service expects.
    _run('ditto', ['-c', '-k', '--keepParent', path, submission]);
  }
  _run('xcrun', [
    'notarytool',
    'submit',
    submission,
    '--keychain-profile',
    profile,
    '--wait',
  ]);
  _run('xcrun', ['stapler', 'staple', path]);
  staging?.deleteSync(recursive: true);
}

void _packagePosixBundle(
  String appDir,
  String bundle,
  _Tools tools,
  String manifest,
  String version,
  String platform,
) {
  _installTools('$bundle/bin', '$bundle/data', tools, manifest);
  // Profile engines read switches from the environment; release ones do not
  // (see the header comment), so the launcher is the supported entry point.
  final launcher = File('$bundle/flutter_scene_editor.sh');
  launcher.writeAsStringSync('''
#!/usr/bin/env bash
# Launches the editor with Impeller + Flutter GPU enabled.
cd "\$(dirname "\$0")"
export FLUTTER_ENGINE_SWITCHES=2
export FLUTTER_ENGINE_SWITCH_1=enable-impeller=true
export FLUTTER_ENGINE_SWITCH_2=enable-flutter-gpu=true
exec ./flutter_scene_editor_app "\$@"
''');
  _run('chmod', ['+x', launcher.path]);

  final archive =
      '${_distDir(appDir)}/'
      'flutter_scene_editor-$version-$platform-${_arch()}.tar.gz';
  if (File(archive).existsSync()) File(archive).deleteSync();
  _run('tar', [
    'czf',
    archive,
    '-C',
    File(bundle).parent.path,
    bundle.split('/').last,
  ]);
  _printSha256(archive);
}

void _packageWindows(
  String appDir,
  String bundle,
  _Tools tools,
  String manifest,
  String version,
) {
  _installTools('$bundle\\bin', '$bundle\\data', tools, manifest);
  File('$bundle\\flutter_scene_editor.bat').writeAsStringSync('''
@echo off
rem Launches the editor with Impeller + Flutter GPU enabled.
cd /d "%~dp0"
set FLUTTER_ENGINE_SWITCHES=2
set FLUTTER_ENGINE_SWITCH_1=enable-impeller=true
set FLUTTER_ENGINE_SWITCH_2=enable-flutter-gpu=true
start "" flutter_scene_editor_app.exe %*
''');
  final archive =
      '${_distDir(appDir)}\\'
      'flutter_scene_editor-$version-windows-${_arch()}.zip';
  if (File(archive).existsSync()) File(archive).deleteSync();
  _run('powershell', [
    '-NoProfile',
    '-Command',
    'Compress-Archive -Path "$bundle\\*" -DestinationPath "$archive"',
  ]);
  _printSha256(archive);
}
