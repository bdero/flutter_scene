// Covers the .cube parser and the blue-slice strip packing; the GPU upload
// itself is exercised by the example app and smoke coverage.

// ignore: implementation_imports
import 'package:flutter_scene/src/post_process/color_lut.dart';
import 'package:flutter_test/flutter_test.dart';

const _identity2 = '''
# comment
TITLE "identity"
LUT_3D_SIZE 2
0.0 0.0 0.0
1.0 0.0 0.0
0.0 1.0 0.0
1.0 1.0 0.0
0.0 0.0 1.0
1.0 0.0 1.0
0.0 1.0 1.0
1.0 1.0 1.0
''';

void main() {
  test('parses a 2x2x2 identity cube red-fastest', () {
    final table = parseCubeTable(_identity2);
    expect(table.size, 2);
    expect(table.values.length, 24);
    // Second row is red=1: (1, 0, 0).
    expect(table.values.sublist(3, 6), [1.0, 0.0, 0.0]);
    // Fifth row is blue=1: (0, 0, 1).
    expect(table.values.sublist(12, 15), [0.0, 0.0, 1.0]);
  });

  test('packs the strip with blue slices side by side', () {
    final bytes = packCubeStrip(parseCubeTable(_identity2));
    // Strip is 4 wide (2 slices of 2) and 2 tall.
    expect(bytes.length, 4 * 2 * 4);
    int r(int x, int y) => bytes[(y * 4 + x) * 4];
    int g(int x, int y) => bytes[(y * 4 + x) * 4 + 1];
    int b(int x, int y) => bytes[(y * 4 + x) * 4 + 2];
    // Slice 0 (blue=0): x is red, y is green.
    expect([r(1, 0), g(1, 0), b(1, 0)], [255, 0, 0]);
    expect([r(0, 1), g(0, 1), b(0, 1)], [0, 255, 0]);
    // Slice 1 (blue=1) starts at x=2.
    expect([r(2, 0), g(2, 0), b(2, 0)], [0, 0, 255]);
    expect([r(3, 1), g(3, 1), b(3, 1)], [255, 255, 255]);
  });

  test('rejects truncated and 1D tables', () {
    expect(() => parseCubeTable('LUT_3D_SIZE 2\n0 0 0\n'), throwsArgumentError);
    expect(() => parseCubeTable('LUT_1D_SIZE 4\n'), throwsArgumentError);
  });
}
