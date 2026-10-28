// Covers KHR_node_visibility: the parsed flag and its default, and both
// importers carrying it onto the node, so a hidden node hides its subtree.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_test/flutter_test.dart';

// A hidden parent whose child asks to be visible, a node that leaves the flag
// out, and a node without the extension.
final Map<String, Object?> _json = {
  'asset': {'version': '2.0'},
  'extensionsUsed': ['KHR_node_visibility'],
  'scenes': [
    {
      'nodes': [0, 2, 3],
    },
  ],
  'nodes': [
    {
      'name': 'Hidden',
      'children': [1],
      'extensions': {
        'KHR_node_visibility': {'visible': false},
      },
    },
    {
      'name': 'Child',
      'extensions': {
        'KHR_node_visibility': {'visible': true},
      },
    },
    {
      'name': 'Default',
      'extensions': {'KHR_node_visibility': <String, Object?>{}},
    },
    {'name': 'Plain'},
  ],
};

void main() {
  test('parses the visible flag, defaulting to visible', () {
    final doc = parseGltfJson(_json);

    expect(doc.warnings, isEmpty);
    expect(
      [for (final node in doc.nodes) node.visible],
      [false, true, true, true],
    );
  });

  test('the offline importer carries it onto the node spec', () {
    final document = buildSceneDocument(parseGltfJson(_json), Uint8List(0));
    final nodes = {for (final node in document.nodes.values) node.name: node};

    expect(nodes['Hidden']!.visible, isFalse);
    expect(nodes['Child']!.visible, isTrue);
    expect(nodes['Default']!.visible, isTrue);
    expect(nodes['Plain']!.visible, isTrue);
  });

  test('the runtime importer hides the node and so its subtree', () async {
    final root = await importGltf(
      Uint8List.fromList(utf8.encode(jsonEncode(_json))),
      resolveUri: (uri) async => fail('unexpected resource request: $uri'),
    );
    final child = root.getChildByName('Child')!;

    expect(root.getChildByName('Hidden')!.visible, isFalse);
    expect(child.visible, isTrue);
    expect(child.internalEffectiveVisible, isFalse);
    expect(root.getChildByName('Default')!.visible, isTrue);
    expect(root.getChildByName('Plain')!.visible, isTrue);
  });
}
