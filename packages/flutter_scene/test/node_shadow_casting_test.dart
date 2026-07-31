import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

void main() {
  test('mesh nodes cast shadows by default', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    root.add(Node(mesh: Mesh(_StubGeometry(), _StubMaterial())));

    root.scenePrePass(0);

    expect(renderScene.items.single.castsShadows, isTrue);
  });

  test('castsShadows reaches mesh and instanced render items', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final meshNode = Node(mesh: Mesh(_StubGeometry(), _StubMaterial()))
      ..castsShadows = false;
    final instancedNode = Node()..castsShadows = false;
    instancedNode.addComponent(
      InstancedMeshComponent(
        InstancedMesh(geometry: _StubGeometry(), material: _StubMaterial())
          ..addInstance(Matrix4.identity()),
      ),
    );
    root
      ..add(meshNode)
      ..add(instancedNode);

    root.scenePrePass(0);

    expect(renderScene.items, hasLength(2));
    expect(renderScene.items.where((item) => !item.castsShadows), hasLength(2));
  });
}
