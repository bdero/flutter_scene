import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
