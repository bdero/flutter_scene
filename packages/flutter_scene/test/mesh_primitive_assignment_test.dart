import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_scene.dart' show RenderScene;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Assigning a primitive's material or geometry on a node already in a scene
/// (fake materials and geometry, no GPU).

class _FakeMaterial implements Material {
  _FakeMaterial({this.drawsNothing = false});

  @override
  final bool drawsNothing;

  @override
  Set<RenderInput> get sceneInputs => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGeometry implements Geometry {
  @override
  int get localBoundsVersion => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _frame = 1 / 60;

void main() {
  late RenderScene renderScene;

  Node mounted(Node node) {
    renderScene = RenderScene();
    node.debugMountInto(renderScene);
    return node;
  }

  test('a material assigned in a scene draws from the next frame', () {
    final replacement = _FakeMaterial();
    final node = mounted(Node(mesh: Mesh(_FakeGeometry(), _FakeMaterial())));
    final item = renderScene.items.single;

    node.mesh!.primitives.single.material = replacement;
    node.scenePrePass(_frame);

    expect(renderScene.items.single, same(item), reason: 'item is retained');
    expect(item.material, same(replacement));
    expect(item.materialIdentity, identityHashCode(replacement));
  });

  test('a geometry assigned in a scene draws from the next frame', () {
    final material = _FakeMaterial();
    final replacement = _FakeGeometry();
    final node = mounted(
      Node(mesh: Mesh(_FakeGeometry(), material))
        ..localTransform = Matrix4.translationValues(3, 0, 0),
    );

    node.mesh!.primitives.single.geometry = replacement;
    node.scenePrePass(_frame);

    final item = renderScene.items.single;
    expect(item.geometry, same(replacement));
    expect(item.material, same(material));
    expect(item.worldTransform.getTranslation().x, 3);
  });

  test('both assigned together draw from the next frame', () {
    final material = _FakeMaterial();
    final geometry = _FakeGeometry();
    final node = mounted(Node(mesh: Mesh(_FakeGeometry(), _FakeMaterial())));

    node.mesh!.primitives.single
      ..geometry = geometry
      ..material = material;
    node.scenePrePass(_frame);

    expect(renderScene.items.single.geometry, same(geometry));
    expect(renderScene.items.single.material, same(material));
  });

  test('an unassigned frame keeps every item', () {
    final node = mounted(
      Node(
        mesh: Mesh.primitives(
          primitives: [
            MeshPrimitive(_FakeGeometry(), _FakeMaterial()),
            MeshPrimitive(_FakeGeometry(), _FakeMaterial()),
          ],
        ),
      ),
    );
    final items = List.of(renderScene.items);

    node.scenePrePass(_frame);

    expect(renderScene.items, items);
  });

  test('one primitive of several takes the assignment', () {
    final replacement = _FakeMaterial();
    final keptMaterial = _FakeMaterial();
    final node = mounted(
      Node(
        mesh: Mesh.primitives(
          primitives: [
            MeshPrimitive(_FakeGeometry(), keptMaterial),
            MeshPrimitive(_FakeGeometry(), _FakeMaterial()),
          ],
        ),
      ),
    );

    node.mesh!.primitives[1].material = replacement;
    node.scenePrePass(_frame);

    final materials = renderScene.items.map((item) => item.material).toList();
    expect(materials, unorderedEquals([keptMaterial, replacement]));
  });

  test('a primitive added to or removed from the mesh follows', () {
    final node = mounted(Node(mesh: Mesh(_FakeGeometry(), _FakeMaterial())));
    final added = MeshPrimitive(_FakeGeometry(), _FakeMaterial());

    node.mesh!.primitives.add(added);
    node.scenePrePass(_frame);
    expect(renderScene.items, hasLength(2));

    node.mesh!.primitives.remove(added);
    node.scenePrePass(_frame);
    expect(renderScene.items, hasLength(1));
  });

  test('a hidden node takes the assignment when shown', () {
    final replacement = _FakeMaterial();
    final node = mounted(Node(mesh: Mesh(_FakeGeometry(), _FakeMaterial())));
    node.visible = false;
    node.scenePrePass(_frame);

    node.mesh!.primitives.single.material = replacement;
    node.scenePrePass(_frame);
    expect(renderScene.items.single.visible, isFalse);

    node.visible = true;
    node.scenePrePass(_frame);
    expect(renderScene.items.single.material, same(replacement));
    expect(renderScene.items.single.visible, isTrue);
  });

  test('an assigned draw-less material hides the item', () {
    final node = mounted(Node(mesh: Mesh(_FakeGeometry(), _FakeMaterial())));

    node.mesh!.primitives.single.material = _FakeMaterial(drawsNothing: true);
    node.scenePrePass(_frame);

    expect(renderScene.items.single.visible, isFalse);
  });

  test('a clone takes its own assignment alone', () {
    final original = _FakeMaterial();
    final replacement = _FakeMaterial();
    final template = Node(mesh: Mesh(_FakeGeometry(), original));
    final root = Node();
    final a = template.clone();
    final b = template.clone();
    root
      ..add(a)
      ..add(b);
    mounted(root);

    a.mesh!.primitives.single.material = replacement;
    root.scenePrePass(_frame);

    final materials = renderScene.items.map((item) => item.material).toList();
    expect(materials, unorderedEquals([original, replacement]));
  });

  test('nodes sharing a mesh both take the assignment', () {
    final replacement = _FakeMaterial();
    final mesh = Mesh(_FakeGeometry(), _FakeMaterial());
    final root = Node()
      ..add(Node(mesh: mesh))
      ..add(Node(mesh: mesh));
    mounted(root);

    mesh.primitives.single.material = replacement;
    root.scenePrePass(_frame);

    expect(renderScene.items.map((item) => item.material), [
      replacement,
      replacement,
    ]);
  });

  test('a geometry assigned under an LOD keeps its tag', () {
    final lod = LodComponent([
      LodLevel(
        geometry: _FakeGeometry(),
        material: _FakeMaterial(),
        screenSize: 0,
      ),
    ]);
    final node = mounted(Node()..addComponent(lod));

    lod.mesh.primitives.single.geometry = _FakeGeometry();
    node.scenePrePass(_frame);

    expect(renderScene.items.single.lod, isNotNull);
  });
}
