// Covers the display-referred flag on UnlitMaterial surviving an fscene
// round trip, in both directions. The flag decides the render bucket and
// whether the color is tone mapped, so losing it changes what draws.

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

MaterialResource _serializedMaterial(Material material) {
  final root = Node()
    ..addComponent(
      MeshComponent(Mesh(CuboidGeometry(Vector3.all(1)), material)),
    );
  return serializeScene(
    root,
  ).resources.values.whereType<MaterialResource>().single;
}

void main() {
  if (!_gpuAvailable()) {
    test(
      'unlit display-referred round trip',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('a display-referred unlit material round-trips', () async {
    await Scene.initializeStaticResources();
    final source = SceneDocument();
    final resource = source.addResource(
      MaterialResource(
        source.newId(),
        type: 'unlit',
        properties: {'displayReferred': const BoolValue(true)},
      ),
    );
    final realized = ResourceRealizer(source).material(resource.id);
    expect((realized as UnlitMaterial).displayReferred, isTrue);

    final restored = _serializedMaterial(
      UnlitMaterial()..displayReferred = true,
    );
    expect((restored.properties['displayReferred'] as BoolValue).value, isTrue);
  });

  test('a scene-referred unlit material stays the default', () async {
    await Scene.initializeStaticResources();
    final source = SceneDocument();
    final resource = source.addResource(
      MaterialResource(source.newId(), type: 'unlit', properties: {}),
    );
    final realized = ResourceRealizer(source).material(resource.id);
    expect((realized as UnlitMaterial).displayReferred, isFalse);

    // Delta persistence: the default is not written.
    final restored = _serializedMaterial(UnlitMaterial());
    expect(restored.properties.containsKey('displayReferred'), isFalse);
  });
}
