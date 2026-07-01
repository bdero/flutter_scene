/// Covers CPU mip-chain generation: chain sizing, and content-aware
/// downsampling (sRGB color averaged in linear light, data averaged directly,
/// normals averaged as vectors and renormalized).
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:test/test.dart';

Uint8List _solid(int w, int h, int r, int g, int b, int a) {
  final p = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    p[i * 4] = r;
    p[i * 4 + 1] = g;
    p[i * 4 + 2] = b;
    p[i * 4 + 3] = a;
  }
  return p;
}

void main() {
  test('mipLevelCountFor is floor(log2(max)) + 1', () {
    expect(mipLevelCountFor(256, 256), 9);
    expect(mipLevelCountFor(1, 1), 1);
    expect(mipLevelCountFor(8, 2), 4);
  });

  test('chain halves down to 1x1 with level 0 first', () {
    final chain = generateMipChain(
      _solid(4, 4, 10, 20, 30, 255),
      4,
      4,
      TextureContent.data,
    );
    expect(chain.map((l) => '${l.width}x${l.height}'), ['4x4', '2x2', '1x1']);
    // A solid image stays solid at every level.
    expect(chain.last.pixels, [10, 20, 30, 255]);
  });

  test('color content averages in linear light, not naively', () {
    // A 2x2 checker of black and white. Naive byte average = 127; correct
    // linear average is 0.5 in linear -> ~188 in sRGB.
    final pixels = Uint8List.fromList([
      0, 0, 0, 255, // black
      255, 255, 255, 255, // white
      255, 255, 255, 255, // white
      0, 0, 0, 255, // black
    ]);
    final chain = generateMipChain(pixels, 2, 2, TextureContent.color);
    final mip = chain[1].pixels; // 1x1
    expect(mip[0], greaterThan(180));
    expect(mip[0], lessThan(195));
  });

  test('data content averages bytes directly', () {
    final pixels = Uint8List.fromList([
      0, 0, 0, 0, //
      255, 255, 255, 255, //
      255, 255, 255, 255, //
      0, 0, 0, 0, //
    ]);
    final chain = generateMipChain(pixels, 2, 2, TextureContent.data);
    expect(chain[1].pixels, [128, 128, 128, 128]);
  });

  test('normal content renormalizes to a unit vector', () {
    // Flat normals (0,0,1) encoded as (128,128,255) stay flat.
    final chain = generateMipChain(
      _solid(2, 2, 128, 128, 255, 255),
      2,
      2,
      TextureContent.normal,
    );
    final mip = chain[1].pixels;
    expect(mip[0], closeTo(128, 1));
    expect(mip[1], closeTo(128, 1));
    expect(mip[2], closeTo(255, 1));
  });
}
