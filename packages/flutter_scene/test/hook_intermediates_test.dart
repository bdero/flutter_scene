/// flutter_scene's own hook runs with its package root in the pub cache, which
/// every project on the machine shares, so builds running at once must write
/// nothing there but the generated tree. Its files are published by rename and
/// named apart by target and engine; everything else a build writes goes into
/// the building app's own hook output directory.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_scene/src/fmat/build_materials.dart';
import 'package:flutter_scene/src/fmat/target_shader_bundle.dart';
import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/generated_assets/generated_tree.dart';
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

/// A hook input building the package at [packageRoot] for [targetOS], from an
/// app whose hook output lives under [buildRoot].
BuildInput _input(Uri packageRoot, Uri buildRoot, OS targetOS) {
  final builder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'app',
      outputDirectoryShared: buildRoot.resolve('shared/'),
      outputFile: buildRoot.resolve('output.json'),
    )
    ..setupBuildInput();
  builder.config.setupBuild(linkingEnabled: false);
  CodeAssetExtension(
    targetArchitecture: Architecture.arm64,
    targetOS: targetOS,
    linkModePreference: LinkModePreference.dynamic,
    iOS: targetOS == OS.iOS
        ? IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 13)
        : null,
    android: targetOS == OS.android
        ? AndroidCodeConfig(targetNdkApi: 21)
        : null,
  ).setupBuildInput(builder);
  return builder.build();
}

const _fragment = '''
#version 460 core
precision highp float;
uniform sampler2D source_texture;
in vec2 v_uv;
out vec4 frag_color;
void main() {
  frag_color = texture(source_texture, v_uv);
}
''';

const _vertex = '''
in vec2 position;
out vec2 v_uv;
void main() {
  v_uv = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}
''';

const _material = '''
material {
  name: "Flat",
  shading_model: unlit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0, 0.5, 0.25, 1.0);
    PrepareMaterial(material);
  }
}
''';

void _write(Directory root, String path, String contents) => (File.fromUri(
  root.uri.resolve(path),
)..parent.createSync(recursive: true)).writeAsStringSync(contents);

/// A package with a raw shader bundle `tiny` and one `.fmat` material.
Directory _package() {
  final root = Directory.systemTemp.createTempSync('fs_hook_package');
  _write(
    root,
    'pubspec.yaml',
    'name: app\nflutter:\n  assets:\n    - $generatedAssetsEntry\n',
  );
  _write(root, 'shaders/tiny.frag', _fragment);
  _write(root, 'shaders/tiny.vert', _vertex);
  _write(
    root,
    'shaders/tiny.shaderbundle.json',
    '{"TinyFragment": {"type": "fragment", "file": "shaders/tiny.frag"},'
        ' "TinyVertex": {"type": "vertex", "file": "shaders/tiny.vert"}}',
  );
  _write(root, 'assets/flat.fmat', _material);
  // A hook `flutter test` runs in process has no package resolver, so the
  // engine's shaders are found through the package config.
  _write(
    root,
    '.dart_tool/package_config.json',
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'flutter_scene',
          'rootUri': Directory.current.absolute.uri.toString(),
          'packageUri': 'lib/',
        },
      ],
    }),
  );
  return root;
}

/// Every file below [root], relative to it.
Set<String> _files(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    if (entity is File)
      entity.uri
          .toFilePath(windows: false)
          .substring(root.uri.toFilePath(windows: false).length),
};

/// Files written below [root] since [before] was listed, other than the
/// generated tree's.
Set<String> _strayWrites(Directory root, Set<String> before) => {
  for (final file in _files(root).difference(before))
    if (!file.startsWith('$generatedAssetsDirectory/')) file,
};

/// The backends each shipped `.shaderbundle` under [root]'s tree carries.
List<Set<String>> _shippedBackends(Directory root) => [
  for (final entity in Directory.fromUri(
    root.uri.resolve('$generatedAssetsDirectory/'),
  ).listSync(recursive: true))
    if (entity is File && entity.path.endsWith('.shaderbundle'))
      {
        for (final shader in fb.ShaderBundle(
          entity.readAsBytesSync(),
        ).shaders!) ...[
          if (shader.metalIos != null) 'metalIos',
          if (shader.metalDesktop != null) 'metalDesktop',
          if (shader.openglEs != null) 'openglEs',
          if (shader.vulkan != null) 'vulkan',
        ],
      },
];

Future<void> _buildTiny(String packagePath, String buildPath, OS os) =>
    buildTargetShaderBundleJson(
      buildInput: _input(
        Uri.directory(packagePath),
        Uri.directory(buildPath),
        os,
      ),
      buildOutput: BuildOutputBuilder(),
      manifestFileName: 'shaders/tiny.shaderbundle.json',
    );

