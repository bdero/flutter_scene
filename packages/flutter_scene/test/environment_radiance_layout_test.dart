import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps Android native environments on the legacy radiance atlas', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        backendSupportsMips: true,
      ),
      isFalse,
    );
  });

  test('keeps the cubemap layout on web and non-Android native backends', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
        backendSupportsMips: true,
      ),
      isTrue,
    );
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.macOS,
        backendSupportsMips: true,
      ),
      isTrue,
    );
  });

  test('uses the atlas when the backend does not support manually written mips', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.macOS,
        backendSupportsMips: false,
      ),
      isFalse,
    );
  });
}
