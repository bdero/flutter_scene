// Covers the pure-Dart half of EnvironmentMap.fromKtx2Bytes: the container
// parse, the format decode, the mip-to-roughness remap, the face placement,
// and the band-atlas fallback. The GPU upload is a handful of
// createTexture/overwrite calls and needs a device, so it is not exercised
// here.
//
// Every fixture is assembled in-test. A real glTF-IBL-Sampler cubemap is
// several megabytes even at the smallest face size the layout allows, too
// large to carry in a published package, and it would not cover any code path
// the synthetic files miss.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/material/ibl_ktx2.dart';
import 'package:flutter_scene/src/render/radiance_layout.dart';
import 'package:flutter_scene/src/texture/half_float.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _vkRgba8Unorm = 37;
const int _vkRgba8Srgb = 43;
const int _vkRgba16Sfloat = 97;
const int _vkRgba32Sfloat = 109;
const int _vkE5b9g9r9 = 123;
const int _vkBc7SrgbBlock = 146;

/// The base face size fixtures use, the smallest the radiance layout allows.
const int _size = kMinRadianceCubeSize;

int _bytesPerTexel(int vkFormat) => switch (vkFormat) {
  _vkRgba32Sfloat => 16,
  _vkRgba16Sfloat => 8,
  _ => 4,
};

/// Encodes one texel of [vkFormat] into [out] at [offset].
void _encodeTexel(int vkFormat, Vector3 rgb, ByteData out, int offset) {
  switch (vkFormat) {
    case _vkRgba8Unorm:
    case _vkRgba8Srgb:
      out.setUint8(offset, (rgb.x * 255.0).round().clamp(0, 255));
      out.setUint8(offset + 1, (rgb.y * 255.0).round().clamp(0, 255));
      out.setUint8(offset + 2, (rgb.z * 255.0).round().clamp(0, 255));
      out.setUint8(offset + 3, 255);
    case _vkRgba16Sfloat:
      out.setUint16(offset, floatToHalfBits(rgb.x), Endian.little);
      out.setUint16(offset + 2, floatToHalfBits(rgb.y), Endian.little);
      out.setUint16(offset + 4, floatToHalfBits(rgb.z), Endian.little);
      out.setUint16(offset + 6, floatToHalfBits(1.0), Endian.little);
    case _vkRgba32Sfloat:
      out.setFloat32(offset, rgb.x, Endian.little);
      out.setFloat32(offset + 4, rgb.y, Endian.little);
      out.setFloat32(offset + 8, rgb.z, Endian.little);
      out.setFloat32(offset + 12, 1.0, Endian.little);
    case _vkE5b9g9r9:
      out.setUint32(offset, _packRgb9e5(rgb), Endian.little);
    default:
      throw ArgumentError('No encoder for vkFormat $vkFormat');
  }
}

/// Packs linear [rgb] into a shared-exponent RGB9E5 word, the way a bake tool
/// would.
int _packRgb9e5(Vector3 rgb) {
  const maxMantissa = 511;
  final peak = math.max(math.max(rgb.x, rgb.y), rgb.z).clamp(0.0, 65408.0);
  if (peak <= 0.0) return 0;
  var exponent = (math.log(peak) / math.ln2).floor() + 1 + 15;
  exponent = exponent.clamp(0, 31);
  final scale = math.pow(2.0, 24 - exponent).toDouble();
  final r = (rgb.x * scale).round().clamp(0, maxMantissa);
  final g = (rgb.y * scale).round().clamp(0, maxMantissa);
  final b = (rgb.z * scale).round().clamp(0, maxMantissa);
  // Assembled arithmetically; the exponent lands above bit 31 under dart2js
  // bitwise semantics if shifted.
  return r + g * 512 + b * 262144 + exponent * 134217728;
}

/// The linear color fixture face [face] is filled with, distinct per face so
/// misplacement is visible.
Vector3 _faceColor(int face, int level) =>
    Vector3(0.1 * (face + 1), 0.05 * (level + 1), 0.5);

