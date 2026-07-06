// Minimal DICOM reader for the DICOM Volume example.
//
// Scope is deliberately narrow: enough to load the bundled reference head
// MRI (per-slice, uncompressed, little-endian). It handles explicit- and
// implicit-VR little-endian datasets and reads only the tags the volume
// renderer needs. Encapsulated/compressed pixel data (JPEG, JPEG-LS,
// JPEG2000, RLE) and big-endian transfer syntaxes are not supported.
//
// TODO(dicom): support encapsulated/compressed transfer syntaxes and
// big-endian; today only uncompressed little-endian is parsed.

import 'dart:typed_data';

/// One parsed DICOM image slice: the raw pixel samples plus the geometry and
/// intensity-mapping metadata needed to assemble and display a volume.
class DicomSlice {
  DicomSlice({
    required this.rows,
    required this.columns,
    required this.bitsAllocated,
    required this.bitsStored,
    required this.pixelRepresentation,
    required this.samplesPerPixel,
    required this.invertMonochrome,
    required this.rescaleSlope,
    required this.rescaleIntercept,
    required this.windowCenter,
    required this.windowWidth,
    required this.pixelSpacing,
    required this.sliceThickness,
    required this.imagePositionPatient,
    required this.imageOrientationPatient,
    required this.pixelData,
  });

  final int rows;
  final int columns;
  final int bitsAllocated;
  final int bitsStored;

  /// 0 = unsigned, 1 = two's-complement signed.
  final int pixelRepresentation;
  final int samplesPerPixel;

  /// True for PhotometricInterpretation MONOCHROME1 (min value is white).
  final bool invertMonochrome;

  final double rescaleSlope;
  final double rescaleIntercept;

  /// Suggested display window, or null if the file omits it.
  final double? windowCenter;
  final double? windowWidth;

  /// [rowSpacing, columnSpacing] in mm, or null.
  final List<double>? pixelSpacing;
  final double? sliceThickness;

  /// [x, y, z] of the top-left voxel in patient space (mm), or null.
  final List<double>? imagePositionPatient;

  /// Six direction cosines [rowX,rowY,rowZ, colX,colY,colZ], or null.
  final List<double>? imageOrientationPatient;

  /// Raw PixelData element bytes (little-endian samples).
  final Uint8List pixelData;

  /// Applies rescale slope/intercept to a stored sample, yielding the
  /// modality value (e.g. Hounsfield units for CT, arbitrary for MR).
  double rescale(num stored) => stored * rescaleSlope + rescaleIntercept;
}

/// Thrown when bytes are not a DICOM file we can read.
class DicomParseException implements Exception {
  DicomParseException(this.message);
  final String message;
  @override
  String toString() => 'DicomParseException: $message';
}

// Transfer syntax UIDs we understand.
const String _implicitVrLE = '1.2.840.10008.1.2';
const String _explicitVrLE = '1.2.840.10008.1.2.1';

// Tag constants, packed as (group << 16) | element.
const int _tagTransferSyntax = 0x00020010;
const int _tagSamplesPerPixel = 0x00280002;
const int _tagPhotometric = 0x00280004;
const int _tagRows = 0x00280010;
const int _tagColumns = 0x00280011;
const int _tagBitsAllocated = 0x00280100;
const int _tagBitsStored = 0x00280101;
const int _tagPixelRepresentation = 0x00280103;
const int _tagWindowCenter = 0x00281050;
const int _tagWindowWidth = 0x00281051;
const int _tagRescaleIntercept = 0x00281052;
const int _tagRescaleSlope = 0x00281053;
const int _tagPixelSpacing = 0x00280030;
const int _tagSliceThickness = 0x00180050;
const int _tagImagePosition = 0x00200032;
const int _tagImageOrientation = 0x00200037;
const int _tagPixelData = 0x7fe00010;

// VRs whose explicit-VR encoding uses a 2-byte reserved field followed by a
// 4-byte length (rather than an inline 2-byte length).
const Set<String> _longFormVrs = {'OB', 'OW', 'OF', 'OD', 'SQ', 'UT', 'UN'};

