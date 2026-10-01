/// The physical material bundle loads on demand instead of gating every
/// scene's first frame. While a requested load is in flight the scene must not
/// draw (a material would pick the wrong shader), but a load that fails must
/// not keep it from drawing for good.
library;

// ignore: implementation_imports
import 'package:flutter_scene/src/material/physical_material_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nothing is pending until a material asks for the bundle', () {
    expect(physicalMaterialResourcesPending, isFalse);
    expect(physicalMaterialResourcesReady, isFalse);
  });

  test('a requested load is pending until it settles, and a failed one is '
      'not left pending', () async {
    // The test bundle has no generated assets, so the load fails.
    requestPhysicalMaterialResources();
    expect(physicalMaterialResourcesPending, isTrue);

    await pumpEventQueue();
    expect(physicalMaterialResourcesPending, isFalse);
    expect(physicalMaterialResourcesReady, isFalse);

    // A later request retries rather than reusing the failed future.
    requestPhysicalMaterialResources();
    expect(physicalMaterialResourcesPending, isTrue);
    await pumpEventQueue();
    expect(physicalMaterialResourcesPending, isFalse);
  });

  test('an awaited load reports its failure and is not left pending', () async {
    await expectLater(initializePhysicalMaterialResources(), throwsA(anything));
    expect(physicalMaterialResourcesPending, isFalse);
  });
}
