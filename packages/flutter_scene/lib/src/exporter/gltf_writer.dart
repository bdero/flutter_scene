/// Writing a node tree back out as glTF 2.0.
///
/// The engine has read glTF thoroughly for a long time and had no way to
/// return the favour, which makes a scene built here a scene that can only be
/// opened here. This is the way out: geometry, the node hierarchy that
/// arranges it, and the material factors that shade it, in the format every
/// other tool already opens.
///
/// What it does not write yet, stated so the gap is visible rather than
/// discovered: textures (the pixels live on the GPU and reading them back
/// needs a frame), skins, morph targets and animation. Materials come out as
/// factors, so a model round-trips with its colours but not its maps.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../geometry/mesh_data.dart';
import '../gpu/gpu.dart' as gpu;
import '../material/material.dart';
import '../material/physically_based_material.dart';
import '../material/unlit_material.dart';
import '../mesh.dart';
import '../node.dart';

/// Writes [root] and its descendants as a binary glTF 2.0 asset.
///
/// Geometry that does not retain CPU-side vertex data (a caller-managed vertex
/// buffer) cannot be written and is reported through [onWarning] rather than
/// dropped quietly -- a mesh missing from an export is worse the later you
/// find out.
///
/// {@category Importer}
Uint8List writeGlb(
  Node root, {
  String generator = 'flutter_scene',
  void Function(String warning)? onWarning,
}) {
  final writer = _GltfWriter(generator: generator, onWarning: onWarning);
  writer.addScene(root);
  return writer.finish();
}

/// glTF's component types, by the spec's own numbers.
const int _componentFloat = 5126;
const int _componentUnsignedShort = 5123;
const int _componentUnsignedInt = 5125;

/// glTF's buffer view targets.
const int _targetArrayBuffer = 34962;
const int _targetElementArrayBuffer = 34963;

class _GltfWriter {
  _GltfWriter({required this.generator, this.onWarning});

  final String generator;
  final void Function(String warning)? onWarning;

  final List<Map<String, Object?>> _nodes = [];
  final List<Map<String, Object?>> _meshes = [];
  final List<Map<String, Object?>> _materials = [];
  final List<Map<String, Object?>> _accessors = [];
  final List<Map<String, Object?>> _bufferViews = [];
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _bufferLength = 0;

  /// Written meshes and materials by identity, so a model that shares one
  /// material across forty primitives writes it once.
  final Map<Mesh, int> _meshIndices = {};
  final Map<Material, int> _materialIndices = {};

  final List<int> _roots = [];

  bool _usesUnlit = false;

  void addScene(Node root) => _roots.add(_addNode(root));

  int _addNode(Node node) {
    final json = <String, Object?>{};
    if (node.name.isNotEmpty) json['name'] = node.name;

    final matrix = node.localTransform;
    if (!_isIdentity(matrix)) {
      json['matrix'] = [for (final value in matrix.storage) value];
    }

    final mesh = node.mesh;
    if (mesh != null) {
      final index = _addMesh(mesh, node.name);
      if (index != null) json['mesh'] = index;
    }

    // The node's own entry is reserved before its children are written, so
    // the indices children refer back to are stable.
    final index = _nodes.length;
    _nodes.add(json);

    final children = [for (final child in node.children) _addNode(child)];
    if (children.isNotEmpty) json['children'] = children;
    return index;
  }

  int? _addMesh(Mesh mesh, String nodeName) {
    final existing = _meshIndices[mesh];
    if (existing != null) return existing;

    final primitives = <Map<String, Object?>>[];
    for (final primitive in mesh.primitives) {
      final written = _addPrimitive(primitive, nodeName);
      if (written != null) primitives.add(written);
    }
    if (primitives.isEmpty) return null;

    final index = _meshes.length;
    _meshes.add({
      if (nodeName.isNotEmpty) 'name': nodeName,
      'primitives': primitives,
    });
    _meshIndices[mesh] = index;
    return index;
  }