void main() {
  late Directory package;
  late Directory app;

  setUp(() {
    package = _package();
    app = Directory.systemTemp.createTempSync('fs_hook_app');
  });
  tearDown(() {
    package.deleteSync(recursive: true);
    app.deleteSync(recursive: true);
  });

  test('a shader bundle build writes only the generated tree', () async {
    final before = _files(package);
    await _buildTiny(package.path, app.path, OS.iOS);
    expect(_strayWrites(package, before), isEmpty);
    expect(_shippedBackends(package), [
      {'metalIos'},
    ]);
  });

  test('a material build writes only the generated tree', () async {
    final before = _files(package);
    await buildMaterials(
      buildInput: _input(package.uri, app.uri, OS.android),
      buildOutput: BuildOutputBuilder(),
    );
    expect(_strayWrites(package, before), isEmpty);
    expect(_shippedBackends(package), [
      {'openglEs', 'vulkan'},
    ]);
  });

  test(
    'the engine build with debug views writes only the generated tree',
    () async {
      final before = _files(package);
      final output = BuildOutputBuilder();
      await buildEngineAssets(
        buildInput: _input(package.uri, app.uri, OS.iOS),
        buildOutput: output,
        debugViews: true,
      );
      expect(_strayWrites(package, before), isEmpty);
      expect(_shippedBackends(package), everyElement({'metalIos'}));
      // The wrappers are rewritten on every compile, so depending on one would
      // rerun the hook on every build.
      final appPath = app.uri.toFilePath(windows: false);
      expect(
        output.build().dependencies.where(
          (uri) => uri.toFilePath(windows: false).startsWith(appPath),
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('builds for two targets at once each ship their own backends', () async {
    final other = Directory.systemTemp.createTempSync('fs_hook_app');
    addTearDown(() => other.deleteSync(recursive: true));
    final before = _files(package);
    final (packagePath, iosBuild, androidBuild) = (
      package.path,
      app.path,
      other.path,
    );
    for (var round = 0; round < 3; round++) {
      await Future.wait([
        Isolate.run(() => _buildTiny(packagePath, iosBuild, OS.iOS)),
        Isolate.run(() => _buildTiny(packagePath, androidBuild, OS.android)),
      ]);
    }
    expect(_strayWrites(package, before), isEmpty);
    expect(
      _shippedBackends(package),
      unorderedEquals([
        {'metalIos'},
        {'openglEs', 'vulkan'},
      ]),
    );
  });

  test('a build saving after another keeps that build\'s entries', () {
    // Both open the tree before either saves, the way two builds overlap.
    final ios = GeneratedAssetTree.open(package.uri, 'app');
    final android = GeneratedAssetTree.open(package.uri, 'app');
    Uri write(GeneratedAssetTree tree, String target) {
      final uri = tree.fileUri(
        GeneratedAssetFamily.shaderBundle,
        nameId: 'base',
        extension: '.shaderbundle',
        target: target,
      );
      File.fromUri(uri).writeAsBytesSync([0]);
      tree.recordFile(
        family: GeneratedAssetFamily.shaderBundle,
        id: 'base',
        uri: uri,
        stamp: target,
        target: target,
      );
      return uri;
    }

    final iosFile = write(ios, 'metalIos');
    final androidFile = write(android, 'openglEs,vulkan');
    ios.save();
    android.save();

    final manifest = GeneratedAssetManifest.decode(
      File.fromUri(
        package.uri.resolve(
          '$generatedAssetsDirectory/$generatedManifestFileName',
        ),
      ).readAsStringSync(),
    )!;
    for (final target in ['metalIos', 'openglEs,vulkan']) {
      expect(
        manifest.find(
          GeneratedAssetFamily.shaderBundle,
          'base',
          target: target,
        ),
        isNotNull,
        reason: target,
      );
    }
    expect(File.fromUri(iosFile).existsSync(), isTrue);
    expect(File.fromUri(androidFile).existsSync(), isTrue);
  });

  test('saving leaves another build\'s write in flight alone', () {
    final tree = GeneratedAssetTree.open(package.uri, 'app');
    final output = tree.fileUri(
      GeneratedAssetFamily.shaderBundle,
      nameId: 'base',
      extension: '.shaderbundle',
    );
    // What writeGeneratedBytes holds just before its rename.
    final inFlight = File('${output.toFilePath()}.1234.abcd.tmp')
      ..writeAsBytesSync([0]);
    tree.save();
    expect(inFlight.existsSync(), isTrue);
  });
}
