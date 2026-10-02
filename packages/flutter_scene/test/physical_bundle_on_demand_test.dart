/// The physical material bundle loads on first use instead of gating every
/// scene's first frame. A material that starts needing it asks for it, a
/// failure is reported once and not retried every frame, and an explicit
/// preload retries.
library;

import 'package:flutter/foundation.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/physical_material_variant.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<FlutterErrorDetails> reported;
  late FlutterExceptionHandler? previousOnError;

  setUp(() {
    resetPhysicalMaterialResourcesForTesting();
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() {
    FlutterError.onError = previousOnError;
    resetPhysicalMaterialResourcesForTesting();
  });

  test('a plain material does not ask for the bundle', () {
    final material = PhysicallyBasedMaterial()
      ..metallicFactor = 0.5
      ..roughnessFactor = 0.3;
    expect(physicalMaterialResourcesPending, isFalse);
    // ignore: invalid_use_of_internal_member
    expect(material.awaitsDeferredResources, isFalse);
  });

  test('an extension asks for the bundle as soon as it is set', () async {
    final material = PhysicallyBasedMaterial()..clearcoat = 0.8;
    expect(physicalMaterialResourcesPending, isTrue);
    // ignore: invalid_use_of_internal_member
    expect(material.awaitsDeferredResources, isTrue);
    expect(physicalMaterialResourcesLoad, isNotNull);

    // The test bundle has no generated assets, so the load fails.
    await physicalMaterialResourcesLoad;
    expect(physicalMaterialResourcesPending, isFalse);
    expect(physicalMaterialResourcesReady, isFalse);
    expect(physicalMaterialResourcesLoad, isNull);
  });

  test('a shadow catcher asks for the bundle and draws nothing without '
      'it', () async {
    final catcher = ShadowCatcherMaterial();
    expect(physicalMaterialResourcesPending, isTrue);
    // ignore: invalid_use_of_internal_member
    expect(catcher.drawsNothing, isTrue);
    await physicalMaterialResourcesLoad;
    // ignore: invalid_use_of_internal_member
    expect(catcher.drawsNothing, isTrue);
  });

  test('a failed request is reported once and not retried', () async {
    requestPhysicalMaterialResources();
    await physicalMaterialResourcesLoad;
    await pumpEventQueue();
    expect(reported, hasLength(1));

    // Materials keep asking every frame; none of that reloads or re-reports.
    requestPhysicalMaterialResources();
    expect(physicalMaterialResourcesPending, isFalse);
    PhysicallyBasedMaterial().clearcoat = 1.0;
    expect(physicalMaterialResourcesPending, isFalse);
    await pumpEventQueue();
    expect(reported, hasLength(1));
  });

  test('an explicit load retries after a failure and throws it', () async {
    requestPhysicalMaterialResources();
    await physicalMaterialResourcesLoad;
    await expectLater(initializePhysicalMaterialResources(), throwsA(anything));
    expect(physicalMaterialResourcesPending, isFalse);
  });
}
