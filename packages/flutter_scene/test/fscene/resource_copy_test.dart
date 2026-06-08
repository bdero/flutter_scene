// Covers copyResourceInto: moving a resource and the payload chunks it
// references from one document into another with ids preserved. This is the
// GPU-free half of mesh serialization (the realizer stamps live objects with
// their origin, and the serializer copies those origins here).

import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('copyResourceInto', () {
    test('copies a payload-backed geometry with its chunks and ids', () {
      final source = SceneDocument();
      final vertices = source.addPayload(
        PayloadSpec(
          source.newId(),
          encoding: PayloadEncoding.vertexBuffer,
          layout: 'unskinned',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      final indices = source.addPayload(
        PayloadSpec(
          source.newId(),
          encoding: PayloadEncoding.indexBuffer,
          format: 'uint16',
          bytes: Uint8List.fromList([9, 8]),
        ),
      );
      final geometry = source.addResource(
        GeometryResource(
          source.newId(),
          vertices: vertices.id,
          indices: indices.id,
        ),
      );

      final dest = SceneDocument();
      final copiedId = copyResourceInto(dest, source, geometry.id);

      expect(copiedId, geometry.id);
      final copied = dest.resource(geometry.id) as GeometryResource;
      expect(copied.vertices, vertices.id);
      expect(copied.indices, indices.id);
      expect(dest.payload(vertices.id)!.bytes, equals(vertices.bytes));
      expect(dest.payload(indices.id)!.format, 'uint16');
      expect(dest.payload(indices.id)!.bytes, equals(indices.bytes));
    });

    test('copies a procedural geometry without any payloads', () {
      final source = SceneDocument();
      final geometry = source.addResource(
        GeometryResource(
          source.newId(),
          procedural: CuboidGeometrySpec(extents: Vector3(1, 1, 1)),
        ),
      );

      final dest = SceneDocument();
      copyResourceInto(dest, source, geometry.id);

      final copied = dest.resource(geometry.id) as GeometryResource;
      expect(copied.procedural, isA<CuboidGeometrySpec>());
      expect(dest.payloads, isEmpty);
    });

    test('copies a material together with its texture and image chunk', () {
      final source = SceneDocument();
      final image = source.addPayload(
        PayloadSpec(
          source.newId(),
          encoding: PayloadEncoding.image,
          format: 'rgba8',
          width: 1,
          height: 1,
          bytes: Uint8List.fromList([255, 255, 255, 255]),
        ),
      );
      final texture = source.addResource(
        TextureResource(source.newId(), payload: image.id),
      );
      final material = source.addResource(
        MaterialResource(
          source.newId(),
          type: 'physicallyBased',
          properties: {'baseColorTexture': ResourceRefValue(texture.id)},
        ),
      );

      final dest = SceneDocument();
      copyResourceInto(dest, source, material.id);

      expect(dest.resource(material.id), isA<MaterialResource>());
      expect(dest.resource(texture.id), isA<TextureResource>());
      expect(dest.payload(image.id)!.bytes, equals(image.bytes));
    });

    test('is idempotent for a resource shared by several meshes', () {
      final source = SceneDocument();
      final vertices = source.addPayload(
        PayloadSpec(
          source.newId(),
          encoding: PayloadEncoding.vertexBuffer,
          layout: 'unskinned',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      final geometry = source.addResource(
        GeometryResource(source.newId(), vertices: vertices.id),
      );

      final dest = SceneDocument();
      copyResourceInto(dest, source, geometry.id);
      copyResourceInto(dest, source, geometry.id);

      expect(dest.resources, hasLength(1));
      expect(dest.payloads, hasLength(1));
    });
  });
}
