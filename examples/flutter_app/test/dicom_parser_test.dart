// Byte-level tests for the minimal DICOM reader used by the DICOM Volume
// example. Rather than hypothesize about parsing, these synthesize a known
// explicit-VR little-endian file in memory and assert every tag and pixel
// value round-trips exactly (the importer-verification methodology used
// across this repo).

import 'dart:typed_data';

import 'package:example_app/dicom/dicom_parser.dart';
import 'package:example_app/dicom/dicom_volume.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal explicit-VR little-endian DICOM file.
class _DicomBuilder {
  final BytesBuilder _b = BytesBuilder();

  void _tag(int group, int element) {
    final t = ByteData(4)
      ..setUint16(0, group, Endian.little)
      ..setUint16(2, element, Endian.little);
    _b.add(t.buffer.asUint8List());
  }

  /// A short-form explicit element (VR with an inline 16-bit length).
  void shortElement(int group, int element, String vr, Uint8List value) {
    _tag(group, element);
    _b.add(Uint8List.fromList(vr.codeUnits));
    final len = ByteData(2)..setUint16(0, value.length, Endian.little);
    _b.add(len.buffer.asUint8List());
    _b.add(value);
  }

  /// A long-form explicit element (OW/OB/etc: reserved + 32-bit length).
  void longElement(int group, int element, String vr, Uint8List value) {
    _tag(group, element);
    _b.add(Uint8List.fromList(vr.codeUnits));
    final header = ByteData(6)..setUint32(2, value.length, Endian.little);
    _b.add(header.buffer.asUint8List());
    _b.add(value);
  }

  void us(int group, int element, int value) {
    final v = ByteData(2)..setUint16(0, value, Endian.little);
    shortElement(group, element, 'US', v.buffer.asUint8List());
  }

  void ds(int group, int element, String value) {
    // DS is a string, padded to even length with a trailing space.
    var s = value;
    if (s.length.isOdd) s = '$s ';
    shortElement(group, element, 'DS', Uint8List.fromList(s.codeUnits));
  }

  void ui(int group, int element, String value) {
    var s = value;
    if (s.length.isOdd) s = '$s\x00';
    shortElement(group, element, 'UI', Uint8List.fromList(s.codeUnits));
  }

  Uint8List build() {
    final out = BytesBuilder();
    out.add(Uint8List(128)); // preamble
    out.add(Uint8List.fromList('DICM'.codeUnits));
    out.add(_b.toBytes());
    return out.toBytes();
  }
}

