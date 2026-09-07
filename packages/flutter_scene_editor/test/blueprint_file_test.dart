// Blueprint assets on disk. A graph on a node dies with the node; a blueprint
// in the project is a class, and these are the properties that make it one.

import 'dart:io';

import 'package:flutter_scene_editor/src/assets/asset_index.dart';
import 'package:flutter_scene_editor/src/blueprints/blueprint_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/visual_script.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('blueprint_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  BlueprintFile make(String name) =>
      BlueprintFile(freeBlueprintPath(root.path, name));

  test('a blueprint is a recognised project asset', () async {
    // Or it never appears in the browser that created it, and the file you
    // just made looks like nothing happened.
    File('${root.path}/Door.blueprint').writeAsStringSync('{}');
    final assets = await scanProjectAssets(root.path);
    expect(
      assets.where((a) => a.kind == FileAssetKind.blueprint).map((a) => a.name),
      ['Door.blueprint'],
    );
  });

  test('the name comes from the file, not the contents', () {
    // Renaming the file is how people rename a class, so the file wins.
    expect(BlueprintFile('/tmp/Door.blueprint').name, 'Door');
    expect(BlueprintFile('/tmp/Door').name, 'Door');
  });

  test('it round trips through disk', () async {
    final file = make('Door');
    await file.write(
      newBlueprint(
        name: 'Door',
        kind: BlueprintKind.widgetBlueprint,
        parentClass: 'camera',
      ),
    );
    final read = file.read()!;
    expect(read.name, 'Door');
    expect(read.kind, BlueprintKind.widgetBlueprint);
    expect(read.parentClass, 'camera');
    expect(read.graphs, hasLength(1));
  });

  test('it is written indented, because people diff these', () async {
    final file = make('Door');
    await file.write(
      newBlueprint(
        name: 'Door',
        kind: BlueprintKind.blueprintClass,
        parentClass: 'node',
      ),
    );
    final text = File(file.path).readAsStringSync();
    expect(text, contains('\n'), reason: 'one line makes every diff total');
  });

  test('a missing file reads as nothing, not as an empty blueprint', () {
    // An empty canvas over a file that failed to read is how you save over
    // your own work.
    expect(BlueprintFile('${root.path}/nope.blueprint').read(), isNull);
  });

  test('an unparseable file reads as nothing too', () {
    final path = '${root.path}/broken.blueprint';
    File(path).writeAsStringSync('this is not json');
    expect(BlueprintFile(path).read(), isNull);
  });

  test('a second blueprint of the same name gets its own file', () {
    // Making a second Door should give you a second Door.
    final first = freeBlueprintPath(root.path, 'Door');
    File(first).writeAsStringSync('{}');
    final second = freeBlueprintPath(root.path, 'Door');
    expect(second, isNot(first));
    expect(second, endsWith('.blueprint'));
  });

  test('a name with path characters in it cannot escape the project', () {
    final path = freeBlueprintPath(root.path, '../../etc/passwd');
    expect(path, startsWith(root.path));
    expect(path, isNot(contains('..')));
  });

  test('a name that is only punctuation still makes a file', () {
    final path = freeBlueprintPath(root.path, '///');
    expect(path, endsWith('Blueprint.blueprint'));
  });
}