  Map<String, Object?>? _addPrimitive(MeshPrimitive primitive, String owner) {
    final geometry = primitive.geometry;
    if (!geometry.isReadable) {
      _warn(
        'Skipped a primitive of "${owner.isEmpty ? 'an unnamed node' : owner}": '
        'its geometry keeps no CPU-side vertex data, so there is nothing to '
        'write. Geometry built through GeometryBuilder or loaded by an '
        'importer is readable; a caller-managed vertex buffer is not.',
      );
      return null;
    }
    final MeshData data;
    try {
      data = geometry.extractMeshData();
    } on StateError catch (error) {
      _warn('Skipped a primitive of "$owner": ${error.message}');
      return null;
    }

    final attributes = <String, int>{
      'POSITION': _addVectorAccessor(data.positions, 3, bounds: true),
    };
    if (data.normals case final normals?) {
      attributes['NORMAL'] = _addVectorAccessor(normals, 3);
    }
    if (data.texCoords case final uv?) {
      attributes['TEXCOORD_0'] = _addVectorAccessor(uv, 2);
    }
    if (data.texCoords1 case final uv1?) {
      attributes['TEXCOORD_1'] = _addVectorAccessor(uv1, 2);
    }
    if (data.colors case final colors?) {
      attributes['COLOR_0'] = _addVectorAccessor(colors, 4);
    }
    if (data.tangents case final tangents?) {
      attributes['TANGENT'] = _addVectorAccessor(tangents, 4);
    }

    return {
      'attributes': attributes,
      if (data.indices case final indices?)
        if (indices.isNotEmpty) 'indices': _addIndexAccessor(indices),
      'material': _addMaterial(primitive.material),
      if (_mode(data.primitiveType) case final mode when mode != 4)
        'mode': mode,
    };
  }

  /// glTF's primitive modes, by the spec's own numbers.
  int _mode(gpu.PrimitiveType type) => switch (type) {
    gpu.PrimitiveType.point => 0,
    gpu.PrimitiveType.line => 1,
    gpu.PrimitiveType.lineStrip => 3,
    gpu.PrimitiveType.triangle => 4,
    gpu.PrimitiveType.triangleStrip => 5,
  };

  int _addMaterial(Material material) {
    final existing = _materialIndices[material];
    if (existing != null) return existing;

    final json = <String, Object?>{};
    switch (material) {
      case PhysicallyBasedMaterial pbr:
        json['pbrMetallicRoughness'] = {
          'baseColorFactor': _rgba(pbr.baseColorFactor),
          'metallicFactor': pbr.metallicFactor,
          'roughnessFactor': pbr.roughnessFactor,
        };
        final emissive = pbr.emissiveFactor;
        if (emissive.r != 0 || emissive.g != 0 || emissive.b != 0) {
          json['emissiveFactor'] = [emissive.r, emissive.g, emissive.b];
        }
      case UnlitMaterial unlit:
        // The unlit extension is what tells the reader not to light it; without
        // it an unlit material arrives as a lit one that happens to be flat.
        _usesUnlit = true;
        json['pbrMetallicRoughness'] = {
          'baseColorFactor': _rgba(unlit.baseColorFactor),
          'metallicFactor': 0.0,
          'roughnessFactor': 1.0,
        };
        json['extensions'] = {'KHR_materials_unlit': <String, Object?>{}};
      default:
        // A custom material's parameters are its own; what survives the trip
        // is that the primitive had one.
        _warn(
          'A ${material.runtimeType} was written as a default material: only '
          'the built-in materials have factors glTF can carry.',
        );
        json['pbrMetallicRoughness'] = {
          'baseColorFactor': [1.0, 1.0, 1.0, 1.0],
          'metallicFactor': 0.0,
          'roughnessFactor': 1.0,
        };
    }

    final index = _materials.length;
    _materials.add(json);
    _materialIndices[material] = index;
    return index;
  }

  static List<double> _rgba(Vector4 c) => [c.r, c.g, c.b, c.a];

  int _addVectorAccessor(
    Float32List values,
    int components, {
    bool bounds = false,
  }) {
    final count = values.length ~/ components;
    final view = _addBufferView(
      Uint8List.sublistView(values),
      target: _targetArrayBuffer,
    );
    final accessor = <String, Object?>{
      'bufferView': view,
      'componentType': _componentFloat,
      'count': count,
      'type': switch (components) {
        2 => 'VEC2',
        3 => 'VEC3',
        _ => 'VEC4',
      },
    };
    // POSITION must carry bounds; the spec requires them, and a reader that
    // frames a model on load has nothing to frame without them.
    if (bounds && count > 0) {
      final min = List<double>.filled(components, double.infinity);
      final max = List<double>.filled(components, -double.infinity);
      for (var i = 0; i < count; i++) {
        for (var c = 0; c < components; c++) {
          final value = values[i * components + c];
          if (value < min[c]) min[c] = value;
          if (value > max[c]) max[c] = value;
        }
      }
      accessor['min'] = min;
      accessor['max'] = max;
    }
    _accessors.add(accessor);
    return _accessors.length - 1;
  }

