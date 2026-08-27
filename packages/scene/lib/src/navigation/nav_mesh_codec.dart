import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_mesh.dart';

/// The on-disk magic and version of a baked nav mesh.
///
/// Versioned because the polygon layout is the contract between a baker and a
/// runtime that may be a release apart. A mismatch throws rather than reading
/// nonsense as geometry.
const int navMeshMagic = 0x4e564d31; // 'NVM1'
const int navMeshVersion = 1;

/// Serializes [mesh] to a compact binary form.
///
/// The layout is a small header, the config as JSON, and then the arrays
/// verbatim: a baked mesh is mostly numbers, and turning them into text would
/// multiply the size for no gain. The config rides along because a path is
/// only valid for the agent the mesh was baked for.
Uint8List encodeNavMesh(NavMesh mesh) {
  final configBytes = utf8.encode(jsonEncode(mesh.config.toJson()));

  final headerBytes = 8 * 4;
  final total =
      headerBytes +
      configBytes.length +
      mesh.vertices.lengthInBytes +
      mesh.polygonVertices.lengthInBytes +
      mesh.polygonStart.lengthInBytes +
      mesh.neighbours.lengthInBytes +
      mesh.areas.lengthInBytes +
      mesh.regions.lengthInBytes;

  final bytes = Uint8List(total);
  final view = ByteData.view(bytes.buffer);
  var offset = 0;
  void writeInt(int value) {
    view.setUint32(offset, value, Endian.little);
    offset += 4;
  }

  writeInt(navMeshMagic);
  writeInt(navMeshVersion);
  writeInt(configBytes.length);
  writeInt(mesh.vertices.length ~/ 3);
  writeInt(mesh.polygonCount);
  writeInt(mesh.polygonVertices.length);
  writeInt(0); // Reserved, so a later field costs no version bump.
  writeInt(0);

  void writeBytes(Uint8List source) {
    bytes.setRange(offset, offset + source.length, source);
    offset += source.length;
  }

  writeBytes(Uint8List.fromList(configBytes));
  writeBytes(
    mesh.vertices.buffer.asUint8List(
      mesh.vertices.offsetInBytes,
      mesh.vertices.lengthInBytes,
    ),
  );
  writeBytes(
    mesh.polygonVertices.buffer.asUint8List(
      mesh.polygonVertices.offsetInBytes,
      mesh.polygonVertices.lengthInBytes,
    ),
  );
  writeBytes(
    mesh.polygonStart.buffer.asUint8List(
      mesh.polygonStart.offsetInBytes,
      mesh.polygonStart.lengthInBytes,
    ),
  );
  writeBytes(
    mesh.neighbours.buffer.asUint8List(
      mesh.neighbours.offsetInBytes,
      mesh.neighbours.lengthInBytes,
    ),
  );
  writeBytes(mesh.areas);
  writeBytes(
    mesh.regions.buffer.asUint8List(
      mesh.regions.offsetInBytes,
      mesh.regions.lengthInBytes,
    ),
  );
  return bytes;
}

/// Rebuilds a [NavMesh] from [encodeNavMesh] output.
///
/// Throws [FormatException] on a wrong magic, an unsupported version, or a
/// truncated buffer.
NavMesh decodeNavMesh(Uint8List bytes) {
  if (bytes.length < 32) {
    throw const FormatException('Nav mesh data is too short to hold a header');
  }
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  var offset = 0;
  int readInt() {
    final value = view.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  final magic = readInt();
  if (magic != navMeshMagic) {
    throw const FormatException('Not a baked nav mesh (bad magic)');
  }
  final version = readInt();
  if (version != navMeshVersion) {
    throw FormatException(
      'Nav mesh version $version, expected $navMeshVersion. Re-bake it.',
    );
  }
  final configLength = readInt();
  final vertexCount = readInt();
  final polygonCount = readInt();
  final cornerCount = readInt();
  readInt();
  readInt();

  // Every array is copied rather than viewed, because a view would inherit the
  // source buffer's alignment, and a header of 32 bytes plus a JSON blob of
  // arbitrary length does not leave Float32List aligned.
  Uint8List take(int length) {
    if (offset + length > bytes.length) {
      throw const FormatException('Nav mesh data is truncated');
    }
    final slice = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return slice;
  }

  final config = NavMeshConfig.fromJson(
    jsonDecode(utf8.decode(take(configLength))) as Map<String, Object?>,
  );
  final vertices = take(vertexCount * 3 * 4).buffer.asFloat32List();
  final polygonVertices = take(cornerCount * 2).buffer.asUint16List();
  final polygonStart = take((polygonCount + 1) * 4).buffer.asUint32List();
  final neighbours = take(cornerCount * 4).buffer.asInt32List();
  final areas = take(polygonCount);
  final regions = take(polygonCount * 2).buffer.asUint16List();

  return NavMesh(
    vertices: vertices,
    polygonVertices: polygonVertices,
    polygonStart: polygonStart,
    polygonCount: polygonCount,
    neighbours: neighbours,
    areas: areas,
    regions: regions,
    config: config,
  );
}
