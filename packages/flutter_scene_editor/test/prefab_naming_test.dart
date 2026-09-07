// Where a dragged-out prefab lands and what it is called. A name comes from a
// node, and a node's name is whatever somebody typed into it, so it reaches
// the filesystem having been nowhere near a filesystem.

import 'dart:io';

import 'package:flutter_scene_editor/src/panels/asset_browser_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('prefab_naming');
  });

  tearDown(() => root.deleteSync(recursive: true));

  String pathFor(String name) => freePrefabPath(root.path, name);

  test('a plain name becomes that file', () {
    expect(pathFor('Crate'), endsWith('${Platform.pathSeparator}Crate.fscene'));
  });

  test('a name already taken gets the next one, rather than overwriting', () {
    File(pathFor('Crate')).writeAsStringSync('{}');
    expect(pathFor('Crate'), endsWith('Crate 1.fscene'));
  });

  test('it keeps counting past the second', () {
    File(pathFor('Crate')).writeAsStringSync('{}');
    File(pathFor('Crate')).writeAsStringSync('{}');
    expect(pathFor('Crate'), endsWith('Crate 2.fscene'));
  });

  test('a name that would escape the folder cannot', () {
    // A node called "../../etc/passwd" is a node somebody named that.
    final path = pathFor('../../etc/passwd');
    expect(path, startsWith(root.path));
    expect(path, isNot(contains('..')));
  });

  test('a separator in the name does not become one on disk', () {
    final path = pathFor('crates/big');
    expect(
      path.substring(root.path.length + 1),
      isNot(contains(Platform.pathSeparator)),
    );
  });

  test('a name of nothing but punctuation still becomes a file', () {
    expect(pathFor('///'), endsWith('Prefab.fscene'));
    expect(pathFor(''), endsWith('Prefab.fscene'));
  });

  test('spaces, dashes and underscores survive, since people use them', () {
    expect(pathFor('Big_Crate - 2'), endsWith('Big_Crate - 2.fscene'));
  });
}
