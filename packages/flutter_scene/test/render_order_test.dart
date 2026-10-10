// Covers `.fmat` `render_order:` and the document round trips of material
// and node render orders. The draw order itself is checked on a real GPU by
// examples/smoke_render/integration_test/render_order_test.dart.

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/realize.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  group('.fmat render_order', () {
    test('parses into the AST and the sidecar', () {
      final m = parseFmat('''
material { name: "Paint", blending: alpha, render_order: -2.5 }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.renderOrder, -2.5);
      expect(buildSidecar(m)['render_order'], -2.5);

      final byDefault = parseFmat('''
material { name: "Plain" }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(byDefault.renderOrder, 0);
      expect(buildSidecar(byDefault).containsKey('render_order'), isFalse);
    });

    test('rejects a value that is not a number', () {
      expect(
        () => parseFmat('''
material { name: "X", render_order: late }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        throwsA(isA<FmatException>()),
      );
    });
  });

  group('node render order document', () {
    SceneDocument documentWithOrder(double order) {
      final document = SceneDocument();
      final node = NodeSpec(id: document.newId(), renderOrder: order);
      document.addNode(node);
      document.roots.add(node.id);
      return document;
    }

    test('realizes onto the node and serializes back', () {
      final root = realizeScene(documentWithOrder(-3));
      expect(root.children.single.renderOrder, -3);

      final serialized = serializeScene(Node()..add(Node()..renderOrder = 2));
      expect([
        for (final node in serialized.nodes.values) node.renderOrder,
      ], contains(2));
    });

    test('a change shows in the document diff', () {
      final before = documentWithOrder(0);
      final after = readFscene(writeFscene(before));
      after.nodes.values.single.renderOrder = 1;
      final change = diffScene(before, after).changed.single;
      expect(change.renderOrder, isTrue);
    });

    test('is omitted at the default and survives text', () {
      expect(writeFscene(documentWithOrder(0)), isNot(contains('renderOrder')));
      final text = writeFscene(documentWithOrder(1.5));
      expect(text, contains('renderOrder'));
      final decoded = readFscene(text);
      expect(decoded.nodes[decoded.roots.single]!.renderOrder, 1.5);
    });
  });

  test('material render order realizes and serializes', () async {
    await Scene.initializeStaticResources();
    final source = SceneDocument();
    final resource = source.addResource(
      MaterialResource(
        source.newId(),
        type: 'physicallyBased',
        properties: {'renderOrder': const DoubleValue(-4)},
      ),
    );
    expect(ResourceRealizer(source).material(resource.id).renderOrder, -4);

    final material = UnlitMaterial()..renderOrder = 3;
    final root = Node()
      ..addComponent(
        MeshComponent(Mesh(CuboidGeometry(Vector3.all(1)), material)),
      );
    final restored = serializeScene(
      root,
    ).resources.values.whereType<MaterialResource>().single;
    expect((restored.properties['renderOrder'] as DoubleValue).value, 3);
  }, skip: noGpu);
}