/// Wraps [payload] in a zstd frame of raw blocks. Exercises the container's
/// supercompression path without needing a compressor; the compressed-block
/// decoder has its own reference-CLI coverage in test/texture/zstd_test.dart.
Uint8List _zstdRawFrame(Uint8List payload) {
  final out = BytesBuilder();
  out.add(<int>[0x28, 0xB5, 0x2F, 0xFD]);
  out.addByte(0xA0); // single segment, 4-byte frame content size
  final size = ByteData(4)..setUint32(0, payload.length, Endian.little);
  out.add(size.buffer.asUint8List());
  const maxBlock = 1 << 16;
  var offset = 0;
  do {
    final take = math.min(maxBlock, payload.length - offset);
    final last = offset + take >= payload.length;
    final header = take * 8 + (last ? 1 : 0); // size<<3 | type 0 | last
    out.add(<int>[
      header & 0xff,
      (header >>> 8) & 0xff,
      (header >>> 16) & 0xff,
    ]);
    out.add(Uint8List.sublistView(payload, offset, offset + take));
    offset += take;
  } while (offset < payload.length);
  return out.toBytes();
}

/// Builds a KTX2 cubemap whose every texel of level `l`, face `f` is
/// [color] `(l, f)`.
Uint8List _cubeKtx2({
  int vkFormat = _vkRgba16Sfloat,
  int size = _size,
  int levelCount = kPrefilterBandCount,
  bool zstd = false,
  int faceCount = 6,
  int? pixelHeight,
  Map<String, Uint8List> keyValues = const {},
  Vector3 Function(int face, int level) color = _faceColor,
}) {
  final bytesPerTexel = _bytesPerTexel(vkFormat);
  final levels = <Ktx2Level>[];
  for (var level = 0; level < levelCount; level++) {
    final levelSize = math.max(1, size >> level);
    final texels = levelSize * levelSize;
    final payload = Uint8List(texels * bytesPerTexel * faceCount);
    final view = ByteData.sublistView(payload);
    for (var face = 0; face < faceCount; face++) {
      final rgb = color(face, level);
      for (var i = 0; i < texels; i++) {
        _encodeTexel(vkFormat, rgb, view, (face * texels + i) * bytesPerTexel);
      }
    }
    levels.add(
      Ktx2Level(
        data: zstd ? _zstdRawFrame(payload) : payload,
        uncompressedByteLength: payload.length,
      ),
    );
  }
  return writeKtx2(
    Ktx2Texture(
      vkFormat: vkFormat,
      typeSize: vkFormat == _vkRgba16Sfloat ? 2 : 4,
      pixelWidth: size,
      pixelHeight: pixelHeight ?? size,
      faceCount: faceCount,
      levels: levels,
      supercompression: zstd
          ? Ktx2Supercompression.zstandard
          : Ktx2Supercompression.none,
      keyValues: keyValues,
      levelAlignment: 4,
    ),
  );
}

/// The RGBA of texel ([x], [y]) of [face] in [mip] of a decoded cube.
List<double> _cubeTexel(
  ImportedRadianceCube cube,
  int mip,
  int face,
  int x,
  int y,
) {
  final size = math.max(1, cube.baseSize >> mip);
  final o = (y * size + x) * 4;
  return [
    for (var c = 0; c < 4; c++) halfBitsToDouble(cube.mips[mip][face][o + c]),
  ];
}

