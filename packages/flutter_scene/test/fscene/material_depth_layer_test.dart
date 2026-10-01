import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/realize.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  if (!_gpuAvailable()) {
    test(
      'material depth layer round trip',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('material depth layer realizes, clamps, and serializes', () async {
    await Scene.initializeStaticResources();
    final source = SceneDocument();
    final resource = source.addResource(
      MaterialResource(
        source.newId(),
        type: 'physicallyBased',
        properties: {'depthLayer': const IntValue(2)},
      ),
    );
    final realized = ResourceRealizer(source).material(resource.id);
    expect(realized.depthLayer, 2);

    final material = UnlitMaterial()..depthLayer = 40;
    expect(material.depthLayer, 8);
    material.depthLayer = 3;
    final root = Node()
      ..addComponent(
        MeshComponent(Mesh(CuboidGeometry(Vector3.all(1)), material)),
      );
    final serialized = serializeScene(root);
    final restored = serialized.resources.values
        .whereType<MaterialResource>()
        .single;
    expect((restored.properties['depthLayer'] as IntValue).value, 3);
  });
}
