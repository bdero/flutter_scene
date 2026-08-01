import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android stays on the atlas until the probe confirms mip sampling', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        backendSupportsMips: true,
        platformMipSamplingWorks: null,
      ),
      isFalse,
    );
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        backendSupportsMips: true,
        platformMipSamplingWorks: false,
      ),
      isFalse,
    );
  });

  test('Android uses the cube layout once the probe passes', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        backendSupportsMips: true,
        platformMipSamplingWorks: true,
      ),
      isTrue,
    );
  });

  test('web and non-Android native backends trust the capability bits', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
        backendSupportsMips: true,
        platformMipSamplingWorks: null,
      ),
      isTrue,
    );
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.macOS,
        backendSupportsMips: true,
        platformMipSamplingWorks: null,
      ),
      isTrue,
    );
  });

  test('uses the atlas when the backend does not support manual mips', () {
    expect(
      EnvironmentMap.shouldUseMipRadianceLayout(
        isWeb: false,
        targetPlatform: TargetPlatform.macOS,
        backendSupportsMips: false,
        platformMipSamplingWorks: true,
      ),
      isFalse,
    );
  });
}