/// Packs 16-bit little-endian samples into a pixel-data payload.
Uint8List _pixels16(List<int> values) {
  final data = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    data.setUint16(i * 2, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('parseDicom', () {
    test('reads tags and pixel data from an explicit-VR file', () {
      final b = _DicomBuilder()
        ..ui(0x0002, 0x0010, '1.2.840.10008.1.2.1') // explicit VR LE
        ..us(0x0028, 0x0010, 2) // Rows
        ..us(0x0028, 0x0011, 3) // Columns
        ..us(0x0028, 0x0100, 16) // BitsAllocated
        ..us(0x0028, 0x0101, 16) // BitsStored
        ..us(0x0028, 0x0103, 0) // PixelRepresentation (unsigned)
        ..ds(0x0028, 0x1052, '-10') // RescaleIntercept
        ..ds(0x0028, 0x1053, '2') // RescaleSlope
        ..ds(0x0028, 0x0030, '0.5\\0.75') // PixelSpacing [row, col]
        ..longElement(
          0x7fe0,
          0x0010,
          'OW',
          _pixels16([10, 20, 30, 40, 50, 60]),
        );

      final slice = parseDicom(b.build());

      expect(slice.rows, 2);
      expect(slice.columns, 3);
      expect(slice.bitsAllocated, 16);
      expect(slice.pixelRepresentation, 0);
      expect(slice.rescaleIntercept, -10);
      expect(slice.rescaleSlope, 2);
      expect(slice.pixelSpacing, [0.5, 0.75]);
      expect(slice.pixelData.length, 12);
      // Rescale maps stored 10 -> 2*10 - 10 = 10.
      expect(slice.rescale(10), 10);
      expect(slice.rescale(60), 110);
    });

    test('tolerates a missing preamble', () {
      final full =
          (_DicomBuilder()
                ..ui(0x0002, 0x0010, '1.2.840.10008.1.2.1')
                ..us(0x0028, 0x0010, 1)
                ..us(0x0028, 0x0011, 1)
                ..us(0x0028, 0x0100, 16)
                ..us(0x0028, 0x0101, 16)
                ..us(0x0028, 0x0103, 0)
                ..longElement(0x7fe0, 0x0010, 'OW', _pixels16([42])))
              .build();
      // Strip the 128-byte preamble + "DICM"; the parser should still start
      // reading the dataset from offset 0.
      final stripped = Uint8List.sublistView(full, 132);
      final slice = parseDicom(stripped);
      expect(slice.rows, 1);
      expect(slice.columns, 1);
    });

    test('rejects an unsupported (compressed) transfer syntax', () {
      final b = _DicomBuilder()
        ..ui(0x0002, 0x0010, '1.2.840.10008.1.2.4.90') // JPEG 2000
        ..us(0x0028, 0x0010, 1);
      expect(() => parseDicom(b.build()), throwsA(isA<DicomParseException>()));
    });
  });

  group('buildVolume', () {
    DicomSlice sliceAt(double z, List<int> pixels) {
      final b = _DicomBuilder()
        ..ui(0x0002, 0x0010, '1.2.840.10008.1.2.1')
        ..us(0x0028, 0x0010, 1) // Rows
        ..us(0x0028, 0x0011, 2) // Columns
        ..us(0x0028, 0x0100, 16)
        ..us(0x0028, 0x0101, 16)
        ..us(0x0028, 0x0103, 0)
        ..ds(0x0020, 0x0032, '0\\0\\$z') // ImagePositionPatient
        ..ds(0x0020, 0x0037, '1\\0\\0\\0\\1\\0') // orientation (normal +z)
        ..longElement(0x7fe0, 0x0010, 'OW', _pixels16(pixels));
      return parseDicom(b.build());
    }

    test('orders slices by ImagePositionPatient, not input order', () {
      // Supplied out of order; z=0 should end up first.
      final volume = buildVolume([
        sliceAt(2.0, [100, 100]),
        sliceAt(0.0, [0, 10]),
        sliceAt(1.0, [50, 50]),
      ]);

      expect(volume.width, 2);
      expect(volume.height, 1);
      expect(volume.depth, 3);
      // First slice (z=0) carries the [0, 10] samples.
      expect(volume.voxels[0], 0);
      expect(volume.voxels[1], 10);
      // Last slice (z=2) carries [100, 100].
      expect(volume.voxels[4], 100);
      expect(volume.minValue, 0);
      expect(volume.maxValue, 100);
      // Slice spacing inferred from consecutive positions (1 mm).
      expect(volume.spacing[2], closeTo(1.0, 1e-9));
    });

    test('inverts MONOCHROME1 so larger reads brighter', () {
      final b = _DicomBuilder()
        ..ui(0x0002, 0x0010, '1.2.840.10008.1.2.1')
        ..shortElement(
          0x0028,
          0x0004,
          'CS',
          Uint8List.fromList('MONOCHROME1 '.codeUnits),
        )
        ..us(0x0028, 0x0010, 1)
        ..us(0x0028, 0x0011, 2)
        ..us(0x0028, 0x0100, 16)
        ..us(0x0028, 0x0101, 12) // 12 bits stored -> max 4095
        ..us(0x0028, 0x0103, 0)
        ..longElement(0x7fe0, 0x0010, 'OW', _pixels16([0, 4095]));
      final volume = buildVolume([parseDicom(b.build())]);
      // Stored 0 -> 4095, stored 4095 -> 0 after inversion.
      expect(volume.voxels[0], 4095);
      expect(volume.voxels[1], 0);
    });
  });
}
