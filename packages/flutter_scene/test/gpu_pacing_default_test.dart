import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('two frames in flight by default only on Metal platforms', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final metal =
          platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
      expect(
        defaultMaxGpuFramesInFlight,
        metal && !kIsWeb ? 2 : 1,
        reason: platform.name,
      );
    }
  });
}
