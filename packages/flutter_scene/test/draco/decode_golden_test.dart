// End-to-end golden coverage for the Draco decoder. Each compressed fixture
// is decoded and its attribute and index output byte-compared against the
// matching *_decoded.glb, produced by the reference decoder (see
// test/fixtures/draco/generate.sh).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/mesh_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/fixtures/draco';

class _Fixture {
  _Fixture(this.compressed, this.decoded);

  final _Glb compressed;
  final _Glb decoded;
}

class _Glb {
  _Glb(this.json, this.doc, this.bin);

  final Map<String, Object?> json;
  final GltfDocument doc;
  final Uint8List bin;

  /// Raw packed bytes of an accessor, de-interleaved when the buffer view
  /// carries a byte stride.
  Uint8List accessorBytes(int accessorIndex) {
    final accessor = doc.accessors[accessorIndex];
    final view = doc.bufferViews[accessor.bufferView!];
    final elementSize =
        accessor.componentType.bytes * accessor.type.componentCount;
    final stride = view.byteStride ?? elementSize;
    final start = view.byteOffset + accessor.byteOffset;
    final out = Uint8List(accessor.count * elementSize);
    for (var i = 0; i < accessor.count; i++) {
      out.setRange(
        i * elementSize,
        (i + 1) * elementSize,
        bin,
        start + i * stride,
      );
    }
    return out;
  }
}

_Fixture _loadFixture(String name) {
  _Glb load(String path) {
    final contents = parseGlb(File(path).readAsBytesSync());
    return _Glb(
      contents.json,
      parseGltfJson(contents.json),
      contents.binaryChunk,
    );
  }

  return _Fixture(
    load('$_fixtureDir/$name.glb'),
    load('$_fixtureDir/${name}_decoded.glb'),
  );
}

/// The raw KHR_draco_mesh_compression extension json for a primitive.
Map<String, Object?>? _dracoExtension(
  Map<String, Object?> json,
  int meshIndex,
  int primitiveIndex,
) {
  final meshes = json['meshes'] as List;
  final primitives = (meshes[meshIndex] as Map)['primitives'] as List;
  final extensions = (primitives[primitiveIndex] as Map)['extensions'] as Map?;
  final draco = extensions?['KHR_draco_mesh_compression'] as Map?;
  return draco?.cast<String, Object?>();
}

void _checkPrimitive(_Fixture fixture, int meshIndex, int primitiveIndex) {
  final draco = _dracoExtension(
    fixture.compressed.json,
    meshIndex,
    primitiveIndex,
  );
  expect(draco, isNotNull, reason: 'fixture primitive is not Draco compressed');

  final viewIndex = draco!['bufferView'] as int;
  final view = fixture.compressed.doc.bufferViews[viewIndex];
  final payload = Uint8List.sublistView(
    fixture.compressed.bin,
    view.byteOffset,
    view.byteOffset + view.byteLength,
  );
  final decoded = decodeDracoMesh(payload);

  final referencePrimitive =
      fixture.decoded.doc.meshes[meshIndex].primitives[primitiveIndex];

  // Indices.
  final referenceIndices = readAccessorAsUint32(
    fixture.decoded.doc.accessors[referencePrimitive.indices!],
    fixture.decoded.doc.bufferViews[fixture
        .decoded
        .doc
        .accessors[referencePrimitive.indices!]
        .bufferView!],
    fixture.decoded.bin,
  );
  expect(decoded.faces.length, referenceIndices.length, reason: 'index count');
  for (var i = 0; i < referenceIndices.length; i++) {
    expect(decoded.faces[i], referenceIndices[i], reason: 'index $i');
  }

  // Attributes, byte-exact against the reference decode.
  final attributeMap = (draco['attributes'] as Map).cast<String, int>();
  expect(attributeMap, isNotEmpty);
  for (final entry in attributeMap.entries) {
    final attribute = decoded.attributeByUniqueId(entry.value);
    expect(attribute, isNotNull, reason: 'missing attribute ${entry.key}');
    final actual = attribute!.pointBytes(decoded.numPoints);
    final referenceAccessor = referencePrimitive.attributes[entry.key]!;
    final referenceCount =
        fixture.decoded.doc.accessors[referenceAccessor].count;
    expect(decoded.numPoints, referenceCount, reason: 'point count');
    final expected = fixture.decoded.accessorBytes(referenceAccessor);
    expect(
      actual.length,
      expected.length,
      reason: 'byte length of ${entry.key}',
    );
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) {
        fail(
          'attribute ${entry.key} differs at byte $i '
          '(${actual[i]} != ${expected[i]})',
        );
      }
    }
  }
}

void main() {
  test('decodes sequential connectivity byte-exact', () {
    final fixture = _loadFixture('synthetic_draco_seq');
    _checkPrimitive(fixture, 0, 0);
  });

  test('decodes EdgeBreaker connectivity byte-exact', () {
    final fixture = _loadFixture('synthetic_draco_eb');
    _checkPrimitive(fixture, 0, 0);
  });

  test('decodes skinned EdgeBreaker primitives byte-exact', () {
    final fixture = _loadFixture('two_triangles_draco_eb');
    _checkPrimitive(fixture, 0, 0);
    _checkPrimitive(fixture, 0, 1);
  });

  test('decodes high compression EdgeBreaker byte-exact', () {
    // Valence coded traversal plus the stronger prediction schemes.
    final fixture = _loadFixture('synthetic_draco_eb_cl10');
    _checkPrimitive(fixture, 0, 0);
  });

  test('decodes valence coded traversal byte-exact', () {
    // 1058 faces crosses the encoder's threshold for valence coding.
    final fixture = _loadFixture('synthetic_draco_eb_valence');
    _checkPrimitive(fixture, 0, 0);
  });

  test('decodes attribute seams byte-exact', () {
    // Flat shaded cube, deduplicated positions force per-corner attributes.
    final fixture = _loadFixture('cube_draco_eb');
    _checkPrimitive(fixture, 0, 0);
  });

  test('decodes attribute seams at high compression byte-exact', () {
    final fixture = _loadFixture('cube_draco_eb_cl10');
    _checkPrimitive(fixture, 0, 0);
  });
}
