import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The values have two consumers that want opposite things from an absolute
  // path, so these assert the one form that works for both. `Uri.resolve` is
  // what `collectShaderBundleDependencies` calls; the compiler opens the value
  // relative to the building package.
  test('entries resolve back to the source from the building package', () {
    final sourceRoot = Uri.parse('file:///work/app/packages/flutter_scene/');
    final packageRoot = Uri.parse('file:///work/app/examples/demo/');
    final rebased = rebaseShaderBundleManifest(
      {
        'Fragment': {'file': 'shaders/one.frag', 'type': 'fragment'},
      },
      sourceRoot,
      packageRoot: packageRoot,
    );

    final file = (rebased['Fragment']! as Map)['file'] as String;
    expect(file, '../../packages/flutter_scene/shaders/one.frag');
    expect(packageRoot.resolve(file), sourceRoot.resolve('shaders/one.frag'));
    // A drive letter here would parse as a URI scheme.
    expect(file, isNot(matches(RegExp(r'^[A-Za-z]:'))));
    expect(file, isNot(contains(r'\')));
  });

  test('a windows-shaped layout stays resolvable', () {
    final sourceRoot = Uri.parse('file:///D:/a/scene/packages/flutter_scene/');
    final packageRoot = Uri.parse('file:///D:/a/scene/examples/smoke/');
    final rebased = rebaseShaderBundleManifest(
      {
        'Fragment': {'file': 'shaders/one.frag'},
      },
      sourceRoot,
      packageRoot: packageRoot,
    );

    final file = (rebased['Fragment']! as Map)['file'] as String;
    expect(packageRoot.resolve(file), sourceRoot.resolve('shaders/one.frag'));
    expect(file, isNot(matches(RegExp(r'^/?[A-Za-z]:'))));
  });

  test('a posix split root still relativizes', () {
    // A container workdir and a pub cache under different top-level
    // directories share no first segment but walk up fine.
    for (final (source, package, expected) in [
      (
        'file:///root/.pub-cache/fs/',
        'file:///app/',
        '../root/.pub-cache/fs/shaders/one.frag',
      ),
      (
        'file:///opt/pub-cache/fs/',
        'file:///builds/proj/',
        '../../opt/pub-cache/fs/shaders/one.frag',
      ),
      (
        'file:///Users/me/.pub-cache/fs/',
        'file:///Users/me/app/',
        '../.pub-cache/fs/shaders/one.frag',
      ),
    ]) {
      final rebased = rebaseShaderBundleManifest(
        {
          'Fragment': {'file': 'shaders/one.frag'},
        },
        Uri.parse(source),
        packageRoot: Uri.parse(package),
      );
      final file = (rebased['Fragment']! as Map)['file'] as String;
      expect(file, expected);
      expect(
        Uri.parse(package).resolve(file),
        Uri.parse(source).resolve('shaders/one.frag'),
      );
    }
  });

  test('one windows drive relativizes across directories', () {
    final rebased = rebaseShaderBundleManifest(
      {
        'Fragment': {'file': 'shaders/one.frag'},
      },
      Uri.parse('file:///C:/pkg/fs/'),
      packageRoot: Uri.parse('file:///C:/app/'),
    );
    expect((rebased['Fragment']! as Map)['file'], '../pkg/fs/shaders/one.frag');
  });

  test('roots sharing nothing fall back to a readable URI', () {
    final rebased = rebaseShaderBundleManifest(
      {
        'Fragment': {'file': 'shaders/one.frag'},
      },
      Uri.parse('file:///D:/scene/packages/flutter_scene/'),
      packageRoot: Uri.parse('file:///C:/apps/demo/'),
    );

    final file = (rebased['Fragment']! as Map)['file'] as String;
    expect(file, startsWith('file:///'));
    expect(Uri.parse(file).toFilePath(windows: true), isNotEmpty);
  });

  test('other entry fields survive', () {
    final rebased = rebaseShaderBundleManifest(
      {
        'Fragment': {'file': 'a.frag', 'type': 'fragment', 'language': 'glsl'},
      },
      Uri.parse('file:///pkg/scene/'),
      packageRoot: Uri.parse('file:///pkg/app/'),
    );

    final entry = (rebased['Fragment']! as Map).cast<String, Object?>();
    expect(entry['type'], 'fragment');
    expect(entry['language'], 'glsl');
  });
}
