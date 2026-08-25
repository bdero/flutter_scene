// ShaderMaterial accessor and storage tests. The actual GPU bind
// path (RenderPass binding via getUniformSlot) requires a real
// Flutter GPU context and is exercised by the example app smoke test,
// not by unit tests.

import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;
// The revision counter the frame's scene-input summary is cached against is
// internal, and asserting the invalidation is the point of the last test here.
// ignore: implementation_imports
import 'package:flutter_scene/src/material/material.dart'
    show materialSceneInputsRevision;
import 'package:flutter_test/flutter_test.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

void main() {
  group('ShaderMaterial uniform block storage', () {
    test('setUniformBlock round-trips ByteData', () {
      final material = ShaderMaterial();
      final bytes = ByteData.sublistView(Float32List.fromList([1, 2, 3]));
      material.setUniformBlock('FragInfo', bytes);
      expect(material.getUniformBlock('FragInfo'), same(bytes));
      expect(material.uniformBlockNames, contains('FragInfo'));
    });

    test('setUniformBlock(null) clears the binding', () {
      final material = ShaderMaterial();
      material.setUniformBlock(
        'FragInfo',
        ByteData.sublistView(Float32List.fromList([1])),
      );
      material.setUniformBlock('FragInfo', null);
      expect(material.getUniformBlock('FragInfo'), isNull);
      expect(material.uniformBlockNames, isNot(contains('FragInfo')));
    });

    test('setUniformBlockFromFloats packs as Float32List', () {
      final material = ShaderMaterial();
      material.setUniformBlockFromFloats('FragInfo', [0.5, 1.0, 1.5, 2.0]);
      final bytes = material.getUniformBlock('FragInfo');
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, 16);
      expect(bytes.getFloat32(0, Endian.host), 0.5);
      expect(bytes.getFloat32(4, Endian.host), 1.0);
      expect(bytes.getFloat32(8, Endian.host), 1.5);
      expect(bytes.getFloat32(12, Endian.host), 2.0);
    });

    test('multiple uniform blocks remain independently addressable', () {
      final material = ShaderMaterial();
      material.setUniformBlockFromFloats('FragInfo', [1]);
      material.setUniformBlockFromFloats('ExtraInfo', [9, 9]);
      expect(
        material.uniformBlockNames,
        containsAll(['FragInfo', 'ExtraInfo']),
      );
      expect(material.getUniformBlock('FragInfo')!.lengthInBytes, 4);
      expect(material.getUniformBlock('ExtraInfo')!.lengthInBytes, 8);
    });
  });

  // Texture storage uses the same Map-backed pattern as uniform blocks
  // and shares an implementation path. Constructing a real
  // `gpu.Texture` requires a Flutter GPU context, so binding behavior
  // for textures is covered by the integration smoke test (the toon
  // example) rather than unit tests.

  group('ShaderMaterial render-state flags', () {
    test('isOpaque mirrors isOpaqueOverride', () {
      final opaque = ShaderMaterial();
      expect(opaque.isOpaque(), isTrue);
      opaque.isOpaqueOverride = false;
      expect(opaque.isOpaque(), isFalse);
    });
  });

  group('ShaderMaterial instance attributes', () {
    test('raw materials declare values accepted by InstancedMesh', () {
      final material = ShaderMaterial(
        instanceAttributes: const [
          ShaderInstanceAttribute('seed', ShaderInstanceAttributeType.float),
          ShaderInstanceAttribute('state', ShaderInstanceAttributeType.vec3),
        ],
      );
      final mesh = InstancedMesh(geometry: _StubGeometry(), material: material);
      final index = mesh.addInstance(Matrix4.identity());
      mesh
        ..setInstanceAttribute(index, 'seed', 3.0)
        ..setInstanceAttribute(index, 'state', Vector3(1.0, 2.0, 3.0));
    });

    test('rejects duplicate raw instance attribute names', () {
      expect(
        () => ShaderMaterial(
          instanceAttributes: const [
            ShaderInstanceAttribute('seed', ShaderInstanceAttributeType.float),
            ShaderInstanceAttribute('seed', ShaderInstanceAttributeType.vec2),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('ShaderMaterial scene inputs', () {
    test('requests nothing by default', () {
      expect(ShaderMaterial().sceneInputs, isEmpty);
    });

    test('carries what the constructor declared', () {
      final material = ShaderMaterial(
        sceneInputs: const {RenderInput.opaqueSceneColor, RenderInput.depth},
      );
      expect(
        material.sceneInputs,
        containsAll(<RenderInput>[
          RenderInput.opaqueSceneColor,
          RenderInput.depth,
        ]),
      );
    });

    test('a change invalidates the cached frame summary', () {
      final material = ShaderMaterial();
      final before = materialSceneInputsRevision;
      material.sceneInputs = const {RenderInput.depth};
      expect(materialSceneInputsRevision, greaterThan(before));

      // Setting an equal set is not a change and must not invalidate, or every
      // material assignment costs the frame its input summary.
      final after = materialSceneInputsRevision;
      material.sceneInputs = const {RenderInput.depth};
      expect(materialSceneInputsRevision, after);
    });

    test('declaring inputs at construction invalidates too', () {
      final before = materialSceneInputsRevision;
      ShaderMaterial(sceneInputs: const {RenderInput.depth});
      expect(materialSceneInputsRevision, greaterThan(before));

      // A material that declares nothing cannot change the frame's answer.
      final after = materialSceneInputsRevision;
      ShaderMaterial();
      expect(materialSceneInputsRevision, after);
    });

    test('rejects inputs only a custom render pass can ask for', () {
      expect(
        () => ShaderMaterial(sceneInputs: const {RenderInput.shadowMap}),
        throwsArgumentError,
      );
      expect(
        () => ShaderMaterial(sceneInputs: const {RenderInput.normals}),
        throwsArgumentError,
      );
      expect(
        () => ShaderMaterial().sceneInputs = const {RenderInput.shadowMap},
        throwsArgumentError,
      );
    });

    test('the filtered atlas implies the snapshot it is built from', () {
      final material = ShaderMaterial(
        sceneInputs: const {RenderInput.filteredSceneColor},
      );
      expect(
        material.sceneInputs,
        containsAll(<RenderInput>[
          RenderInput.filteredSceneColor,
          RenderInput.opaqueSceneColor,
        ]),
      );
    });

    test('the declared set cannot be mutated behind the invalidation', () {
      final declared = <RenderInput>{RenderInput.depth};
      final material = ShaderMaterial(sceneInputs: declared);

      // Mutating the caller's set must not reach the material, and the getter
      // must not hand out something a caller can mutate. Either would change
      // what the frame produces without bumping the revision.
      declared.add(RenderInput.opaqueSceneColor);
      expect(material.sceneInputs, const {RenderInput.depth});
      expect(
        () => material.sceneInputs.add(RenderInput.opaqueSceneColor),
        throwsUnsupportedError,
      );
    });
  });
}
