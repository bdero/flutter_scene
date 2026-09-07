// Lifting a subtree out as its own document. What matters is that the result
// stands alone: a prefab that still points at a resource left behind in the
// level it came from loads as half a crate everywhere else.

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'dart:typed_data';

/// A level: a crate with a lid, sharing a material, plus an unrelated floor.
({SceneDocument document, LocalId crate, LocalId floor, LocalId outside})
level() {
  final document = SceneDocument();

  final payload = PayloadSpec(
    document.newId(),
    encoding: PayloadEncoding.vertexBuffer,
    bytes: Uint8List(4),
  );
  document.addPayload(payload);
  final geometry = GeometryResource(document.newId(), vertices: payload.id);
  document.addResource(geometry);
  final texturePayload = PayloadSpec(
    document.newId(),
    encoding: PayloadEncoding.image,
    bytes: Uint8List(4),
  );
  document.addPayload(texturePayload);
  final texture = TextureResource(document.newId(), payload: texturePayload.id);
  document.addResource(texture);
  final material = MaterialResource(
    document.newId(),
    type: 'physicallyBased',
    properties: {'baseColorTexture': ResourceRefValue(texture.id)},
  );
  document.addResource(material);

  ComponentSpec mesh() => ComponentSpec(
    'mesh',
    properties: {
      'geometry': ResourceRefValue(geometry.id),
      'material': ResourceRefValue(material.id),
    },
  );

  final outside = document.newId();
  document.addNode(NodeSpec(id: outside, name: 'Elsewhere'), root: true);

  final lid = document.newId();
  final crate = document.newId();
  document.addNode(NodeSpec(id: lid, name: 'Lid', components: [mesh()]));
  document.addNode(
    NodeSpec(id: crate, name: 'Crate', children: [lid], components: [mesh()]),
    root: true,
  );

  final floor = document.newId();
  document.addNode(
    NodeSpec(id: floor, name: 'Floor', components: [mesh()]),
    root: true,
  );
  return (document: document, crate: crate, floor: floor, outside: outside);
}

void main() {
  test('the subtree and its descendants come across', () {
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate);
    expect(extracted.document.nodes, hasLength(2));
    expect(extracted.document.roots, [scene.crate]);
    expect(extracted.document.nodes.values.map((n) => n.name).toSet(), {
      'Crate',
      'Lid',
    });
  });

  test('nothing outside the subtree comes with it', () {
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate);
    expect(extracted.document.nodes.containsKey(scene.floor), isFalse);
    expect(extracted.document.nodes.containsKey(scene.outside), isFalse);
  });

  test('the resources it draws with come across', () {
    // Geometry and material, or the prefab is a node that renders nothing.
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate);
    expect(
      extracted.document.resources.values.whereType<GeometryResource>(),
      hasLength(1),
    );
    expect(
      extracted.document.resources.values.whereType<MaterialResource>(),
      hasLength(1),
    );
  });

  test('a resource named by another resource follows it', () {
    // The material names a texture, which names the payload holding it. A
    // prefab that stopped at the material would load untextured.
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate);
    expect(
      extracted.document.resources.values.whereType<TextureResource>(),
      hasLength(1),
      reason: 'the texture the material names was left behind',
    );
  });

  test('the payloads behind those resources come across', () {
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate);
    // The geometry's vertices and the texture's bytes.
    expect(extracted.document.payloads, hasLength(2));
  });

  test('nothing in the result dangles', () {
    // The property that makes it a prefab rather than a fragment.
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate).document;
    for (final node in extracted.nodes.values) {
      for (final child in node.children) {
        expect(extracted.nodes.containsKey(child), isTrue, reason: 'child');
      }
      for (final component in node.components) {
        for (final value in component.properties.values) {
          if (value is ResourceRefValue) {
            expect(
              extracted.resources.containsKey(value.id),
              isTrue,
              reason: 'resource ${value.id}',
            );
          }
        }
      }
    }
    for (final resource in extracted.resources.values) {
      if (resource is GeometryResource && resource.vertices != null) {
        expect(extracted.payloads.containsKey(resource.vertices), isTrue);
      }
      if (resource is TextureResource && resource.payload != null) {
        expect(extracted.payloads.containsKey(resource.payload), isTrue);
      }
    }
  });

  test('a reference to a node outside is cleared, and reported', () {
    // The level is not there when the prefab loads somewhere else, so the
    // reference cannot come; going quiet about it is how somebody finds out
    // from a thing that stopped working.
    final scene = level();
    final crate = scene.document.node(scene.crate)!;
    scene.document.addNode(
      NodeSpec(
        id: crate.id,
        name: crate.name,
        children: crate.children,
        components: [
          ...crate.components,
          ComponentSpec(
            'lookAt',
            properties: {'target': NodeRefValue(scene.outside)},
          ),
        ],
      ),
    );

    final extracted = extractPrefab(scene.document, scene.crate);
    expect(extracted.isComplete, isFalse);
    expect(extracted.droppedNodeReferences.single, contains('lookAt'));
    final component = extracted.document
        .node(scene.crate)!
        .components
        .firstWhere((c) => c.type == 'lookAt');
    expect(component.properties['target'], isNot(isA<NodeRefValue>()));
  });

  test('a reference to a node inside the subtree is kept', () {
    final scene = level();
    final crate = scene.document.node(scene.crate)!;
    final lid = crate.children.single;
    scene.document.addNode(
      NodeSpec(
        id: crate.id,
        name: crate.name,
        children: crate.children,
        components: [
          ComponentSpec('lookAt', properties: {'target': NodeRefValue(lid)}),
        ],
      ),
    );
    final extracted = extractPrefab(scene.document, scene.crate);
    expect(extracted.isComplete, isTrue);
    expect(
      extracted.document
          .node(scene.crate)!
          .components
          .single
          .properties['target'],
      isA<NodeRefValue>(),
    );
  });

  test('extracting a leaf gives a document with one node', () {
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.floor);
    expect(extracted.document.nodes, hasLength(1));
    expect(extracted.document.roots, [scene.floor]);
  });

  test('the source document is not touched', () {
    final scene = level();
    final before = scene.document.nodes.length;
    extractPrefab(scene.document, scene.crate);
    expect(scene.document.nodes.length, before);
    expect(scene.document.roots, contains(scene.crate));
  });

  test('it writes and reads back as a document', () {
    // The point of the whole thing: this becomes a .fscene on disk.
    final scene = level();
    final extracted = extractPrefab(scene.document, scene.crate);
    final reread = readFscene(writeFscene(extracted.document));
    expect(reread.nodes, hasLength(2));
    expect(reread.roots, [scene.crate]);
  });
}
