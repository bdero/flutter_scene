import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' hide Animation;
// ignore: implementation_imports
import 'package:flutter_scene/src/components/materials_variants_component.dart'
    show MaterialsVariantBinding;
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/property_value.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/builtin_codecs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/scene_document.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:test/test.dart';

/// KHR_materials_variants through the `.fscene` document pipeline: the glTF
/// importer emits a `materialsVariants` component, it survives the JSON
/// round-trip, and the codec realizes and serializes it (GPU-free via fake
/// materials).

class _FakeMaterial implements Material {
  _FakeMaterial(this.label);
  final String label;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGeometry implements Geometry {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRealizer implements ResourceRealizer {
  _FakeRealizer(this.materials);
  final Map<LocalId, Material> materials;

  @override
  Material material(LocalId id) => materials[id]!;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Builds a minimal GLB: one triangle mesh with two materials and a
/// two-variant `KHR_materials_variants` declaration mapping them.
Uint8List _buildVariantsGlb() {
  // Positions (3 vec3), normals (3 vec3), uvs (3 vec2), indices (3 uint16).
  final buffer = BytesBuilder();
  buffer.add(
    Float32List.fromList([
      0, 0, 0, 1, 0, 0, 0, 1, 0, // positions
      0, 0, 1, 0, 0, 1, 0, 0, 1, // normals
      0, 0, 1, 0, 0, 1, // uvs
    ]).buffer.asUint8List(),
  );
  buffer.add(Uint16List.fromList([0, 1, 2]).buffer.asUint8List());
  buffer.add(Uint8List(2)); // pad to 4-byte alignment
  final bin = buffer.takeBytes();

  final json = {
    'asset': {'version': '2.0'},
    'extensionsUsed': ['KHR_materials_variants'],
    'extensions': {
      'KHR_materials_variants': {
        'variants': [
          {'name': 'alpha'},
          {'name': 'beta'},
        ],
      },
    },
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'scene': 0,
    'nodes': [
      {'name': 'tri', 'mesh': 0},
    ],
    'materials': [
      {'name': 'matA'},
      {'name': 'matB'},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2},
            'indices': 3,
            'material': 0,
            'extensions': {
              'KHR_materials_variants': {
                'mappings': [
                  {
                    'material': 0,
                    'variants': [0],
                  },
                  {
                    'material': 1,
                    'variants': [1],
                  },
                ],
              },
            },
          },
        ],
      },
    ],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 36, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 72, 'byteLength': 24},
      {'buffer': 0, 'byteOffset': 96, 'byteLength': 6},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0, 0, 0],
        'max': [1, 1, 0],
      },
      {'bufferView': 1, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5126, 'count': 3, 'type': 'VEC2'},
      {'bufferView': 3, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'},
    ],
  };

  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadded = jsonBytes.length % 4 == 0
      ? jsonBytes.length
      : jsonBytes.length + (4 - jsonBytes.length % 4);
  final binPadded = bin.length % 4 == 0
      ? bin.length
      : bin.length + (4 - bin.length % 4);
  final total = 12 + 8 + jsonPadded + 8 + binPadded;
  final out = BytesBuilder();
  void u32(int value) => out.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
  );
  out.add(ascii.encode('glTF'));
  u32(2);
  u32(total);
  u32(jsonPadded);
  out.add(ascii.encode('JSON'));
  out.add(jsonBytes);
  for (var i = jsonBytes.length; i < jsonPadded; i++) {
    out.add(const [0x20]); // JSON chunks pad with spaces
  }
  u32(binPadded);
  out.add([0x42, 0x49, 0x4E, 0x00]); // 'BIN\0'
  out.add(bin);
  for (var i = bin.length; i < binPadded; i++) {
    out.add(const [0]);
  }
  return out.takeBytes();
}

ComponentSpec? _variantsComponent(SceneDocument document) {
  for (final rootId in document.roots) {
    for (final component in document.nodes[rootId]!.components) {
      if (component.type == 'materialsVariants') return component;
    }
  }
  return null;
}

