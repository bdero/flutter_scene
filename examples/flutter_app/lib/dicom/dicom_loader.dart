// Downloads, caches, parses, and packs the reference head MRI for the DICOM
// Volume example.
//
// Reference dataset (primary): datalad `example-dicom-structural`, a de-faced
// T1-weighted head MRI (100 slices) from the studyforrest project, released
// into the public domain under the PDDL (Open Data Commons Public Domain
// Dedication). https://github.com/datalad/example-dicom-structural
//
// Fallback: Zenodo record 16956, a head MRI (T1/T2) under CC-BY-SA 4.0.
// https://zenodo.org/records/16956
//
// The tarball is fetched once and cached under the app support directory;
// parsing and atlas packing run on a background isolate so the UI thread and
// the raster thread stay free. The finished float atlas is handed back for
// GPU upload on the raster thread.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'dicom_parser.dart';
import 'dicom_volume.dart';

/// A scalar volume packed into a 2D slice-atlas, ready for GPU upload as an
/// r32Float texture.
class VolumeAtlas {
  VolumeAtlas({
    required this.data,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.cols,
    required this.rows,
    required this.volumeWidth,
    required this.volumeHeight,
    required this.volumeDepth,
    required this.spacing,
    required this.patientRowDir,
    required this.patientColDir,
    required this.patientSliceDir,
    required this.windowCenter,
    required this.windowWidth,
  });

  /// Normalized intensities in [0,1], atlas-tiled, one float per texel.
  final Float32List data;
  final int atlasWidth;
  final int atlasHeight;

  /// Tile grid dimensions.
  final int cols;
  final int rows;

  /// Volume voxel dimensions.
  final int volumeWidth;
  final int volumeHeight;
  final int volumeDepth;

  /// Physical voxel size [x, y, z] in mm (for display aspect).
  final List<double> spacing;

  /// DICOM patient-space (LPS) unit directions of the column, row, and slice
  /// axes, for orienting the volume anatomically.
  final List<double> patientRowDir;
  final List<double> patientColDir;
  final List<double> patientSliceDir;

  /// Default window in normalized [0,1] intensity units.
  final double windowCenter;
  final double windowWidth;
}

/// Progress callback phases for the loader.
typedef DicomStatusCallback = void Function(String message);

const String _primaryUrl =
    'https://codeload.github.com/datalad/example-dicom-structural/tar.gz/refs/heads/master';
const String _fallbackUrl =
    'https://zenodo.org/records/16956/files/DICOM.zip?download=1';
const String _cacheFileName = 'dicom_example_structural.tar.gz';

// Keep atlas dimensions within a conservative cross-backend texture limit.
const int _maxAtlasDimension = 8192;

/// Loads the reference volume, using the on-disk cache when present.
Future<VolumeAtlas> loadReferenceVolume({DicomStatusCallback? onStatus}) async {
  onStatus?.call('Locating cached dataset...');
  final cached = await _cachedTarball();
  Uint8List bytes;
  bool isZip = false;
  if (cached != null) {
    onStatus?.call('Loading cached dataset...');
    bytes = cached;
  } else {
    try {
      onStatus?.call('Downloading head MRI (public domain)...');
      bytes = await _download(_primaryUrl);
      await _writeCache(bytes);
    } catch (e) {
      onStatus?.call('Primary source failed, trying fallback...');
      bytes = await _download(_fallbackUrl);
      isZip = true;
      // The fallback is a zip; don't cache it under the .tar.gz name.
    }
  }

  onStatus?.call('Decoding slices...');
  return compute(_decodeRequest, _DecodeRequest(bytes, isZip));
}

Future<Uint8List> _download(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('download failed (${response.statusCode}) for $url');
  }
  return response.bodyBytes;
}

Future<File> _cacheFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/$_cacheFileName');
}

Future<Uint8List?> _cachedTarball() async {
  try {
    final file = await _cacheFile();
    if (await file.exists() && await file.length() > 0) {
      return await file.readAsBytes();
    }
  } catch (_) {
    // Cache is best-effort; fall through to a network fetch.
  }
  return null;
}

Future<void> _writeCache(Uint8List bytes) async {
  try {
    final file = await _cacheFile();
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // Non-fatal: a failed cache write just means we re-download next time.
  }
}