/// The face and face-relative UV the GL/Vulkan cube map specification assigns
/// to [direction], transcribed from the specification's major-axis table
/// rather than from the engine's own bases, so the two are independent.
({int face, double u, double v}) _specCubeFace(Vector3 direction) {
  final ax = direction.x.abs();
  final ay = direction.y.abs();
  final az = direction.z.abs();
  final int face;
  final double sc;
  final double tc;
  final double ma;
  if (ax >= ay && ax >= az) {
    ma = ax;
    if (direction.x > 0) {
      face = 0;
      sc = -direction.z;
      tc = -direction.y;
    } else {
      face = 1;
      sc = direction.z;
      tc = -direction.y;
    }
  } else if (ay >= az) {
    ma = ay;
    if (direction.y > 0) {
      face = 2;
      sc = direction.x;
      tc = direction.z;
    } else {
      face = 3;
      sc = direction.x;
      tc = -direction.z;
    }
  } else {
    ma = az;
    if (direction.z > 0) {
      face = 4;
      sc = direction.x;
      tc = -direction.y;
    } else {
      face = 5;
      sc = -direction.x;
      tc = -direction.y;
    }
  }
  return (face: face, u: 0.5 * (sc / ma) + 0.5, v: 0.5 * (tc / ma) + 0.5);
}

