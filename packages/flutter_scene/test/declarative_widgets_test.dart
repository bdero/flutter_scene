import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Reconciliation tests for the declarative scene widgets, run against a bare
/// [Node] parent through [SceneSubtree] so no GPU (and no [Scene]) is needed.

class _FakeMaterial implements Material {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGeometry implements Geometry {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingComponent extends Component {
  int attaches = 0;
  int detaches = 0;

  @override
  void onAttach() => attaches++;

  @override
  void onDetach() => detaches++;
}

void main() {
  late Node root;

  setUp(() {
    root = Node(name: 'test-root');
  });

  Widget host(List<Widget> children) =>
      SceneSubtree(parent: root, children: children);

  group('SceneNode structure', () {
    testWidgets('mounts under the parent and detaches on unmount', (
      tester,
    ) async {
      await tester.pumpWidget(host([SceneNode(name: 'a')]));
      expect(root.children, hasLength(1));
      expect(root.children.single.name, 'a');

      await tester.pumpWidget(host([]));
      expect(root.children, isEmpty);
    });

    testWidgets('nests children under the widget node', (tester) async {
      await tester.pumpWidget(
        host([
          SceneNode(
            name: 'parent',
            children: [SceneNode(name: 'child')],
          ),
        ]),
      );
      final parent = root.children.single;
      expect(parent.name, 'parent');
      expect(parent.children.single.name, 'child');
    });

    testWidgets('non-scene widgets can sit between scene widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([Builder(builder: (context) => SceneNode(name: 'built'))]),
      );
      expect(root.children.single.name, 'built');
    });

    testWidgets('conditional removal detaches only the removed subtree', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([SceneNode(name: 'a'), SceneNode(name: 'b')]),
      );
      expect(root.children.map((n) => n.name), ['a', 'b']);

      await tester.pumpWidget(host([SceneNode(name: 'b')]));
      // Without keys the first element pairs positionally and is renamed;
      // the second unmounts.
      expect(root.children, hasLength(1));
      expect(root.children.single.name, 'b');
    });

    testWidgets('keys preserve engine-node identity across reorders', (
      tester,
    ) async {
      final controllerA = SceneNodeController();
      final controllerB = SceneNodeController();
      Widget build(bool swapped) => host([
        for (final entry in swapped ? ['b', 'a'] : ['a', 'b'])
          SceneNode(
            key: ValueKey(entry),
            name: entry,
            controller: entry == 'a' ? controllerA : controllerB,
          ),
      ]);

      await tester.pumpWidget(build(false));
      final nodeA = controllerA.node;
      final nodeB = controllerB.node;
      expect(nodeA, isNotNull);

      await tester.pumpWidget(build(true));
      expect(identical(controllerA.node, nodeA), isTrue);
      expect(identical(controllerB.node, nodeB), isTrue);
      expect(root.children, hasLength(2));
    });

