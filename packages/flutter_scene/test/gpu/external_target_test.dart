// ignore_for_file: implementation_imports
@TestOn('vm')
library;

import 'package:flutter_scene/src/gpu/external_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter GPU reports no external targets', () {
    expect(externalColorTargetsSupported, isFalse);
    expect(nativeGraphicsContext, isNull);
    expect(
      () => wrapExternalColorTarget(Object(), width: 1, height: 1),
      throwsUnsupportedError,
    );
  });
}
