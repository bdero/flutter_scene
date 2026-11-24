import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gpu_available.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('two frames in flight by default on Metal platforms and web', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final metal =
          platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
      expect(
        defaultMaxGpuFramesInFlight,
        kIsWeb || metal ? 2 : 1,
        reason: platform.name,
      );
    }
  });

  test(
    'maxGpuFramesInFlight setter and dispose handle pacing transitions safely',
    () async {
      if (kIsWeb) {
        await gpu.initializeGpuBackend();
      }
      final scene = Scene();
      expect(scene.maxGpuFramesInFlight, defaultMaxGpuFramesInFlight);

      scene.maxGpuFramesInFlight = 3;
      expect(scene.maxGpuFramesInFlight, 3);

      scene.maxGpuFramesInFlight = 0;
      expect(scene.maxGpuFramesInFlight, 0);

      scene.dispose();
      // Updating maxGpuFramesInFlight or disposing again after dispose is safe.
      scene.maxGpuFramesInFlight = 1;
      expect(scene.maxGpuFramesInFlight, 1);
      scene.dispose();
    },
    skip: (kIsWeb || gpuAvailable()) ? false : 'Requires a GPU device.',
  );
}