/// Isolate payload: the raw archive bytes plus whether it is a zip.
class _DecodeRequest {
  _DecodeRequest(this.bytes, this.isZip);
  final Uint8List bytes;
  final bool isZip;
}

/// Isolate entry point for [compute].
VolumeAtlas _decodeRequest(_DecodeRequest req) =>
    _decodeAndPack(req.bytes, req.isZip);

/// Extracts DICOM files from the archive, parses them, assembles the volume,
/// and packs it into a normalized slice atlas. Runs on a background isolate.
VolumeAtlas _decodeAndPack(Uint8List archiveBytes, bool isZip) {
  final Archive archive;
  if (isZip) {
    archive = ZipDecoder().decodeBytes(archiveBytes);
  } else {
    final tar = GZipDecoder().decodeBytes(archiveBytes);
    archive = TarDecoder().decodeBytes(tar);
  }

  final slices = <DicomSlice>[];
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.toLowerCase();
    // Skip obvious non-image entries; try to parse everything else and
    // silently drop what isn't a readable DICOM image.
    if (name.endsWith('.md') ||
        name.endsWith('.txt') ||
        name.endsWith('.json') ||
        name.endsWith('/dicomdir') ||
        name.endsWith('.gitattributes')) {
      continue;
    }
    try {
      final slice = parseDicom(entry.content);
      if (slice.rows > 0 && slice.columns > 0 && slice.pixelData.isNotEmpty) {
        slices.add(slice);
      }
    } catch (_) {
      // Not a DICOM image we can read; skip it.
    }
  }

  if (slices.isEmpty) {
    throw DicomParseException('archive contained no readable DICOM slices');
  }

  final volume = buildVolume(slices);
  return _packAtlas(volume);
}

/// Packs a [DicomVolume] into a normalized [0,1] slice atlas.
VolumeAtlas _packAtlas(DicomVolume volume) {
  final w = volume.width;
  final h = volume.height;
  final d = volume.depth;

  // Near-square tile grid.
  final cols = _ceilSqrt(d);
  final rows = (d + cols - 1) ~/ cols;
  final atlasWidth = cols * w;
  final atlasHeight = rows * h;

  if (atlasWidth > _maxAtlasDimension || atlasHeight > _maxAtlasDimension) {
    // TODO(dicom): split across multiple atlas textures (or downsample) for
    // volumes too large for a single texture; today only single-atlas volumes
    // that fit within the conservative limit are supported.
    throw DicomParseException(
      'volume ${w}x${h}x$d needs a ${atlasWidth}x$atlasHeight atlas, '
      'exceeding the ${_maxAtlasDimension}px limit',
    );
  }

  final range = volume.maxValue - volume.minValue;
  final invRange = range > 0 ? 1.0 / range : 0.0;
  final atlas = Float32List(atlasWidth * atlasHeight);

  for (var z = 0; z < d; z++) {
    final col = z % cols;
    final row = z ~/ cols;
    final tileX = col * w;
    final tileY = row * h;
    final srcBase = z * w * h;
    for (var y = 0; y < h; y++) {
      final dstBase = (tileY + y) * atlasWidth + tileX;
      final srcRow = srcBase + y * w;
      for (var x = 0; x < w; x++) {
        atlas[dstBase + x] =
            (volume.voxels[srcRow + x] - volume.minValue) * invRange;
      }
    }
  }

  final wcNorm = ((volume.defaultWindowCenter - volume.minValue) * invRange)
      .clamp(0.0, 1.0);
  final wwNorm = (volume.defaultWindowWidth * invRange)
      .clamp(0.001, 1.0)
      .toDouble();

  return VolumeAtlas(
    data: atlas,
    atlasWidth: atlasWidth,
    atlasHeight: atlasHeight,
    cols: cols,
    rows: rows,
    volumeWidth: w,
    volumeHeight: h,
    volumeDepth: d,
    spacing: volume.spacing,
    patientRowDir: volume.patientRowDir,
    patientColDir: volume.patientColDir,
    patientSliceDir: volume.patientSliceDir,
    windowCenter: wcNorm.toDouble(),
    windowWidth: wwNorm,
  );
}

int _ceilSqrt(int n) {
  var c = 1;
  while (c * c < n) {
    c++;
  }
  return c;
}
