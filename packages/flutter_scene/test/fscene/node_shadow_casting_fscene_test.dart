// Covers the node shadow-casting mode's document round trip: the spec name
// realizes onto the live node, a live node serializes back, the default is
// omitted from the written text, and an unknown name falls back to the
// default rather than failing the load.

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

SceneDocument _documentWithMode(String mode) {
  final document = SceneDocument();
  final node = NodeSpec(id: document.newId(), shadowCastingMode: mode);
  document.addNode(node);
  document.roots.add(node.id);
  return document;
}

void main() {
  test('a mode name realizes onto the node', () {
    for (final mode in ShadowCastingMode.values) {
      final root = realizeScene(_documentWithMode(mode.name));
      expect(root.children.single.shadowCastingMode, mode, reason: mode.name);
    }
  });

  test('an unknown mode name falls back to the default', () {
    expect(shadowCastingModeFromName('someFutureMode'), ShadowCastingMode.on);
    final root = realizeScene(_documentWithMode('someFutureMode'));
    expect(root.children.single.shadowCastingMode, ShadowCastingMode.on);
  });

  test('a live node serializes its mode back', () {
    final root = Node()
      ..add(Node()..shadowCastingMode = ShadowCastingMode.shadowsOnly);
    final document = serializeScene(root);
    final modes = [
      for (final node in document.nodes.values) node.shadowCastingMode,
    ];
    expect(modes, contains('shadowsOnly'));
  });

  test('the default mode is omitted from the written document', () {
    final plain = SceneDocument();
    final node = NodeSpec(id: plain.newId());
    plain.addNode(node);
    plain.roots.add(node.id);
    expect(writeFscene(plain), isNot(contains('shadowCasting')));

    final authored = _documentWithMode('shadowsOnly');
    final text = writeFscene(authored);
    expect(text, contains('shadowCasting'));
    final decoded = readFscene(text);
    expect(
      decoded.nodes[decoded.roots.single]!.shadowCastingMode,
      'shadowsOnly',
    );
  });
}
