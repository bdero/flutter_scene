import 'dart:io';

import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rebased entries are paths the host can open', () {
    final sourceRoot = Uri.directory(
      Uri.file('/pkg/flutter_scene/').toFilePath(),
    );
    final rebased = rebaseShaderBundleManifest({
      'Fragment': {'file': 'shaders/one.frag', 'type': 'fragment'},
    }, sourceRoot);

    final file = (rebased['Fragment']! as Map)['file'] as String;
    expect(file, sourceRoot.resolve('shaders/one.frag').toFilePath());
    // A posix-formatted Windows path (`/C:/...`) opens nowhere.
    expect(file, isNot(matches(RegExp(r'^/[A-Za-z]:'))));
    expect(File(file).uri.toFilePath(), file);
  });

  test('other entry fields survive', () {
    final rebased = rebaseShaderBundleManifest({
      'Fragment': {'file': 'a.frag', 'type': 'fragment', 'language': 'glsl'},
    }, Uri.directory(Uri.file('/pkg/').toFilePath()));

    final entry = (rebased['Fragment']! as Map).cast<String, Object?>();
    expect(entry['type'], 'fragment');
    expect(entry['language'], 'glsl');
  });
}
