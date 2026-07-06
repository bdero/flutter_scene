import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/splats/splat_sort_service.dart';

void main() {
  test('sorts through the background worker and survives reuse', () async {
    // Five splats along +Z.
    final positions = Float32List.fromList([
      0, 0, 0, //
      0, 0, 1, //
      0, 0, 2, //
      0, 0, 3, //
      0, 0, 4, //
    ]);
    final service = SplatSortService(positions, 5);

    final backToFront = await service.sort(0, 0, 1);
    expect(backToFront, [4, 3, 2, 1, 0]);

    // A second request reuses the same worker; the reversed direction
    // reverses the order.
    final frontToBack = await service.sort(0, 0, -1);
    expect(frontToBack, [0, 1, 2, 3, 4]);

    service.dispose();
    expect(await service.sort(0, 0, 1), isNull);
  });
}
