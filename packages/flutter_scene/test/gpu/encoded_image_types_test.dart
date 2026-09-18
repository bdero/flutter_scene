import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fitWithin leaves an image inside the cap alone', () {
    expect(gpu.fitWithin(64, 32, 64), (64, 32));
    expect(gpu.fitWithin(1, 1, 1), (1, 1));
  });

  test('fitWithin scales the longest side to the cap, keeping aspect', () {
    expect(gpu.fitWithin(8192, 8192, 2048), (2048, 2048));
    expect(gpu.fitWithin(4096, 1024, 512), (512, 128));
    expect(gpu.fitWithin(1000, 300, 512), (512, 153));
    expect(gpu.fitWithin(300, 1000, 512), (153, 512));
  });

  test('fitWithin never collapses a side below one texel', () {
    expect(gpu.fitWithin(4096, 1, 16), (16, 1));
  });
}
