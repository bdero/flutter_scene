// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:test/test.dart';

void main() {
  test('matches the published FNV-1a 32-bit vectors', () {
    expect(sidecarBundleHash(<int>[]), '811c9dc5');
    expect(sidecarBundleHash(utf8.encode('a')), 'e40c292c');
    expect(sidecarBundleHash(utf8.encode('foobar')), 'bf9cf968');
  });
}
