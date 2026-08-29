/// Serializing a whole tiled world.
///
/// A single mesh has [encodeNavMesh]; a tile set is that plus the grid it
/// sits on. The links between tiles are deliberately *not* stored: they are
/// derived from the tiles' own boundary polygons, recomputing them costs a
/// scan of the edges, and a stored copy is one more thing that can disagree
/// with the geometry it describes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_mesh_codec.dart';
import 'package:scene/src/navigation/nav_tiles.dart';

/// The on-disk magic and version of a baked tile set.
const int navTileSetMagic = 0x4e565431; // 'NVT1'
const int navTileSetVersion = 1;

/// Serializes [tiles] to a compact binary form.
///
/// Tiles are written in a stable order (by z, then x) so the same set encodes
/// to the same bytes twice, which is what makes a saved scene diff cleanly
/// when the bake did not change.
/// {@category Navigation}
Uint8List encodeNavTileSet(NavTileSet tiles) {
  final header = utf8.encode(
    jsonEncode({
      'config': tiles.config.toJson(),
      'tileCells': tiles.tiling.tileCells,
      if (tiles.tiling.borderCells != null)
        'borderCells': tiles.tiling.borderCells,
      'origin': [tiles.origin.x, tiles.origin.y, tiles.origin.z],
    }),
  );

  final keys = tiles.tiles.toList()
    ..sort((a, b) => a.z == b.z ? a.x.compareTo(b.x) : a.z.compareTo(b.z));
  final chunks = [for (final key in keys) encodeNavMesh(tiles.tile(key)!)];

  var total = 4 * 4 + header.length;
  for (final chunk in chunks) {
    total += 3 * 4 + chunk.length;
  }

  final bytes = Uint8List(total);
  final view = ByteData.view(bytes.buffer);
  var offset = 0;
  void writeInt(int value) {
    view.setInt32(offset, value, Endian.little);
    offset += 4;
  }

  void writeBytes(List<int> source) {
    bytes.setRange(offset, offset + source.length, source);
    offset += source.length;
  }

  writeInt(navTileSetMagic);
  writeInt(navTileSetVersion);
  writeInt(header.length);
  writeInt(keys.length);
  writeBytes(header);
  for (var i = 0; i < keys.length; i++) {
    writeInt(keys[i].x);
    writeInt(keys[i].z);
    writeInt(chunks[i].length);
    writeBytes(chunks[i]);
  }
  return bytes;
}

/// Rebuilds a [NavTileSet] from [encodeNavTileSet] output, relinking the
/// tiles as they are installed.
///
/// Throws [FormatException] on a wrong magic, an unsupported version, or a
/// truncated buffer.
/// {@category Navigation}
NavTileSet decodeNavTileSet(Uint8List bytes) {
  if (bytes.length < 16) {
    throw const FormatException('Nav tile data is too short to hold a header');
  }
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  var offset = 0;
  int readInt() {
    final value = view.getInt32(offset, Endian.little);
    offset += 4;
    return value;
  }

  if (readInt() != navTileSetMagic) {
    throw const FormatException('Not a baked nav tile set (bad magic)');
  }
  final version = readInt();
  if (version != navTileSetVersion) {
    throw FormatException(
      'Nav tile set version $version, expected $navTileSetVersion. Re-bake it.',
    );
  }
  final headerLength = readInt();
  final tileCount = readInt();

  Uint8List take(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Nav tile data is truncated');
    }
    final slice = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return slice;
  }

  final header =
      jsonDecode(utf8.decode(take(headerLength))) as Map<String, Object?>;
  final config = NavMeshConfig.fromJson(
    header['config']! as Map<String, Object?>,
  );
  final origin = (header['origin'] as List?)?.cast<num>();
  final set = NavTileSet(
    config: config,
    tiling: NavTileConfig(
      tileCells: (header['tileCells'] as num?)?.toInt() ?? 128,
      borderCells: (header['borderCells'] as num?)?.toInt(),
    ),
    origin: origin == null
        ? null
        : Vector3(
            origin[0].toDouble(),
            origin[1].toDouble(),
            origin[2].toDouble(),
          ),
  );

  for (var i = 0; i < tileCount; i++) {
    final x = readInt();
    final z = readInt();
    final length = readInt();
    set.setTile((x: x, z: z), decodeNavMesh(take(length)));
  }
  return set;
}
