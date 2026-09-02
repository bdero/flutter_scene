/// Writing a node tree back out as glTF.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry with data and no GPU behind it, which is all the writer reads.
class _StubGeometry extends Geometry {
  _StubGeometry(this.data, {this.readable = true});

  final MeshData data;
  final bool readable;

  @override
  bool get isReadable => readable;

  @override
  MeshData extractMeshData() {
    if (!readable) throw StateError('not readable');
    return data;
  }

  // Drawing is the one thing the writer never asks for.
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) => throw UnimplementedError();
}

MeshData _quad() => MeshData(
  positions: Float32List.fromList([
    -1, 0, -1, //
    1, 0, -1,
    1, 0, 1,
    -1, 0, 1,
  ]),
  vertexCount: 4,
  normals: Float32List.fromList([
    0, 1, 0, //
    0, 1, 0,
    0, 1, 0,
    0, 1, 0,
  ]),
  texCoords: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
  indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
);

/// Splits a GLB into its header numbers and its two chunks.
({int version, int length, Map<String, Object?> json, Uint8List bin}) _readGlb(
  Uint8List bytes,
) {
  final view = ByteData.sublistView(bytes);
  expect(view.getUint32(0, Endian.little), 0x46546C67, reason: 'magic');
  final version = view.getUint32(4, Endian.little);
  final length = view.getUint32(8, Endian.little);

  final jsonLength = view.getUint32(12, Endian.little);
  expect(view.getUint32(16, Endian.little), 0x4E4F534A, reason: 'JSON chunk');
  final json =
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)))
          as Map<String, Object?>;

  var bin = Uint8List(0);
  final binStart = 20 + jsonLength;
  if (binStart < bytes.length) {
    final binLength = view.getUint32(binStart, Endian.little);
    expect(
      view.getUint32(binStart + 4, Endian.little),
      0x004E4942,
      reason: 'BIN chunk',
    );
    bin = bytes.sublist(binStart + 8, binStart + 8 + binLength);
  }
  return (version: version, length: length, json: json, bin: bin);
}

void main() {
  test('a node tree writes as a valid glb container', () {
    final root = Node(name: 'Root')
      ..add(
        Node(
          name: 'Quad',
          localTransform: Matrix4.translation(Vector3(0, 2, 0)),
          mesh: Mesh(_StubGeometry(_quad()), PhysicallyBasedMaterial()),
        ),
      );

    final bytes = writeGlb(root);
    final glb = _readGlb(bytes);

    expect(glb.version, 2);
    expect(glb.length, bytes.length, reason: 'the header states the real size');
    expect(bytes.length % 4, 0, reason: 'chunks are four-byte aligned');
    expect((glb.json['asset']! as Map)['version'], '2.0');
  });

  test('the hierarchy, the transform and the attributes survive', () {
    final root = Node(name: 'Root')
      ..add(
        Node(
          name: 'Quad',
          localTransform: Matrix4.translation(Vector3(0, 2, 0)),
          mesh: Mesh(_StubGeometry(_quad()), PhysicallyBasedMaterial()),
        ),
      );

    final glb = _readGlb(writeGlb(root));
    final nodes = (glb.json['nodes']! as List).cast<Map<String, Object?>>();
    final scenes = (glb.json['scenes']! as List).cast<Map<String, Object?>>();

    expect(scenes.single['nodes'], [0]);
    expect(nodes[0]['name'], 'Root');
    expect(nodes[0]['matrix'], isNull, reason: 'identity is left out');
    expect(nodes[0]['children'], [1]);

    final child = nodes[1];
    expect(child['name'], 'Quad');
    // Column-major, so the translation is the last column.
    expect((child['matrix']! as List)[13], 2.0);

    final mesh = (glb.json['meshes']! as List).first as Map<String, Object?>;
    final primitive =
        (mesh['primitives']! as List).single as Map<String, Object?>;
    final attributes = primitive['attributes']! as Map<String, Object?>;
    expect(attributes.keys, containsAll(['POSITION', 'NORMAL', 'TEXCOORD_0']));
    expect(primitive['mode'], isNull, reason: 'triangles are the default mode');

    final accessors = (glb.json['accessors']! as List)
        .cast<Map<String, Object?>>();
    final position = accessors[attributes['POSITION']! as int];
    expect(position['count'], 4);
    expect(position['type'], 'VEC3');
    // The spec requires bounds on POSITION, and a viewer needs them to frame
    // what it just opened.
    expect(position['min'], [-1.0, 0.0, -1.0]);
    expect(position['max'], [1.0, 0.0, 1.0]);

    final indices = accessors[primitive['indices']! as int];
    expect(indices['count'], 6);
    expect(indices['componentType'], 5123, reason: 'short indices stay short');
  });

  test('the vertex data lands where the accessors say it does', () {
    final root = Node(
      name: 'Quad',
      mesh: Mesh(_StubGeometry(_quad()), PhysicallyBasedMaterial()),
    );

    final glb = _readGlb(writeGlb(root));
    final accessors = (glb.json['accessors']! as List)
        .cast<Map<String, Object?>>();
    final views = (glb.json['bufferViews']! as List)
        .cast<Map<String, Object?>>();
    final view = views[accessors.first['bufferView']! as int];
    final offset = view['byteOffset']! as int;
    final length = view['byteLength']! as int;

    expect(offset % 4, 0, reason: 'accessor data is aligned');
    final positions = Float32List.sublistView(
      Uint8List.sublistView(glb.bin, offset, offset + length),
    );
    expect(positions.take(3), [-1.0, 0.0, -1.0]);
    expect(positions.length, 12);
  });

  test('one material shared by two meshes is written once', () {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(1, 0, 0, 1)
      ..metallicFactor = 0.25;
    final root = Node(name: 'Root')
      ..add(Node(name: 'A', mesh: Mesh(_StubGeometry(_quad()), material)))
      ..add(Node(name: 'B', mesh: Mesh(_StubGeometry(_quad()), material)));

    final glb = _readGlb(writeGlb(root));
    final materials = (glb.json['materials']! as List)
        .cast<Map<String, Object?>>();

    expect(materials, hasLength(1));
    final pbr = materials.single['pbrMetallicRoughness']! as Map;
    expect(pbr['baseColorFactor'], [1.0, 0.0, 0.0, 1.0]);
    expect(pbr['metallicFactor'], 0.25);
  });

  test('geometry with nothing to write says so rather than vanishing', () {
    final warnings = <String>[];
    final root = Node(
      name: 'Opaque',
      mesh: Mesh(
        _StubGeometry(_quad(), readable: false),
        PhysicallyBasedMaterial(),
      ),
    );

    final glb = _readGlb(writeGlb(root, onWarning: warnings.add));

    expect(warnings, hasLength(1));
    expect(warnings.single, contains('Opaque'));
    expect(glb.json['meshes'], isNull);
    expect(
      (glb.json['nodes']! as List).single,
      isNot(contains('mesh')),
      reason: 'the node survives even though its mesh could not be written',
    );
  });
}
