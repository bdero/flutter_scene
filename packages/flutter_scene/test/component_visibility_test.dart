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
    double depthBias = 0.0,
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

class _VisibilityComponent extends Component {
  bool show = false;
  int ticks = 0;
  @override
  void update(double deltaSeconds) {
    ticks++;
    node.visible = show;
  }
}

void main() {
  test('visibility set in update applies in the same pass', () async {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final control = _VisibilityComponent();
    final parent = Node(mesh: Mesh(_StubGeometry(), _StubMaterial()))
      ..addComponent(control);
    final child = Node(mesh: Mesh(_StubGeometry(), _StubMaterial()));
    final instanced = Node()
      ..addComponent(
        InstancedMeshComponent(
          InstancedMesh(geometry: _StubGeometry(), material: _StubMaterial())
            ..addInstance(Matrix4.identity()),
        ),
      );
    parent
      ..add(child)
      ..add(instanced);
    root.add(parent);
    await Future<void>.delayed(Duration.zero);

    root.scenePrePass(.016);
    expect(renderScene.items, hasLength(3));
    expect(renderScene.items.every((item) => !item.visible), isTrue);

    // A hidden node's component still ticks, so it can show the node again.
    control.show = true;
    root.scenePrePass(.016);
    expect(renderScene.items.every((item) => item.visible), isTrue);
    expect(control.ticks, 2);

    // Showing itself cannot override a hidden ancestor.
    root.visible = false;
    root.scenePrePass(.016);
    expect(renderScene.items.every((item) => !item.visible), isTrue);
    expect(control.ticks, 3);
  });
}
