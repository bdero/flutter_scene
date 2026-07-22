import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/components/materials_variants_component.dart'
    show MaterialsVariantBinding;
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_scene.dart' show RenderScene;
import 'package:test/test.dart';

/// KHR_materials_variants: parsing (pure data, no GPU) and the selection
/// component's material swapping (fake materials, no GPU).

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

Map<String, Object?> _documentJson() => {
  'asset': {'version': '2.0'},
  'extensionsUsed': ['KHR_materials_variants'],
  'extensions': {
    'KHR_materials_variants': {
      'variants': [
        {'name': 'midnight'},
        {'name': 'beach'},
        {'name': 'street'},
      ],
    },
  },
  'scenes': [
    {
      'nodes': [0],
    },
  ],
  'nodes': [
    {'mesh': 0},
  ],
  'materials': [
    {'name': 'a'},
    {'name': 'b'},
    {'name': 'c'},
  ],
  'meshes': [
    {
      'primitives': [
        {
          'attributes': {'POSITION': 0},
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
                {
                  'material': 2,
                  'variants': [2],
                },
              ],
            },
          },
        },
      ],
    },
  ],
};

void main() {
  group('parseGltfJson KHR_materials_variants', () {
    test('parses document variant names in order', () {
      final doc = parseGltfJson(_documentJson());
      expect(doc.materialsVariants, ['midnight', 'beach', 'street']);
    });

    test('flattens primitive mappings to variant->material', () {
      final doc = parseGltfJson(_documentJson());
      final primitive = doc.meshes.first.primitives.first;
      expect(primitive.variantMappings, {0: 0, 1: 1, 2: 2});
    });

    test('a mapping covering several variants maps each of them', () {
      final json = _documentJson();
      final meshes = json['meshes'] as List;
      final primitive =
          ((meshes.first as Map)['primitives'] as List).first as Map;
      (primitive['extensions'] as Map)['KHR_materials_variants'] = {
        'mappings': [
          {
            'material': 1,
            'variants': [0, 2],
          },
        ],
      };
      final doc = parseGltfJson(json);
      expect(doc.meshes.first.primitives.first.variantMappings, {0: 1, 2: 1});
    });

    test('document without the extension parses to empty variants', () {
      final json = _documentJson()..remove('extensions');
      final doc = parseGltfJson(json);
      expect(doc.materialsVariants, isEmpty);
    });
  });

  group('MaterialsVariantsComponent', () {
    late _FakeMaterial defaultA;
    late _FakeMaterial defaultB;
    late _FakeMaterial beachA;
    late MeshPrimitive primitiveA;
    late MeshPrimitive primitiveB;
    late Node nodeA;
    late Node nodeB;
    late MaterialsVariantsComponent component;

    setUp(() {
      defaultA = _FakeMaterial('defaultA');
      defaultB = _FakeMaterial('defaultB');
      beachA = _FakeMaterial('beachA');
      primitiveA = MeshPrimitive(_FakeGeometry(), defaultA);
      primitiveB = MeshPrimitive(_FakeGeometry(), defaultB);
      nodeA = Node()..mesh = Mesh.primitives(primitives: [primitiveA]);
      nodeB = Node()..mesh = Mesh.primitives(primitives: [primitiveB]);
      component = MaterialsVariantsComponent.internal(
        ['midnight', 'beach'],
        [
          MaterialsVariantBinding(
            node: nodeA,
            primitive: primitiveA,
            defaultMaterial: defaultA,
            materialsByVariant: {0: defaultA, 1: beachA},
          ),
          // primitiveB only maps variant 0; 'beach' leaves it on its default.
          MaterialsVariantBinding(
            node: nodeB,
            primitive: primitiveB,
            defaultMaterial: defaultB,
            materialsByVariant: {0: defaultB},
          ),
        ],
      );
    });

    test('exposes declared variant names and starts unselected', () {
      expect(component.variants, ['midnight', 'beach']);
      expect(component.selected, isNull);
    });

    test('select swaps mapped primitives and leaves unmapped on default', () {
      component.select('beach');
      expect(component.selected, 'beach');
      expect(identical(primitiveA.material, beachA), isTrue);
      expect(identical(primitiveB.material, defaultB), isTrue);
    });

    test('select(null) restores defaults', () {
      component.select('beach');
      component.select(null);
      expect(component.selected, isNull);
      expect(identical(primitiveA.material, defaultA), isTrue);
      expect(identical(primitiveB.material, defaultB), isTrue);
    });

    test('select throws on an unknown name', () {
      expect(() => component.select('nope'), throwsArgumentError);
    });

    test('variants list is unmodifiable', () {
      expect(() => component.variants.add('x'), throwsUnsupportedError);
    });

    test('select refreshes a mounted mesh\'s render items', () {
      // Render items capture the material at registration; a variant swap on
      // a live scene must re-register so the new material actually draws.
      final renderScene = RenderScene();
      nodeA.debugMountInto(renderScene);
      expect(renderScene.items, hasLength(1));
      expect(identical(renderScene.items.single.material, defaultA), isTrue);

      component.select('beach');
      expect(renderScene.items, hasLength(1));
      expect(identical(renderScene.items.single.material, beachA), isTrue);

      component.select(null);
      expect(identical(renderScene.items.single.material, defaultA), isTrue);
    });
  });

  test('runtime import attaches the component for variant documents', () {
    // Structural check only: the full import needs a GPU for textures, so
    // this asserts the parsed document carries what _buildScene consumes.
    final doc = parseGltfJson(_documentJson());
    expect(doc.materialsVariants, isNotEmpty);
    expect(doc.meshes.first.primitives.first.variantMappings, isNotEmpty);
  });
}