    testWidgets('GlobalKey reparenting keeps the same engine node', (
      tester,
    ) async {
      final key = GlobalKey();
      final controller = SceneNodeController();
      Widget build(bool underParent) => host([
        SceneNode(
          name: 'anchor',
          children: [
            if (underParent)
              SceneNode(key: key, name: 'moved', controller: controller),
          ],
        ),
        if (!underParent)
          SceneNode(key: key, name: 'moved', controller: controller),
      ]);

      await tester.pumpWidget(build(true));
      final moved = controller.node;
      expect(moved, isNotNull);
      expect(root.children.single.children.single, same(moved));

      await tester.pumpWidget(build(false));
      expect(identical(controller.node, moved), isTrue);
      expect(root.children, hasLength(2));
      expect(root.children[0].children, isEmpty);
      expect(root.children.contains(moved), isTrue);
    });
  });

  group('SceneNode props', () {
    testWidgets('applies transform props and diffs on rebuild', (tester) async {
      await tester.pumpWidget(
        host([SceneNode(name: 'n', position: vm.Vector3(1, 2, 3))]),
      );
      final node = root.children.single;
      expect(node.localTransform.getTranslation(), vm.Vector3(1, 2, 3));

      await tester.pumpWidget(
        host([SceneNode(name: 'n', position: vm.Vector3(4, 5, 6))]),
      );
      expect(identical(root.children.single, node), isTrue);
      expect(node.localTransform.getTranslation(), vm.Vector3(4, 5, 6));
    });

    testWidgets('full transform matrix prop applies', (tester) async {
      final transform = vm.Matrix4.identity()..setEntry(0, 3, 7.0);
      await tester.pumpWidget(host([SceneNode(transform: transform)]));
      expect(root.children.single.localTransform.entry(0, 3), 7.0);
      // The widget clones; mutating the passed matrix must not leak through.
      transform.setEntry(0, 3, 99.0);
      expect(root.children.single.localTransform.entry(0, 3), 7.0);
    });

    testWidgets('visible prop applies and diffs', (tester) async {
      await tester.pumpWidget(host([SceneNode(name: 'n', visible: false)]));
      expect(root.children.single.visible, isFalse);
      await tester.pumpWidget(host([SceneNode(name: 'n')]));
      expect(root.children.single.visible, isTrue);
    });

    testWidgets('components identity-diff across rebuilds', (tester) async {
      final keep = _CountingComponent();
      final dropped = _CountingComponent();
      await tester.pumpWidget(
        host([
          SceneNode(name: 'n', components: [keep, dropped]),
        ]),
      );
      expect(keep.attaches, 1);
      expect(dropped.attaches, 1);

      final added = _CountingComponent();
      await tester.pumpWidget(
        host([
          SceneNode(name: 'n', components: [keep, added]),
        ]),
      );
      expect(keep.attaches, 1);
      expect(keep.detaches, 0);
      expect(dropped.detaches, 1);
      expect(added.attaches, 1);

      final node = root.children.single;
      expect(node.getComponents<_CountingComponent>(), hasLength(2));
    });

    testWidgets('controller attaches, follows, and clears', (tester) async {
      final controller = SceneNodeController();
      expect(controller.node, isNull);

      await tester.pumpWidget(host([SceneNode(controller: controller)]));
      expect(controller.node, same(root.children.single));

      await tester.pumpWidget(host([SceneNode()]));
      expect(controller.node, isNull);

      await tester.pumpWidget(host([]));
      expect(controller.node, isNull);
    });
  });

  group('SceneMesh', () {
    testWidgets('sets the mesh and identity-diffs geometry/material', (
      tester,
    ) async {
      final geometry = _FakeGeometry();
      final materialA = _FakeMaterial();
      await tester.pumpWidget(
        host([SceneMesh(geometry: geometry, material: materialA)]),
      );
      final node = root.children.single;
      final mesh = node.mesh;
      expect(mesh, isNotNull);
      expect(identical(mesh!.primitives.single.material, materialA), isTrue);

      // Same instances: mesh object stays.
      await tester.pumpWidget(
        host([SceneMesh(geometry: geometry, material: materialA)]),
      );
      expect(identical(root.children.single.mesh, mesh), isTrue);

      // New material instance: mesh rebuilt around it.
      final materialB = _FakeMaterial();
      await tester.pumpWidget(
        host([SceneMesh(geometry: geometry, material: materialB)]),
      );
      expect(
        identical(
          root.children.single.mesh!.primitives.single.material,
          materialB,
        ),
        isTrue,
      );
    });
  });

  group('SceneNodeHost', () {
    testWidgets('mounts and unmounts an app-owned node without touching it', (
      tester,
    ) async {
      final external = Node(name: 'external')..add(Node(name: 'inner'));
      await tester.pumpWidget(host([SceneNodeHost(node: external)]));
      expect(root.children.single, same(external));

      await tester.pumpWidget(host([]));
      expect(root.children, isEmpty);
      // Contents untouched.
      expect(external.children.single.name, 'inner');
    });

    testWidgets('swapping the hosted node swaps the attachment', (
      tester,
    ) async {
      final first = Node(name: 'first');
      final second = Node(name: 'second');
      await tester.pumpWidget(host([SceneNodeHost(node: first)]));
      expect(root.children.single, same(first));

      await tester.pumpWidget(host([SceneNodeHost(node: second)]));
      expect(root.children.single, same(second));
      expect(first.parent, isNull);
    });
  });

  group('SceneSubtree', () {
    testWidgets('throws a useful error with no parent and no SceneScope', (
      tester,
    ) async {
      await tester.pumpWidget(const SceneSubtree(children: []));
      expect(tester.takeException(), isFlutterError);
    });

    testWidgets('reparents children when the parent changes', (tester) async {
      final other = Node(name: 'other-root');
      final controller = SceneNodeController();
      await tester.pumpWidget(
        SceneSubtree(
          parent: root,
          children: [SceneNode(controller: controller)],
        ),
      );
      final node = controller.node;
      expect(root.children.single, same(node));

      await tester.pumpWidget(
        SceneSubtree(
          parent: other,
          children: [SceneNode(controller: controller)],
        ),
      );
      expect(root.children, isEmpty);
      expect(other.children.single, same(node));
    });
  });
}
