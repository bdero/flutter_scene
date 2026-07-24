// Covers the prefab composer: expanding instance nodes against referenced
// prefab documents, id remapping, override/add/remove deltas, nested prefabs,
// and cycle handling. All GPU-free (document-to-document).

import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A single-root prefab: 'body' (mesh referencing a material) with a 'wheel'
// child.
SceneDocument _prefab() {
  final doc = SceneDocument();
  final material = doc.addResource(
    MaterialResource(doc.newId(), type: 'physicallyBased'),
  );
  final body = doc.createNode(
    name: 'body',
    root: true,
    components: [
      ComponentSpec(
        'mesh',
        properties: {'material': ResourceRefValue(material.id)},
      ),
    ],
  );
  final wheel = doc.createNode(name: 'wheel');
  body.children.add(wheel.id);
  return doc;
}

PrefabResolver _resolveTo(SceneDocument prefab) =>
    (_) => prefab;

void main() {
  test('returns a document without instances unchanged', () {
    final doc = SceneDocument();
    doc.createNode(name: 'plain', root: true);
    expect(
      composeScene(doc, resolve: (_) => throw StateError('no resolve')),
      same(doc),
    );
  });

  test('instantiates a single-root prefab, merging the root into the '
      'instance', () {
    final host = SceneDocument();
    host.createNode(name: 'enemy0', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('enemy.fscene'),
    );

    final composed = composeScene(host, resolve: _resolveTo(_prefab()));
    final node = composed.rootNodes.single;

    expect(node.name, 'enemy0');
    expect(node.instance, isNull);
    expect(node.components.map((c) => c.type), contains('mesh'));
    expect(node.children, hasLength(1));
    expect(composed.node(node.children.single)!.name, 'wheel');
    // The prefab's material was copied into the composed document.
    expect(
      composed.resources.values.whereType<MaterialResource>(),
      hasLength(1),
    );
    // The merged mesh references that copied material.
    final mesh = node.components.firstWhere((c) => c.type == 'mesh');
    final materialId = (mesh.properties['material'] as ResourceRefValue).id;
    expect(composed.resource(materialId), isA<MaterialResource>());
  });

  test('two instances of one prefab get distinct node ids', () {
    final host = SceneDocument();
    host.createNode(name: 'a', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );
    host.createNode(name: 'b', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    final composed = composeScene(host, resolve: _resolveTo(_prefab()));
    final wheels = composed.nodes.values
        .where((n) => n.name == 'wheel')
        .toList();
    expect(wheels, hasLength(2));
    expect(wheels[0].id, isNot(wheels[1].id));
  });

  test('applies transform, name, and component overrides', () {
    final prefab = _prefab();
    final bodyId = prefab.rootNodes.single.id;
    final wheelId = prefab.rootNodes.single.children.single;

    final host = SceneDocument();
    final newMaterial = host.addResource(
      MaterialResource(host.newId(), type: 'unlit'),
    );
    host.createNode(name: 'enemy', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
      overrides: [
        PropertyOverride(
          target: bodyId,
          path: 'components.mesh.material',
          value: ResourceRefValue(newMaterial.id),
        ),
        PropertyOverride(
          target: wheelId,
          path: 'transform.trs.t',
          value: Vec3Value(Vector3(5, 0, 0)),
        ),
        PropertyOverride(
          target: wheelId,
          path: 'name',
          value: const StringValue('renamed'),
        ),
      ],
    );

    final composed = composeScene(host, resolve: _resolveTo(prefab));
    final node = composed.rootNodes.single;
    final mesh = node.components.firstWhere((c) => c.type == 'mesh');
    expect(
      (mesh.properties['material'] as ResourceRefValue).id,
      newMaterial.id,
    );

    final wheel = composed.node(node.children.single)!;
    expect(wheel.name, 'renamed');
    expect((wheel.transform as TrsTransform).translation, Vector3(5, 0, 0));
  });

  test('removes a prefab node', () {
    final prefab = _prefab();
    final wheelId = prefab.rootNodes.single.children.single;
    final host = SceneDocument();
    host.createNode(root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
      removedNodes: [wheelId],
    );

    final composed = composeScene(host, resolve: _resolveTo(prefab));
    expect(composed.nodes.values.where((n) => n.name == 'wheel'), isEmpty);
    expect(composed.rootNodes.single.children, isEmpty);
  });

  test('attaches host nodes and adds/removes components', () {
    final host = SceneDocument();
    final extra = host.createNode(name: 'extra'); // a real host node
    final instance = host.createNode(root: true);
    instance.children.add(extra.id); // associated with the instance in the host
    instance.instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
      attachments: [Attachment(extra.id)], // graft under the instance root
      addedComponents: [ComponentSpec('camera')],
      removedComponentTypes: ['mesh'],
    );

    final composed = composeScene(host, resolve: _resolveTo(_prefab()));
    final node = composed.node(instance.id)!;
    expect(node.components.map((c) => c.type), contains('camera'));
    expect(node.components.map((c) => c.type), isNot(contains('mesh')));
    expect(node.children.map((c) => composed.node(c)!.name), contains('extra'));
  });

  test('records member origins for composed prefab nodes', () {
    final host = SceneDocument();
    final prefab = _prefab();
    final bodyId = prefab.rootNodes.single.id;
    final wheelId = prefab.rootNodes.single.children.single;
    final instance = host.createNode(root: true)
      ..instance = PrefabInstanceSpec(source: const AssetRef('p'));

    final origins = <LocalId, PrefabMemberOrigin>{};
    final composed = composeScene(
      host,
      resolve: _resolveTo(prefab),
      memberOrigins: origins,
    );
    // The merged root maps to the instance node and carries the prefab root id.
    expect(origins[instance.id]?.prefabLocalId, bodyId);
    final composedWheel = composed
        .node(instance.id)!
        .children
        .firstWhere((c) => composed.node(c)!.name == 'wheel');
    expect(origins[composedWheel]?.instanceId, instance.id);
    expect(origins[composedWheel]?.prefabLocalId, wheelId);
  });

  test('attaches a host node under an internal prefab node', () {
    final host = SceneDocument();
    final prefab = _prefab();
    final wheelId = prefab.rootNodes.single.children.single; // prefab-local
    final prop = host.createNode(name: 'prop');
    final instance = host.createNode(root: true);
    instance.children.add(prop.id);
    instance.instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
      attachments: [Attachment(prop.id, parent: wheelId)],
    );

    final composed = composeScene(host, resolve: _resolveTo(prefab));
    final composedWheel = composed
        .node(instance.id)!
        .children
        .firstWhere((c) => composed.node(c)!.name == 'wheel');
    expect(
      composed.node(composedWheel)!.children.map((c) => composed.node(c)!.name),
      contains('prop'),
    );
    expect(composed.node(instance.id)!.children, isNot(contains(prop.id)));
  });

  test('applies a visible override to an internal prefab node', () {
    final host = SceneDocument();
    final prefab = _prefab();
    final wheelId = prefab.rootNodes.single.children.single;
    final instance = host.createNode(root: true);
    instance.instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
      overrides: [
        PropertyOverride(
          target: wheelId,
          path: 'visible',
          value: const BoolValue(false),
        ),
      ],
    );

    final composed = composeScene(host, resolve: _resolveTo(prefab));
    final wheel = composed
        .node(instance.id)!
        .children
        .firstWhere((c) => composed.node(c)!.name == 'wheel');
    expect(composed.node(wheel)!.visible, isFalse);
  });

  test('composes nested prefabs', () {
    final inner = SceneDocument();
    inner.createNode(name: 'gear', root: true);

    final outer = SceneDocument();
    final machine = outer.createNode(name: 'machine', root: true);
    final innerInstance = outer.createNode(name: 'innerInstance');
    innerInstance.instance = PrefabInstanceSpec(
      source: const AssetRef('inner'),
    );
    machine.children.add(innerInstance.id);

    final host = SceneDocument();
    host.createNode(name: 'top', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('outer'),
    );

    final composed = composeScene(
      host,
      resolve: (ref) => ref.key == 'inner' ? inner : outer,
    );
    final top = composed.rootNodes.single;
    expect(top.name, 'top');
    expect(composed.node(top.children.single)!.name, 'innerInstance');
    expect(composed.nodes.values.where((n) => n.instance != null), isEmpty);
  });

  test('breaks a cyclic prefab reference without recursing forever', () {
    final cyclic = SceneDocument();
    final root = cyclic.createNode(name: 'root', root: true);
    final self = cyclic.createNode(name: 'self');
    self.instance = PrefabInstanceSpec(source: const AssetRef('cyclic'));
    root.children.add(self.id);

    final host = SceneDocument();
    host.createNode(root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('cyclic'),
    );

    final composed = composeScene(host, resolve: _resolveTo(cyclic));
    expect(composed.nodes.values.where((n) => n.instance != null), isEmpty);
  });

  test('composeSceneAsync loads referenced prefabs transitively, once '
      'each', () async {
    final inner = SceneDocument()..createNode(name: 'gear', root: true);
    final outer = SceneDocument();
    final machine = outer.createNode(name: 'machine', root: true);
    final innerInstance = outer.createNode(name: 'innerInstance');
    innerInstance.instance = PrefabInstanceSpec(
      source: const AssetRef('inner'),
    );
    machine.children.add(innerInstance.id);

    final host = SceneDocument();
    host.createNode(name: 'top', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('outer'),
    );

    final docs = {'inner': inner, 'outer': outer};
    final loads = <String>[];
    final composed = await composeSceneAsync(
      host,
      load: (ref) async {
        loads.add(ref.key);
        return docs[ref.key]!;
      },
    );

    expect(composed.nodes.values.where((n) => n.instance != null), isEmpty);
    expect(composed.rootNodes.single.name, 'top');
    expect(loads, unorderedEquals(['outer', 'inner']));
  });

  test('composeSceneAsync loads a shared prefab source only once', () async {
    final prefab = SceneDocument()..createNode(name: 'p', root: true);
    final host = SceneDocument();
    host.createNode(name: 'a', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );
    host.createNode(name: 'b', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    var loads = 0;
    await composeSceneAsync(
      host,
      load: (_) async {
        loads++;
        return prefab;
      },
    );
    expect(loads, 1);
  });

  group('deterministic remapping', () {
    test('recomposing yields identical ids', () {
      final prefab = _prefab();
      SceneDocument host() {
        final doc = SceneDocument(documentId: DocumentId(Uint8List(16)));
        doc.addNode(
          NodeSpec(
            id: const LocalId(5, 1),
            name: 'a',
            instance: PrefabInstanceSpec(source: const AssetRef('p')),
          ),
          root: true,
        );
        return doc;
      }

      final first = composeScene(host(), resolve: _resolveTo(prefab));
      final second = composeScene(host(), resolve: _resolveTo(prefab));
      expect(first.nodes.keys.toSet(), second.nodes.keys.toSet());
      expect(first.resources.keys.toSet(), second.resources.keys.toSet());
      expect(first.payloads.keys.toSet(), second.payloads.keys.toSet());
    });

    test('two instances of one prefab share resources but not nodes', () {
      final host = SceneDocument();
      host.createNode(name: 'a', root: true).instance = PrefabInstanceSpec(
        source: const AssetRef('p'),
      );
      host.createNode(name: 'b', root: true).instance = PrefabInstanceSpec(
        source: const AssetRef('p'),
      );

      final composed = composeScene(host, resolve: _resolveTo(_prefab()));
      // One shared material resource, not one per instance.
      expect(composed.resources, hasLength(1));
      final materialId = composed.resources.keys.single;
      for (final root in composed.rootNodes) {
        final mesh = root.components.singleWhere((c) => c.type == 'mesh');
        expect(
          (mesh.properties['material'] as ResourceRefValue).id,
          materialId,
        );
      }
      // The wheels stay distinct per instance.
      final wheels = composed.nodes.values.where((n) => n.name == 'wheel');
      expect(wheels.map((n) => n.id).toSet(), hasLength(2));
    });
  });

  test('keeps a nested lazy instance as a placeholder', () {
    final prefab = SceneDocument();
    final root = prefab.createNode(name: 'prefabRoot', root: true);
    final lazy = prefab.createNode(name: 'lazyChild');
    lazy.instance = PrefabInstanceSpec(
      source: const AssetRef('streamed'),
      load: LoadPolicy.lazy,
    );
    root.children.add(lazy.id);

    final host = SceneDocument();
    host.createNode(name: 'inst', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    final composed = composeScene(host, resolve: _resolveTo(prefab));
    final placeholder = composed.nodes.values.singleWhere(
      (n) => n.name == 'lazyChild',
    );
    expect(placeholder.instance, isNotNull);
    expect(placeholder.instance!.load, LoadPolicy.lazy);
    expect(placeholder.instance!.source.key, 'streamed');
  });

  test('inserts a mirror adapter for an opposite-handedness prefab', () {
    final prefab = _prefab();
    prefab.stage.handedness = Handedness.right;

    final host = SceneDocument(); // left-handed by default
    host.createNode(name: 'inst', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );

    final composed = composeScene(host, resolve: _resolveTo(prefab));
    final instance = composed.rootNodes.single;
    expect(instance.name, 'inst');
    // The prefab root is not merged; an adapter sits between them.
    final adapter = composed.node(instance.children.single)!;
    expect(adapter.excludeFromWindingParity, isTrue);
    final matrix = adapter.transform.toMatrix4();
    expect(matrix.entry(2, 2), -1.0);
    final body = composed.node(adapter.children.single)!;
    expect(body.name, 'body');

    // The adapter flag survives the JSON round trip.
    final restored = readFscene(writeFscene(composed));
    expect(restored.node(adapter.id)!.excludeFromWindingParity, isTrue);
  });
}