/// Parses a single DICOM file's [bytes] into a [DicomSlice].
DicomSlice parseDicom(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  // A conformant file has a 128-byte preamble then the "DICM" magic. Some
  // stripped files omit it and start at the dataset; tolerate both.
  int offset = 0;
  if (bytes.length > 132 &&
      bytes[128] == 0x44 && // D
      bytes[129] == 0x49 && // I
      bytes[130] == 0x43 && // C
      bytes[131] == 0x4d) {
    offset = 132;
  }

  // The file-meta group (0002,xxxx) is always explicit-VR little-endian and
  // carries the transfer syntax that governs the rest of the dataset.
  String transferSyntax = _explicitVrLE;
  final fields = <int, _RawElement>{};

  while (offset + 8 <= bytes.length) {
    final group = data.getUint16(offset, Endian.little);
    // Stop scanning the meta group once we leave group 0002.
    if (group != 0x0002) break;
    final element = _readElement(data, bytes, offset, explicitVr: true);
    if (element == null) break;
    fields[element.tag] = element;
    offset = element.nextOffset;
  }

  final tsElement = fields[_tagTransferSyntax];
  if (tsElement != null) {
    transferSyntax = _readString(bytes, tsElement).trim();
    // UIDs are null-padded to an even length.
    transferSyntax = transferSyntax.replaceAll('\x00', '');
  }

  if (transferSyntax != _implicitVrLE && transferSyntax != _explicitVrLE) {
    throw DicomParseException(
      'unsupported transfer syntax $transferSyntax '
      '(only uncompressed little-endian is supported)',
    );
  }
  final explicit = transferSyntax == _explicitVrLE;

  // Walk the main dataset, collecting the tags we need and stopping at
  // PixelData (which is the last thing we read).
  _RawElement? pixelElement;
  while (offset + 8 <= bytes.length) {
    final element = _readElement(data, bytes, offset, explicitVr: explicit);
    if (element == null) break;
    if (element.tag == _tagPixelData) {
      pixelElement = element;
      break;
    }
    fields[element.tag] = element;
    offset = element.nextOffset;
  }

  if (pixelElement == null) {
    throw DicomParseException('no PixelData element found');
  }

  int intField(int tag, int fallback) {
    final e = fields[tag];
    if (e == null) return fallback;
    return _readUint(data, e);
  }

  double? doubleField(int tag) {
    final e = fields[tag];
    if (e == null) return null;
    final parts = _readDecimals(bytes, e);
    return parts.isEmpty ? null : parts.first;
  }

  List<double>? listField(int tag) {
    final e = fields[tag];
    if (e == null) return null;
    final parts = _readDecimals(bytes, e);
    return parts.isEmpty ? null : parts;
  }

  final photometric = fields.containsKey(_tagPhotometric)
      ? _readString(bytes, fields[_tagPhotometric]!).trim()
      : 'MONOCHROME2';

  return DicomSlice(
    rows: intField(_tagRows, 0),
    columns: intField(_tagColumns, 0),
    bitsAllocated: intField(_tagBitsAllocated, 16),
    bitsStored: intField(_tagBitsStored, 16),
    pixelRepresentation: intField(_tagPixelRepresentation, 0),
    samplesPerPixel: intField(_tagSamplesPerPixel, 1),
    invertMonochrome: photometric == 'MONOCHROME1',
    rescaleSlope: doubleField(_tagRescaleSlope) ?? 1.0,
    rescaleIntercept: doubleField(_tagRescaleIntercept) ?? 0.0,
    windowCenter: doubleField(_tagWindowCenter),
    windowWidth: doubleField(_tagWindowWidth),
    pixelSpacing: listField(_tagPixelSpacing),
    sliceThickness: doubleField(_tagSliceThickness),
    imagePositionPatient: listField(_tagImagePosition),
    imageOrientationPatient: listField(_tagImageOrientation),
    pixelData: Uint8List.sublistView(
      bytes,
      pixelElement.valueOffset,
      pixelElement.valueOffset + pixelElement.length,
    ),
  );
}

/// A located element: its tag, where its value bytes start, and their length.
class _RawElement {
  _RawElement(this.tag, this.vr, this.valueOffset, this.length);
  final int tag;
  final String? vr;
  final int valueOffset;
  final int length;
  int get nextOffset => valueOffset + length;
}

/// Reads the element header at [offset] and returns its location, or null if
/// the bytes run out. Does not copy the value.
_RawElement? _readElement(
  ByteData data,
  Uint8List bytes,
  int offset, {
  required bool explicitVr,
}) {
  if (offset + 8 > bytes.length) return null;
  final group = data.getUint16(offset, Endian.little);
  final element = data.getUint16(offset + 2, Endian.little);
  final tag = (group << 16) | element;
  int p = offset + 4;

  String? vr;
  int length;
  if (explicitVr) {
    vr = String.fromCharCodes(bytes, p, p + 2);
    p += 2;
    if (_longFormVrs.contains(vr)) {
      p += 2; // reserved
      if (p + 4 > bytes.length) return null;
      length = data.getUint32(p, Endian.little);
      p += 4;
    } else {
      length = data.getUint16(p, Endian.little);
      p += 2;
    }
  } else {
    if (p + 4 > bytes.length) return null;
    length = data.getUint32(p, Endian.little);
    p += 4;
  }

  // Undefined length (0xFFFFFFFF) marks encapsulated pixel data or a sequence
  // with delimiters; we don't parse those.
  if (length == 0xffffffff) {
    throw DicomParseException(
      'undefined-length element (encapsulated/sequence) not supported',
    );
  }
  if (p + length > bytes.length) {
    // Clamp to available bytes rather than throwing on a truncated tail.
    length = bytes.length - p;
  }
  return _RawElement(tag, vr, p, length);
}

/// Reads an element's value as an unsigned integer (US/UL, or a numeric
/// string). Used for Rows/Columns/Bits/etc.
int _readUint(ByteData data, _RawElement e) {
  // US is the common case for these tags.
  if (e.length == 2) return data.getUint16(e.valueOffset, Endian.little);
  if (e.length == 4) return data.getUint32(e.valueOffset, Endian.little);
  // Fall back to a decimal/integer string.
  final s = String.fromCharCodes(
    Uint8List.sublistView(
      ByteData.sublistView(data),
      e.valueOffset,
      e.valueOffset + e.length,
    ),
  ).trim();
  return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
}

/// Reads an element's value as an ASCII string.
String _readString(Uint8List bytes, _RawElement e) {
  return String.fromCharCodes(bytes, e.valueOffset, e.valueOffset + e.length);
}

/// Reads a backslash-separated list of decimal strings (DS/IS multi-values).
List<double> _readDecimals(Uint8List bytes, _RawElement e) {
  final s = _readString(bytes, e);
  final out = <double>[];
  for (final part in s.split('\\')) {
    final v = double.tryParse(part.trim());
    if (v != null) out.add(v);
  }
  return out;
}
