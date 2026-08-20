// Per-instance custom attributes end to end on the CPU side: the schema
// resolved from a `.fmat` sidecar, the vertex layout it widens, the
// InstancedMesh setters, the packed records (including the mirrored split),
// and the batching opt-out. No GPU context is needed.

import 'dart:typed_data';

import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene/src/geometry/geometry.dart'
    show kUnskinnedInstancedLayout;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/instance_attributes.dart';
import 'package:flutter_scene/src/render/instance_batching.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _source = '''
material {
  name: "Inst",
  shading_model: unlit,
  instance_attributes: [
    { type: float, name: wobble },
    { type: vec3, name: tint_shift },
    { type: vec2, name: uv_pan },
  ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += instance_wobble;
  }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(GetInstanceTintShift(), 1.0);
    PrepareMaterial(material);
  }
}
''';

InstanceAttributeSchema _schema() =>
    InstanceAttributeSchema.fromMetadata(buildSidecar(parseFmat(_source)))!;

class _StubGeometry extends Geometry {
  _StubGeometry({VertexLayoutDescriptor? layout}) {
    if (layout != null) setVertexLayout(layout);
  }

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

class _StubMaterial extends Material {
  _StubMaterial({this.instanceAttributes});

  @override
  final InstanceAttributeSchema? instanceAttributes;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

class _OpaqueCandidate implements OpaqueBatchRecord {
  _OpaqueCandidate(this.geometry, this.material, this.pipeline);

  @override
  final Geometry geometry;
  @override
  final Material material;
  @override
  final Object pipeline;
  @override
  double get fade => 1;
  @override
  int get lightListOffset => 0;
  @override
  int get lightListCount => 0;
  @override
  int get lightChannelMask => 0xFF;
  @override
  Object? get jointsTexture => null;
}

InstancedMesh _mesh({InstanceAttributeSchema? schema}) => InstancedMesh(
  geometry: _StubGeometry(),
  material: _StubMaterial(instanceAttributes: schema),
);

void main() {
  group('schema', () {
    test('resolves declared order and the padded record width', () {
      final schema = _schema();
      expect(schema.attributes.map((a) => a.name), [
        'wobble',
        'tint_shift',
        'uv_pan',
      ]);
      // wobble at float 0, tint_shift at 1 (padded to four floats), uv_pan at
      // 5, so six floats past the fixed transform-and-color block.
      expect(schema.attributes.map((a) => a.floatOffset), [0, 1, 5]);
      expect(schema.floatCount, 7);
      expect(schema.recordBytes, 108);
    });

    test('widens the instance-rate slot with matching offsets', () {
      final widened = _schema().widen(kUnskinnedInstancedLayout.buffers.last);
      expect(widened.strideInBytes, 108);
      expect(widened.stepMode, gpu.VertexStepMode.instance);
      // The engine's five attributes are kept ahead of the declared ones.
      expect(widened.attributes.length, 8);
      expect(widened.attributes[4].name, 'instance_color');
      expect(
        widened.attributes.sublist(5).map((a) => (a.name, a.offsetInBytes)),
        [
          ('instance_wobble', 80),
          ('instance_tint_shift', 84),
          ('instance_uv_pan', 100),
        ],
      );
      expect(widened.attributes.sublist(5).map((a) => a.format), [
        gpu.VertexFormat.float32,
        gpu.VertexFormat.float32x3,
        gpu.VertexFormat.float32x2,
      ]);
    });

    test('rejects a base slot that is not the engine instance record', () {
      const custom = VertexBufferDescriptor(
        strideInBytes: 32,
        stepMode: gpu.VertexStepMode.instance,
        attributes: [
          VertexAttributeDescriptor(
            name: 'particle',
            format: gpu.VertexFormat.float32x4,
          ),
        ],
      );
      expect(
        () => _schema().widen(custom),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('80 bytes'), contains('32-byte')),
          ),
        ),
      );
    });

    test('the widened layout binds the names the shader declares', () {
      // flutter_gpu matches vertex attributes by name, and the emitter and the
      // runtime schema derive them independently, so they have to agree.
      final material = parseFmat(_source);
      final unskinned = emitVertexGlsl(material)['InstUnskinnedVertex']!;
      final widened = _schema().widen(kUnskinnedInstancedLayout.buffers.last);
      final bound = widened.attributes.map((a) => a.name).toSet();
      for (final a in material.instanceAttributes) {
        expect(bound, contains(a.inputName));
        expect(unskinned, contains('in ${a.type.glslType} ${a.inputName};'));
      }
    });

    test('the widened stride reaches the geometry vertex layout', () {
      final geometry = _StubGeometry(layout: kUnskinnedInstancedLayout);
      final plain = geometry.instancedVertexLayoutFor(null)!;
      expect(plain.buffers.last.strideInBytes, 80);

      final schema = _schema();
      final widened = geometry.instancedVertexLayoutFor(schema)!;
      expect(widened.buffers.length, plain.buffers.length);
      expect(widened.buffers.first, plain.buffers.first);
      expect(widened.buffers.last.strideInBytes, 108);
      // Memoized, so a per-frame resolve does not rebuild it.
      expect(
        identical(geometry.instancedVertexLayoutFor(schema), widened),
        isTrue,
      );
    });
  });

  group('InstancedMesh setters', () {
    test('writes each declared type into the packed record', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      mesh.setInstanceAttribute(0, 'wobble', 0.25);
      mesh.setInstanceAttribute(0, 'tint_shift', Vector3(1, 2, 3));
      mesh.setInstanceAttribute(0, 'uv_pan', Vector2(4, 5));
      expect(mesh.instanceAttributeFloats, 7);
      // The vec3's pad float stays zero between tint_shift and uv_pan.
      expect(mesh.instanceAttributeData, [0.25, 1, 2, 3, 0, 4, 5]);
    });

    test('an instance whose attributes are never set reads zero', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      mesh.addInstance(Matrix4.identity());
      mesh.setInstanceAttribute(1, 'wobble', 9);
      expect(mesh.instanceAttributeData!.sublist(0, 7), everyElement(0));
      expect(mesh.instanceAttributeData![7], 9);
    });

    test('throws on an unknown name', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      expect(
        () => mesh.setInstanceAttribute(0, 'nope', 1.0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Unknown instance attribute "nope"'),
          ),
        ),
      );
    });

    test('throws when the value does not match the declared type', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      expect(
        () => mesh.setInstanceAttribute(0, 'tint_shift', 1.0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Instance attribute "tint_shift" is vec3; cannot assign'),
          ),
        ),
      );
    });

    test('throws when the material declares no instance attributes', () {
      final mesh = _mesh();
      mesh.addInstance(Matrix4.identity());
      expect(mesh.instanceAttributeData, isNull);
      expect(mesh.instanceAttributeFloats, 0);
      expect(
        () => mesh.setInstanceAttribute(0, 'wobble', 1.0),
        throwsArgumentError,
      );
    });

    test('the bulk path lays out one packed record', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      mesh.addInstance(Matrix4.identity());
      mesh.setInstanceAttributes(
        1,
        Float32List.fromList([1, 2, 3, 4, 0, 5, 6]),
      );
      expect(mesh.instanceAttributeData!.sublist(7), [1, 2, 3, 4, 0, 5, 6]);
    });

    test('the bulk path names the expected length', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      expect(
        () => mesh.setInstanceAttributes(0, Float32List(3)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('packs 7 instance attribute float(s)'),
          ),
        ),
      );
    });

    test('removing an instance shifts the attributes down', () {
      final mesh = _mesh(schema: _schema());
      for (var i = 0; i < 3; i++) {
        mesh.addInstance(Matrix4.identity());
        mesh.setInstanceAttribute(i, 'wobble', i + 1);
      }
      mesh.removeInstanceAt(0);
      expect(mesh.instanceAttributeData!.length, 14);
      expect(mesh.instanceAttributeData![0], 2);
      expect(mesh.instanceAttributeData![7], 3);
      // A slot reused after a removal starts zeroed again.
      mesh.addInstance(Matrix4.identity());
      expect(mesh.instanceAttributeData!.sublist(14), everyElement(0));
    });

    test('clearing drops the packed attributes', () {
      final mesh = _mesh(schema: _schema());
      mesh.addInstance(Matrix4.identity());
      mesh.setInstanceAttribute(0, 'wobble', 1);
      mesh.clearInstances();
      expect(mesh.instanceAttributeData, isEmpty);
    });
  });

  group('packing', () {
    final attributes = Float32List.fromList([
      // Instance 0, then instance 1.
      1, 2, 3, 4, 0, 5, 6,
      7, 8, 9, 10, 0, 11, 12,
    ]);

    test('carries attribute bytes through the mirrored split', () {
      final packed = packInstanceData(
        Matrix4.identity(),
        [Matrix4.identity(), Matrix4.diagonal3Values(-1, 1, 1)],
        [Vector4(1, 1, 1, 1), Vector4(1, 1, 1, 1)],
        attributeData: attributes,
        attributeFloats: 7,
      );
      // One instance in each winding group, each carrying its own attributes.
      expect(packed.ccwCount, 1);
      expect(packed.cwCount, 1);
      expect(packed.ccw.sublist(20, 27), [1, 2, 3, 4, 0, 5, 6]);
      expect(packed.cw.sublist(20, 27), [7, 8, 9, 10, 0, 11, 12]);
    });

    test('carries them through the sorted translucent split', () {
      final packed = packInstanceData(
        Matrix4.identity(),
        [
          Matrix4.translation(Vector3(0, 0, 1)),
          Matrix4.translation(Vector3(0, 0, 9)),
        ],
        [Vector4(1, 1, 1, 1), Vector4(1, 1, 1, 1)],
        attributeData: attributes,
        attributeFloats: 7,
        sortBackToFrontFrom: Vector3.zero(),
      );
      expect(packed.ccwCount, 2);
      // Farthest first, so instance 1's attributes lead.
      expect(packed.ccw.sublist(20, 27), [7, 8, 9, 10, 0, 11, 12]);
      expect(packed.ccw.sublist(47, 54), [1, 2, 3, 4, 0, 5, 6]);
    });

    test('a cached batch is read at the wider source stride', () {
      final world = Float32List(2 * 27);
      for (var i = 0; i < 2; i++) {
        world.setAll(i * 27, Matrix4.identity().storage);
        world.setRange(i * 27 + 20, i * 27 + 27, attributes, i * 7);
      }
      final packed = packInstanceDataBatches([
        InstanceDataBatch.cached(
          packedWorldData: world,
          packedWindingFlipped: Uint8List.fromList([0, 1]),
          attributeFloats: 7,
        ),
      ], attributeFloats: 7);
      expect(packed.ccw.sublist(20, 27), [1, 2, 3, 4, 0, 5, 6]);
      expect(packed.cw.sublist(20, 27), [7, 8, 9, 10, 0, 11, 12]);

      // The depth-style pass reads the same source at 16 floats per record.
      final transforms = packInstanceTransformBatches([
        InstanceDataBatch.cached(
          packedWorldData: world,
          packedWindingFlipped: Uint8List.fromList([0, 1]),
          attributeFloats: 7,
        ),
      ]);
      expect(transforms.ccwCount, 1);
      expect(transforms.ccw.sublist(0, 16), Matrix4.identity().storage);
    });

    test('a batch without attribute data contributes zeros', () {
      // The scratch is reused, so prime it with a wide pack first; the
      // single-node record must not inherit those bytes.
      packInstanceData(
        Matrix4.identity(),
        [Matrix4.identity(), Matrix4.identity()],
        [Vector4(1, 1, 1, 1), Vector4(1, 1, 1, 1)],
        attributeData: attributes,
        attributeFloats: 7,
        scratch: transientInstancePackingScratch,
      );
      final packed = packInstanceDataBatches(
        [
          InstanceDataBatch.single(
            nodeTransform: Matrix4.identity(),
            nodeWindingFlipped: false,
          ),
        ],
        attributeFloats: 7,
        scratch: transientInstancePackingScratch,
      );
      expect(packed.ccwCount, 1);
      expect(packed.ccw.sublist(16, 20), [1, 1, 1, 1]);
      expect(packed.ccw.sublist(20, 27), everyElement(0));
    });
  });

  group('non-instanced draws', () {
    test('zero-fill the declared attributes', () {
      final record = packSingleInstanceData(
        Matrix4.translation(Vector3(1, 2, 3)),
        attributeFloats: 7,
      );
      expect(record.length, 27);
      expect(record.sublist(12, 15), [1, 2, 3]);
      expect(record.sublist(16, 20), [1, 1, 1, 1]);
      expect(record.sublist(20), everyElement(0));
      // A material declaring none keeps the fixed record byte for byte.
      expect(packSingleInstanceData(Matrix4.identity()).length, 20);
    });
  });

  group('draw-setup validation', () {
    test('a stride the material does not expect is a clear error', () {
      final schema = _schema();
      expect(() => checkInstanceRecordWidth(schema, 7), returnsNormally);
      expect(() => checkInstanceRecordWidth(null, 0), returnsNormally);
      expect(
        () => checkInstanceRecordWidth(schema, 0),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('expects 7 instance attribute float(s)'),
          ),
        ),
      );
      expect(() => checkInstanceRecordWidth(null, 4), throwsStateError);
    });
  });

  group('cross-node batching', () {
    test('excludes a material declaring instance attributes', () {
      final geometry = _StubGeometry(
        layout: const VertexLayoutDescriptor(buffers: []),
      );
      final pipeline = Object();

      final plain = _StubMaterial();
      final plainRecords = [
        _OpaqueCandidate(geometry, plain, pipeline),
        _OpaqueCandidate(geometry, plain, pipeline),
      ];
      expect(opaqueBatchEnd(plainRecords, 0), 2);

      final declaring = _StubMaterial(instanceAttributes: _schema());
      final declaringRecords = [
        _OpaqueCandidate(geometry, declaring, pipeline),
        _OpaqueCandidate(geometry, declaring, pipeline),
      ];
      expect(opaqueBatchEnd(declaringRecords, 0), 1);
    });
  });
}
