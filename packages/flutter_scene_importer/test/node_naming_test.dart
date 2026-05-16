/// Covers [resolveGltfNodeName], the shared rule both the offline
/// `.model` emitter and the runtime GLB importer use to name nodes.
/// Animation channels resolve their targets by node name, so unnamed
/// glTF nodes must get unique synthetic names or every channel collides
/// on one node.
library;

import 'package:flutter_scene_importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps an authored name unchanged', () {
    expect(resolveGltfNodeName('Armature', 0), 'Armature');
    expect(resolveGltfNodeName('b_Root_00', 12), 'b_Root_00');
  });

  test('synthesizes a name for a null name', () {
    expect(resolveGltfNodeName(null, 7), 'node_7');
  });

  test('synthesizes a name for an empty name', () {
    expect(resolveGltfNodeName('', 3), 'node_3');
  });

  test('synthetic names are unique across distinct indices', () {
    final names = {for (var i = 0; i < 100; i++) resolveGltfNodeName(null, i)};
    expect(names.length, 100);
  });

  test('an authored name that looks synthetic is still passed through', () {
    // The author owns the name even when it collides with the synthetic
    // form; resolving that fully would need index- or path-based
    // channel binding.
    expect(resolveGltfNodeName('node_2', 9), 'node_2');
  });
}
