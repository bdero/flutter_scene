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
      'material depth bias round trip',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('material depth bias realizes and serializes', () async {
    await Scene.initializeStaticResources();
    final source = SceneDocument();
    final resource = source.addResource(
      MaterialResource(
        source.newId(),
        type: 'physicallyBased',
        properties: {'depthBias': const DoubleValue(0.00001)},
      ),
    );
    final realized = ResourceRealizer(source).material(resource.id);
    expect(realized.depthBias, 0.00001);

    final material = PhysicallyBasedMaterial()..depthBias = 0.00002;
    final root = Node()
      ..addComponent(
        MeshComponent(Mesh(CuboidGeometry(Vector3.all(1)), material)),
      );
    final serialized = serializeScene(root);
    final restored = serialized.resources.values
        .whereType<MaterialResource>()
        .single;
    expect((restored.properties['depthBias'] as DoubleValue).value, 0.00002);
  });
}