void main() {
  group('cube face convention', () {
    test('the engine bases are the KTX2/GL cube mapping, so no remap', () {
      // The loader writes file face i to cube slice i verbatim. That is only
      // correct if the engine's own face bases (which the GPU prefilter writes
      // through, see prefilterEquirectRadianceCubeFace) agree with the
      // convention KTX2 stores. Round-trip every face through the
      // specification's table to prove they do.
      for (var face = 0; face < 6; face++) {
        for (final u in <double>[0.02, 0.25, 0.5, 0.75, 0.98]) {
          for (final v in <double>[0.02, 0.25, 0.5, 0.75, 0.98]) {
            final direction = radianceCubeFaceDirection(face, u, v);
            final spec = _specCubeFace(direction);
            expect(spec.face, face, reason: 'face $face at ($u, $v)');
            expect(spec.u, closeTo(u, 1e-6));
            expect(spec.v, closeTo(v, 1e-6));
          }
        }
      }
    });

    test('radianceCubeFaceCoords inverts radianceCubeFaceDirection', () {
      for (var face = 0; face < 6; face++) {
        for (final u in <double>[0.1, 0.5, 0.9]) {
          for (final v in <double>[0.1, 0.5, 0.9]) {
            final coords = radianceCubeFaceCoords(
              radianceCubeFaceDirection(face, u, v),
            );
            expect(coords.face, face);
            expect(coords.u, closeTo(u, 1e-6));
            expect(coords.v, closeTo(v, 1e-6));
          }
        }
      }
    });

    test('file face order lands on the matching cube slice unflipped', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2());
      for (var face = 0; face < 6; face++) {
        final expected = _faceColor(face, 0);
        for (final (x, y) in <(int, int)>[
          (0, 0),
          (_size - 1, 0),
          (0, _size - 1),
          (_size ~/ 2, _size ~/ 2),
        ]) {
          final texel = _cubeTexel(cube, 0, face, x, y);
          expect(texel[0], closeTo(expected.x, 1e-3), reason: 'face $face');
          expect(texel[1], closeTo(expected.y, 1e-3));
          expect(texel[2], closeTo(expected.z, 1e-3));
        }
      }
    });
  });

  group('format decode', () {
    test('float16 faces decode to their linear values', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2());
      expect(cube.baseSize, _size);
      expect(cube.mips.length, kPrefilterBandCount);
      expect(_cubeTexel(cube, 0, 2, 0, 0)[0], closeTo(0.3, 1e-3));
    });

    test('float32 faces decode to their linear values', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2(vkFormat: _vkRgba32Sfloat));
      expect(_cubeTexel(cube, 0, 5, 0, 0)[0], closeTo(0.6, 1e-3));
    });

    test('rgba8 unorm is taken as linear', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2(vkFormat: _vkRgba8Unorm));
      // 0.3 quantized to 8 bits, no transfer function applied.
      expect(_cubeTexel(cube, 0, 2, 0, 0)[0], closeTo(0.3, 2e-3));
    });

    test('rgba8 srgb is linearized', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2(vkFormat: _vkRgba8Srgb));
      final encoded = (0.3 * 255).round() / 255.0;
      final linear = math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
      expect(_cubeTexel(cube, 0, 2, 0, 0)[0], closeTo(linear, 2e-3));
    });

    test('shared-exponent RGB9E5 decodes to linear radiance above 1', () {
      Vector3 bright(int face, int level) => Vector3(4.0, 8.0, 16.0);
      final cube = decodeKtx2RadianceCube(
        _cubeKtx2(vkFormat: _vkE5b9g9r9, color: bright),
      );
      final texel = _cubeTexel(cube, 0, 0, 0, 0);
      expect(texel[0], closeTo(4.0, 0.05));
      expect(texel[1], closeTo(8.0, 0.05));
      expect(texel[2], closeTo(16.0, 0.05));
      expect(texel[3], 1.0);
    });

    test('zstd-supercompressed levels decompress', () {
      final plain = decodeKtx2RadianceCube(_cubeKtx2());
      final compressed = decodeKtx2RadianceCube(_cubeKtx2(zstd: true));
      expect(compressed.mips[0][3], plain.mips[0][3]);
      expect(compressed.mips[7][3], plain.mips[7][3]);
    });
  });

  group('mip to roughness', () {
    test('an eight-level chain maps one to one', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2());
      for (var mip = 0; mip < kPrefilterBandCount; mip++) {
        final size = math.max(1, cube.baseSize >> mip);
        expect(cube.mips[mip][0].length, size * size * 4, reason: 'mip $mip');
        expect(
          _cubeTexel(cube, mip, 0, 0, 0)[1],
          closeTo(_faceColor(0, mip).y, 1e-3),
          reason: 'mip $mip',
        );
      }
    });

    test('a shorter chain is resampled onto eight roughness bands', () {
      // Four source levels, so source level j sits at roughness j/3 and engine
      // band i wants roughness i/7. Band 3 lands 3/7 * 3 = 1.286 source levels
      // in: level 1 blended 0.286 of the way toward level 2.
      final cube = decodeKtx2RadianceCube(_cubeKtx2(levelCount: 4));
      expect(cube.mips.length, kPrefilterBandCount);
      expect(
        _cubeTexel(cube, 0, 0, 0, 0)[1],
        closeTo(_faceColor(0, 0).y, 1e-3),
      );
      expect(
        _cubeTexel(cube, 7, 0, 0, 0)[1],
        closeTo(_faceColor(0, 3).y, 1e-3),
      );
      final low = _faceColor(0, 1).y;
      final band3 = low + (_faceColor(0, 2).y - low) * (3 * 3 / 7 - 1);
      expect(_cubeTexel(cube, 3, 0, 0, 0)[1], closeTo(band3, 1e-3));
    });

    test('a longer chain is resampled onto eight roughness bands', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2(levelCount: 9));
      expect(cube.mips.length, kPrefilterBandCount);
      // Band 7 is fully rough, so it reads the source's last (roughest) level.
      expect(
        _cubeTexel(cube, 7, 0, 0, 0)[1],
        closeTo(_faceColor(0, 8).y, 1e-3),
      );
    });

    test('a base-only file spreads its single level across every band', () {
      final cube = decodeKtx2RadianceCube(_cubeKtx2(levelCount: 1));
      expect(cube.mips.length, kPrefilterBandCount);
      for (var mip = 0; mip < kPrefilterBandCount; mip++) {
        expect(_cubeTexel(cube, mip, 4, 0, 0)[0], closeTo(0.5, 1e-3));
      }
    });
  });

  group('band atlas fallback', () {
    test('flattens the cube onto the stacked-band equirect layout', () {
      final atlas = decodeKtx2RadianceAtlas(_cubeKtx2());
      expect(atlas.width, kPrefilterBandWidth);
      expect(atlas.height, kPrefilterBandHeight * kPrefilterBandCount);
      // Every atlas texel must hold the color of the face the shader's own
      // equirect projection points at, in the band's own source level.
      for (final band in <int>[0, 3, 7]) {
        for (final (x, y) in <(int, int)>[
          (10, 10),
          (kPrefilterBandWidth ~/ 2, kPrefilterBandHeight ~/ 2),
          (kPrefilterBandWidth - 5, kPrefilterBandHeight - 5),
        ]) {
          final direction = equirectUvToDirection(
            (x + 0.5) / kPrefilterBandWidth,
            (y + 0.5) / kPrefilterBandHeight,
          );
          final face = radianceCubeFaceCoords(direction).face;
          final expected = _faceColor(face, band);
          final o = ((band * kPrefilterBandHeight + y) * atlas.width + x) * 4;
          expect(
            halfBitsToDouble(atlas.pixels[o]),
            closeTo(expected.x, 2e-3),
            reason: 'band $band at ($x, $y) should read face $face',
          );
          expect(
            halfBitsToDouble(atlas.pixels[o + 1]),
            closeTo(expected.y, 2e-3),
          );
        }
      }
    });
  });

  group('diffuse spherical harmonics metadata', () {
    test('coefficients ride in the file key/value data', () {
      final sh = <Vector3>[
        for (var i = 0; i < kDiffuseShCoefficientCount; i++)
          Vector3(i * 0.1, i * 0.2, i * 0.3),
      ];
      final bytes = _cubeKtx2(
        keyValues: {kDiffuseShKtx2Key: encodeDiffuseShSidecar(sh)},
      );
      final read = readKtx2DiffuseSh(bytes);
      expect(read, isNotNull);
      for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
        expect(read![i].x, closeTo(sh[i].x, 1e-6));
        expect(read[i].z, closeTo(sh[i].z, 1e-6));
      }
      expect(
        decodeKtx2RadianceCube(bytes).diffuseSphericalHarmonics,
        isNotNull,
      );
    });

    test('a file without the key carries no coefficients', () {
      expect(readKtx2DiffuseSh(_cubeKtx2()), isNull);
      expect(
        decodeKtx2RadianceCube(_cubeKtx2()).diffuseSphericalHarmonics,
        isNull,
      );
    });

    test('malformed metadata is a FormatException', () {
      final bytes = _cubeKtx2(keyValues: {kDiffuseShKtx2Key: Uint8List(12)});
      expect(() => readKtx2DiffuseSh(bytes), throwsA(isA<FormatException>()));
    });
  });

  group('malformed files', () {
    void expectRejected(String reason, Uint8List Function() build) {
      test(reason, () {
        expect(
          () => decodeKtx2RadianceCube(build()),
          throwsA(isA<FormatException>()),
          reason: reason,
        );
      });
    }

    expectRejected('not a KTX2 file at all', () => Uint8List(200));
    expectRejected(
      'a 2D texture rather than a cubemap',
      () => _cubeKtx2(faceCount: 1),
    );
    expectRejected('non-square faces', () => _cubeKtx2(pixelHeight: 128));
    expectRejected(
      'faces below the layout minimum',
      () => _cubeKtx2(size: _size ~/ 2, levelCount: 7),
    );
    expectRejected('a block-compressed payload', () {
      final bytes = _cubeKtx2();
      // Claim BC7 while carrying uncompressed texels; the format check is what
      // must reject it, before any payload is touched.
      ByteData.sublistView(bytes).setUint32(12, _vkBc7SrgbBlock, Endian.little);
      return bytes;
    });
    expectRejected('a truncated level payload', () {
      final bytes = _cubeKtx2();
      // Shrink the base level's stored length so the payload runs short of six
      // faces. Level 0's index entry starts right after the 80-byte header.
      final data = ByteData.sublistView(bytes);
      final length = data.getUint32(88, Endian.little);
      data.setUint32(88, length ~/ 2, Endian.little);
      return bytes;
    });
    expectRejected('an unsupported supercompression scheme', () {
      final bytes = _cubeKtx2();
      ByteData.sublistView(bytes).setUint32(44, 3, Endian.little); // zlib
      return bytes;
    });
  });
}
