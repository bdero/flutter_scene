@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/iwer_bundle.g.dart';

// Paths are relative to the package directory, where flutter test runs.
const _vendored = 'third_party/iwer/iwer.min.js';
const _smokeRenderCopy =
    '../../examples/smoke_render/web/third_party/iwer/iwer.min.js';
const _refresh = 'Rerun `dart run tool/vendor_iwer.dart`.';

// The first differing offset, or -1 when the lists match.
int _firstDifference(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : n;
}

void main() {
  test('the embedded IWER bundle matches the vendored copies', () {
    final embedded = base64.decode(iwerBundleBase64);
    expect(
      embedded,
      hasLength(iwerBundleLength),
      reason: 'iwerBundleLength disagrees with the embedded bytes. $_refresh',
    );
    for (final path in [_vendored, _smokeRenderCopy]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing.');
      final bytes = file.readAsBytesSync();
      expect(
        bytes,
        hasLength(embedded.length),
        reason: '$path differs in size from the embedded bundle. $_refresh',
      );
      expect(
        _firstDifference(bytes, embedded),
        -1,
        reason:
            '$path differs from the embedded bundle at this offset. '
            '$_refresh',
      );
    }
  });
}