  int _addIndexAccessor(List<int> indices) {
    final wide = indices is Uint32List || indices.any((i) => i > 0xFFFF);
    final bytes = wide
        ? Uint8List.sublistView(Uint32List.fromList(indices))
        : Uint8List.sublistView(Uint16List.fromList(indices));
    final view = _addBufferView(bytes, target: _targetElementArrayBuffer);
    _accessors.add({
      'bufferView': view,
      'componentType': wide ? _componentUnsignedInt : _componentUnsignedShort,
      'count': indices.length,
      'type': 'SCALAR',
    });
    return _accessors.length - 1;
  }

  int _addBufferView(Uint8List bytes, {required int target}) {
    _padBufferTo(4);
    final offset = _bufferLength;
    _buffer.add(bytes);
    _bufferLength += bytes.lengthInBytes;
    _bufferViews.add({
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': bytes.lengthInBytes,
      'target': target,
    });
    return _bufferViews.length - 1;
  }

  void _padBufferTo(int alignment) {
    final remainder = _bufferLength % alignment;
    if (remainder == 0) return;
    final padding = alignment - remainder;
    _buffer.add(Uint8List(padding));
    _bufferLength += padding;
  }

  void _warn(String message) => onWarning?.call(message);

  static bool _isIdentity(Matrix4 m) {
    final identity = Matrix4.identity().storage;
    for (var i = 0; i < 16; i++) {
      if ((m.storage[i] - identity[i]).abs() > 1e-9) return false;
    }
    return true;
  }

  Uint8List finish() {
    _padBufferTo(4);
    final bin = _buffer.takeBytes();

    final json = <String, Object?>{
      'asset': {'version': '2.0', 'generator': generator},
      'scene': 0,
      'scenes': [
        {'nodes': _roots},
      ],
      if (_nodes.isNotEmpty) 'nodes': _nodes,
      if (_meshes.isNotEmpty) 'meshes': _meshes,
      if (_materials.isNotEmpty) 'materials': _materials,
      if (_accessors.isNotEmpty) 'accessors': _accessors,
      if (_bufferViews.isNotEmpty) 'bufferViews': _bufferViews,
      if (bin.isNotEmpty)
        'buffers': [
          {'byteLength': bin.length},
        ],
      if (_usesUnlit) 'extensionsUsed': ['KHR_materials_unlit'],
    };

    final jsonBytes = utf8.encode(jsonEncode(json));
    // Chunks are four-byte aligned: JSON pads with spaces, BIN with zeroes,
    // which is the spec's wording and not a detail readers are lenient about.
    final jsonPadding = (4 - jsonBytes.length % 4) % 4;
    final binPadding = (4 - bin.length % 4) % 4;

    final total =
        12 +
        8 +
        jsonBytes.length +
        jsonPadding +
        (bin.isEmpty ? 0 : 8 + bin.length + binPadding);

    final out = BytesBuilder(copy: false);
    final header = ByteData(12)
      ..setUint32(0, 0x46546C67, Endian.little) // "glTF"
      ..setUint32(4, 2, Endian.little)
      ..setUint32(8, total, Endian.little);
    out.add(header.buffer.asUint8List());

    final jsonHeader = ByteData(8)
      ..setUint32(0, jsonBytes.length + jsonPadding, Endian.little)
      ..setUint32(4, 0x4E4F534A, Endian.little); // "JSON"
    out
      ..add(jsonHeader.buffer.asUint8List())
      ..add(jsonBytes)
      ..add(Uint8List.fromList(List.filled(jsonPadding, 0x20)));

    if (bin.isNotEmpty) {
      final binHeader = ByteData(8)
        ..setUint32(0, bin.length + binPadding, Endian.little)
        ..setUint32(4, 0x004E4942, Endian.little); // "BIN\0"
      out
        ..add(binHeader.buffer.asUint8List())
        ..add(bin)
        ..add(Uint8List(binPadding));
    }

    return out.takeBytes();
  }
}
