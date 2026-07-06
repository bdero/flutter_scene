// Assembles parsed DICOM slices into a single scalar volume ready to pack
// into a GPU slice atlas.

import 'dart:math' as math;
import 'dart:typed_data';

import 'dicom_parser.dart';

/// A scalar 3D volume: rescaled intensity per voxel plus physical spacing.
class DicomVolume {
  DicomVolume({
    required this.width,
    required this.height,
    required this.depth,
    required this.voxels,
    required this.minValue,
    required this.maxValue,
    required this.spacing,
    required this.patientRowDir,
    required this.patientColDir,
    required this.patientSliceDir,
    required this.defaultWindowCenter,
    required this.defaultWindowWidth,
  });

  /// Columns (X), rows (Y), and slice count (Z).
  final int width;
  final int height;
  final int depth;

  /// Rescaled intensity, row-major per slice, slices ordered front to back.
  /// Length is width * height * depth.
  final Float32List voxels;

  /// Intensity range across the whole volume (post-rescale), for normalizing.
  final double minValue;
  final double maxValue;

  /// Physical voxel size in mm: [x, y, z]. Used to set the display aspect.
  final List<double> spacing;

  /// DICOM patient-space (LPS: +x Left, +y Posterior, +z Superior) unit
  /// directions of the three volume axes: increasing column (x), increasing
  /// row (y), and increasing slice (z). Used to orient the volume anatomically.
  final List<double> patientRowDir;
  final List<double> patientColDir;
  final List<double> patientSliceDir;

  /// A sensible initial window (from the files, or derived from the range).
  final double defaultWindowCenter;
  final double defaultWindowWidth;

  int get voxelCount => width * height * depth;
}

