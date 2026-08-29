// Spawning from a blueprint. A node runs inside one tick and loading a file
// does not, so a graph spawns a copy of a template the scene already holds --
// the same shape as handing Unity's Instantiate a loaded prefab.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A spawner node with a hidden template parked beside it.
({Node spawner, Node template, SceneVisualScriptHost host, List<String> log})
rig() {
  final log = <String>[];
  final spawner = Node(name: 'Spawner');
  final template = Node(name: 'Crate')..visible = false;
  spawner.add(template);
  return (
    spawner: spawner,
    template: template,
    host: SceneVisualScriptHost(spawner, onLog: log.add),
    log: log,
  );
}

void main() {
  test('the palette carries Spawn', () {
    expect(sceneVisualScriptRegistry()['scene.spawn'], isNotNull);
  });

  test('a copy of the template appears', () {
    final r = rig();
    final name = r.host.invoke('spawn', {
      'template': 'Crate',
      'at': Vector3(1, 2, 3),
    });
    expect(name, 'Crate');
    // With no parent named and no scene above it, the copy lands under the
    // node the graph runs on: the template plus the copy.
    final crates = r.spawner.children.where((n) => n.name == 'Crate');
    expect(crates.length, 2, reason: 'nothing was spawned');
  });

  test('the copy stands where it was asked to', () {
    final r = rig();
    r.host.invoke('spawn', {
      'template': 'Crate',
      'at': Vector3(1, 2, 3),
      'parent': 'Spawner',
    });
    final spawned = r.spawner.children.lastWhere((n) => n.name == 'Crate');
    expect(spawned.position, Vector3(1, 2, 3));
  });

  test('the copy is visible even though the template is not', () {
    // A template is usually parked hidden, and a spawn nobody can see reads
    // as a spawn that failed.
    final r = rig();
    r.host.invoke('spawn', {'template': 'Crate', 'parent': 'Spawner'});
    final spawned = r.spawner.children.lastWhere((n) => n.name == 'Crate');
    expect(spawned.visible, isTrue);
    expect(r.template.visible, isFalse, reason: 'the template was disturbed');
  });

  test('the copy is independent of the template', () {
    final r = rig();
    r.host.invoke('spawn', {'template': 'Crate', 'parent': 'Spawner'});
    final spawned = r.spawner.children.lastWhere((n) => n.name == 'Crate');
    spawned.position = Vector3(9, 9, 9);
    expect(r.template.position, Vector3.zero());
  });

  test('a template that is not there is reported, not guessed at', () {
    final r = rig();
    expect(r.host.invoke('spawn', {'template': 'Barrel'}), '');
    expect(r.log.single, contains('Barrel'));
  });

  test('spawning with no template named says so', () {
    final r = rig();
    expect(r.host.invoke('spawn', {'template': ''}), '');
    expect(r.log.single, contains('no template'));
  });

  test('a parent that is not there is reported', () {
    final r = rig();
    expect(
      r.host.invoke('spawn', {'template': 'Crate', 'parent': 'Nowhere'}),
      '',
    );
    expect(r.log.single, contains('Nowhere'));
  });

  test('a template cannot be spawned into itself', () {
    // It would be its own child, which is a tree that is not one.
    final r = rig();
    expect(
      r.host.invoke('spawn', {'template': 'Crate', 'parent': 'Crate'}),
      '',
    );
    expect(r.log.single, contains('itself'));
  });

  test('spawning twice gives two, not one moved twice', () {
    final r = rig();
    r.host.invoke('spawn', {'template': 'Crate', 'parent': 'Spawner'});
    r.host.invoke('spawn', {'template': 'Crate', 'parent': 'Spawner'});
    final crates = r.spawner.children.where((n) => n.name == 'Crate');
    expect(crates.length, 3, reason: 'the template plus two copies');
  });
}
