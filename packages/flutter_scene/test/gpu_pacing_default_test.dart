import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_test/flutter_test.dart';

const bool _webGpu = bool.fromEnvironment('flutter_scene.webgpu');

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('two frames in flight by default on Metal platforms and WebGPU', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final metal =
          platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
      expect(
        defaultMaxGpuFramesInFlight,
        kIsWeb ? (_webGpu ? 2 : 1) : (metal ? 2 : 1),
        reason: platform.name,
      );
    }
  });
}