void main() {
  group('emitter', () {
    late SceneDocument document;

    setUpAll(() {
      document = importGlbToSceneDocument(_buildVariantsGlb());
    });

    test('attaches a materialsVariants component to the root', () {
      final component = _variantsComponent(document);
      expect(component, isNotNull);
      final variants = component!.properties['variants'] as ListValue;
      expect(
        [for (final v in variants.values) (v as StringValue).value],
        ['alpha', 'beta'],
      );
      expect(document.featuresUsed, contains('materialsVariants'));
    });

    test('bindings reference the mesh node, primitive, and materials', () {
      final component = _variantsComponent(document)!;
      final bindings = component.properties['bindings'] as ListValue;
      expect(bindings.values, hasLength(1));
      final binding = bindings.values.single as MapValue;
      final nodeRef = binding.values['node'] as NodeRefValue;
      final rootSpec = document.nodes[document.roots.single]!;
      expect(nodeRef.id, rootSpec.id);
      expect((binding.values['primitive'] as IntValue).value, 0);
      final materials = binding.values['materials'] as MapValue;
      expect(materials.values.keys.toSet(), {'0', '1'});
      // Each mapped id must be a registered material resource.
      for (final value in materials.values.values) {
        final resource = document.resources[(value as ResourceRefValue).id];
        expect(resource, isA<MaterialResource>());
      }
      // Variant 0 maps the same material the mesh uses as its default.
      final meshComponent = rootSpec.components.firstWhere(
        (c) => c.type == 'mesh',
      );
      expect(
        (materials.values['0'] as ResourceRefValue).id,
        (meshComponent.properties['material'] as ResourceRefValue).id,
      );
    });

    test('the component survives the canonical JSON round-trip', () {
      final text = writeFscene(document);
      final reread = readFscene(text);
      expect(writeFscene(reread), text);
      final component = _variantsComponent(reread);
      expect(component, isNotNull);
      final variants = component!.properties['variants'] as ListValue;
      expect(variants.values, hasLength(2));
      expect(
        (component.properties['bindings'] as ListValue).values,
        hasLength(1),
      );
    });
  });

  group('codec', () {
    test('realizes bindings after the tree exists and select swaps', () {
      final document = SceneDocument();
      final nodeId = document.newId();
      final defaultId = document.newId();
      final betaId = document.newId();

      final defaultMaterial = _FakeMaterial('default');
      final betaMaterial = _FakeMaterial('beta');
      final primitive = MeshPrimitive(_FakeGeometry(), defaultMaterial);
      final liveNode = tagNodeId(
        Node(name: 'tri')..mesh = Mesh.primitives(primitives: [primitive]),
        nodeId,
      );

      final context = RealizeContext(
        document,
        resources: _FakeRealizer({
          defaultId: defaultMaterial,
          betaId: betaMaterial,
        }),
      );
      context.resolveNode = (id) => id == nodeId ? liveNode : null;

      final spec = ComponentSpec(
        'materialsVariants',
        properties: {
          'variants': ListValue([StringValue('alpha'), StringValue('beta')]),
          'bindings': ListValue([
            MapValue({
              'node': NodeRefValue(nodeId),
              'primitive': const IntValue(0),
              'materials': MapValue({
                '0': ResourceRefValue(defaultId),
                '1': ResourceRefValue(betaId),
              }),
            }),
          ]),
        },
      );

      final component =
          MaterialsVariantsCodec().realize(spec, context)
              as MaterialsVariantsComponent;
      // Bindings resolve only after the deferred pass runs.
      component.select('beta');
      expect(identical(primitive.material, defaultMaterial), isTrue);

      context.runAfterRealize();
      component.select('beta');
      expect(identical(primitive.material, betaMaterial), isTrue);
      component.select(null);
      expect(identical(primitive.material, defaultMaterial), isTrue);
    });

    test('serializes variants, node ref, primitive index, and materials', () {
      final source = SceneDocument();
      final nodeId = source.newId();
      final betaResource = source.addResource(
        MaterialResource(source.newId(), type: 'physicallyBased', name: 'b'),
      );

      final defaultMaterial = _FakeMaterial('default');
      final betaMaterial = tagResourceOrigin(
        _FakeMaterial('beta'),
        source,
        betaResource.id,
      );
      final primitive = MeshPrimitive(_FakeGeometry(), defaultMaterial);
      final liveNode = tagNodeId(
        Node(name: 'tri')..mesh = Mesh.primitives(primitives: [primitive]),
        nodeId,
      );
      final component = MaterialsVariantsComponent.internal(
        ['alpha', 'beta'],
        [
          MaterialsVariantBinding(
            node: liveNode,
            primitive: primitive,
            defaultMaterial: defaultMaterial,
            materialsByVariant: {1: betaMaterial},
          ),
        ],
      );

      final dest = SceneDocument();
      final spec = MaterialsVariantsCodec().serialize(
        component,
        SerializeContext(dest),
      )!;
      expect(spec.type, 'materialsVariants');
      final variants = spec.properties['variants'] as ListValue;
      expect(
        [for (final v in variants.values) (v as StringValue).value],
        ['alpha', 'beta'],
      );
      final binding =
          (spec.properties['bindings'] as ListValue).values.single as MapValue;
      expect((binding.values['node'] as NodeRefValue).id, nodeId);
      expect((binding.values['primitive'] as IntValue).value, 0);
      final materials = binding.values['materials'] as MapValue;
      expect(materials.values.keys.toList(), ['1']);
      // The variant material was copied into the destination document.
      final copiedId = (materials.values['1'] as ResourceRefValue).id;
      expect(dest.resources[copiedId], isA<MaterialResource>());
    });
  });
}