/// Builds a [DicomVolume] from unordered [slices]. Slices are sorted along
/// their common normal by ImagePositionPatient (never by filename), stored
/// samples are rescaled, and MONOCHROME1 is inverted so larger always reads
/// brighter.
DicomVolume buildVolume(List<DicomSlice> slices) {
  if (slices.isEmpty) {
    throw DicomParseException('no slices to assemble');
  }

  final first = slices.first;
  final width = first.columns;
  final height = first.rows;
  if (width == 0 || height == 0) {
    throw DicomParseException('slice has zero extent');
  }
  for (final s in slices) {
    if (s.columns != width || s.rows != height) {
      throw DicomParseException('slices have inconsistent dimensions');
    }
    if (s.samplesPerPixel != 1) {
      throw DicomParseException(
        'only single-sample (monochrome) images '
        'are supported, got ${s.samplesPerPixel} samples/pixel',
      );
    }
  }

  // Slice ordering: project each slice origin onto the slice normal (the
  // cross product of the row and column direction cosines) and sort by that
  // scalar. Falls back to the position's Z, then to input order.
  final normal = _sliceNormal(first.imageOrientationPatient);
  double sortKey(DicomSlice s) {
    final p = s.imagePositionPatient;
    if (p == null || p.length < 3) return 0;
    if (normal != null) {
      return p[0] * normal[0] + p[1] * normal[1] + p[2] * normal[2];
    }
    return p[2];
  }

  final ordered = List<DicomSlice>.from(slices);
  final positioned = ordered.every(
    (s) =>
        s.imagePositionPatient != null && s.imagePositionPatient!.length >= 3,
  );
  if (positioned) {
    ordered.sort((a, b) => sortKey(a).compareTo(sortKey(b)));
  }

  final depth = ordered.length;
  final voxels = Float32List(width * height * depth);
  double minValue = double.infinity;
  double maxValue = double.negativeInfinity;

  for (var z = 0; z < depth; z++) {
    final slice = ordered[z];
    final samples = _decodeSamples(slice);
    final base = z * width * height;
    final slope = slice.rescaleSlope;
    final intercept = slice.rescaleIntercept;
    final invert = slice.invertMonochrome;
    // For MONOCHROME1 we flip within the stored range so brighter == larger.
    final maxStored = (1 << slice.bitsStored) - 1;
    for (var i = 0; i < samples.length; i++) {
      var stored = samples[i];
      if (invert) stored = maxStored - stored;
      final value = stored * slope + intercept;
      voxels[base + i] = value;
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
  }

  if (!minValue.isFinite || !maxValue.isFinite) {
    minValue = 0;
    maxValue = 1;
  }
  if (maxValue <= minValue) maxValue = minValue + 1;

  // Physical spacing. In-plane from PixelSpacing [rowSpacing, colSpacing];
  // between-slice from consecutive slice positions (more reliable than
  // SliceThickness, which ignores gaps), falling back to SliceThickness.
  final ps = first.pixelSpacing;
  final rowSpacing = (ps != null && ps.isNotEmpty) ? ps[0] : 1.0;
  final colSpacing = (ps != null && ps.length > 1) ? ps[1] : rowSpacing;
  final sliceSpacing = _sliceSpacing(ordered, sortKey, first.sliceThickness);

  // spacing is [x, y, z] = [column, row, slice] in mm.
  final spacing = <double>[colSpacing, rowSpacing, sliceSpacing];

  // Patient-space directions of the volume axes, for anatomical orientation.
  // ImageOrientationPatient gives the row (increasing column) and column
  // (increasing row) cosines; the slice axis is their cross product (the
  // normal), which points along increasing slice after the sort above.
  final orient = first.imageOrientationPatient;
  final rowDir = (orient != null && orient.length >= 6)
      ? _normalize(orient.sublist(0, 3))
      : <double>[1, 0, 0];
  final colDir = (orient != null && orient.length >= 6)
      ? _normalize(orient.sublist(3, 6))
      : <double>[0, 1, 0];
  final sliceDir = normal != null ? _normalize(normal) : <double>[0, 0, 1];

  // Default window: prefer the file's, else cover the middle of the range.
  final wc = first.windowCenter ?? (minValue + maxValue) * 0.5;
  final ww = first.windowWidth ?? (maxValue - minValue);

  return DicomVolume(
    width: width,
    height: height,
    depth: depth,
    voxels: voxels,
    minValue: minValue,
    maxValue: maxValue,
    spacing: spacing,
    patientRowDir: rowDir,
    patientColDir: colDir,
    patientSliceDir: sliceDir,
    defaultWindowCenter: wc,
    defaultWindowWidth: ww <= 0 ? (maxValue - minValue) : ww,
  );
}

/// Returns a unit-length copy of a 3-vector, or the input if degenerate.
List<double> _normalize(List<double> v) {
  final len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (len < 1e-9) return v;
  return [v[0] / len, v[1] / len, v[2] / len];
}

/// Decodes stored integer samples from a slice's raw PixelData, honoring
/// bits-allocated and signedness. Returns unsigned-shifted values for signed
/// data so the caller can rescale uniformly.
Int32List _decodeSamples(DicomSlice slice) {
  final count = slice.rows * slice.columns;
  final out = Int32List(count);
  final bytes = slice.pixelData;
  final signed = slice.pixelRepresentation == 1;

  if (slice.bitsAllocated <= 8) {
    // Use a ByteData view so the slice's own byte offset is respected.
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < count && i < bytes.length; i++) {
      out[i] = signed ? view.getInt8(i) : bytes[i];
    }
    return out;
  }

  // 16-bit little-endian (the common MRI/CT case).
  final view = ByteData.sublistView(bytes);
  final maxSafe = (bytes.length ~/ 2);
  for (var i = 0; i < count && i < maxSafe; i++) {
    out[i] = signed
        ? view.getInt16(i * 2, Endian.little)
        : view.getUint16(i * 2, Endian.little);
  }
  return out;
}

/// Cross product of the row and column direction cosines, or null.
List<double>? _sliceNormal(List<double>? orientation) {
  if (orientation == null || orientation.length < 6) return null;
  final r = orientation.sublist(0, 3);
  final c = orientation.sublist(3, 6);
  return [
    r[1] * c[2] - r[2] * c[1],
    r[2] * c[0] - r[0] * c[2],
    r[0] * c[1] - r[1] * c[0],
  ];
}

/// Median gap between consecutive ordered slices, falling back to thickness.
double _sliceSpacing(
  List<DicomSlice> ordered,
  double Function(DicomSlice) sortKey,
  double? thickness,
) {
  if (ordered.length >= 2) {
    final gaps = <double>[];
    for (var i = 1; i < ordered.length; i++) {
      final g = (sortKey(ordered[i]) - sortKey(ordered[i - 1])).abs();
      if (g > 1e-6) gaps.add(g);
    }
    if (gaps.isNotEmpty) {
      gaps.sort();
      return gaps[gaps.length ~/ 2];
    }
  }
  if (thickness != null && thickness > 0) return thickness;
  return 1.0;
}
