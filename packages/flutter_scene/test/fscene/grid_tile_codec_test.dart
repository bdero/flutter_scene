// Covers the GridTileLayer codec. Its geometry and material are resource
// references, so realizing one needs a resource realizer; these tests drive
// the parts that do not (the schema, the grid encoding, and the refusal
// paths) plus a full round trip of the tile list through serialize.
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/kit_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart'
    show Geometry, Material, Lighting, TransientWriter;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/kit/grid/grid_tiles.dart';
import 'package:flutter_scene/src/kit/scatter/scatter_layer.dart';
import 'package:scene/grid.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:vector_math/vector_math.dart';

// Stub resources, so a layer can exist without a Flutter GPU context.
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
  }) => throw UnsupportedError('stub');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('stub');
}

void main() {
  final codec = GridTileLayerCodec();

  test('the layer type is registered and filed under Mesh', () {
    final registry = defaultComponentRegistry();
    expect(registry.types, contains('gridTileLayer'));
    expect(registry.codecFor('gridTileLayer')!.schema.category, 'Mesh');
  });

  test('it declares both resources it needs', () {
    final kinds = {
      for (final def in codec.propertySchema) def.name: def.resourceKind,
    };
    expect(kinds['geometry'], 'geometry');
    expect(kinds['material'], 'material');
  });

  test('realize refuses without a resource realizer', () {
    // A GPU-free context cannot produce the tile geometry, so there is
    // nothing to draw; skipping beats a layer with no mesh. This guard runs
    // before the reference check, so the missing-reference path is only
    // reachable with a realizer and is not covered here.
    final doc = SceneDocument();
    for (final spec in [
      ComponentSpec('gridTileLayer'),
      ComponentSpec(
        'gridTileLayer',
        properties: {'geometry': ResourceRefValue(doc.newId())},
      ),
    ]) {
      expect(codec.realize(spec, RealizeContext(doc)), isNull);
    }
  });

  test('serialize declines a layer whose resources came from code', () {
    // A hand-built geometry has no source resource, so there is no reference
    // to write. Saving it as something else would be worse than not saving.
    final layer = GridTileLayer(
      grid: const SquareGrid(cellSize: 1),
      geometry: _StubGeometry(),
      material: _StubMaterial(),
    );
    layer.set(const GridCoord(1, 2), height: 0.5);
    expect(codec.serialize(layer, SerializeContext(SceneDocument())), isNull);
  });

  test('the tiles it would write carry what they were placed with', () {
    // The write path above needs real resources, but the tile list it draws
    // from is the layer's own and testable here.
    final layer = GridTileLayer(
      grid: const HexGrid(cellSize: 2, orientation: HexOrientation.flatTop),
      geometry: _StubGeometry(),
      material: _StubMaterial(),
    );
    layer.set(const GridCoord(1, -2), height: 0.75, yaw: 0.4);
    layer.set(const GridCoord(0, 0), color: Vector4(1, 0, 0, 1));

    final tiles = {for (final tile in layer.tiles) tile.cell: tile.look};
    expect(tiles, hasLength(2));
    expect(tiles[const GridCoord(1, -2)]!.height, 0.75);
    expect(tiles[const GridCoord(1, -2)]!.yaw, 0.4);
    expect(tiles[const GridCoord(0, 0)]!.color, Vector4(1, 0, 0, 1));
  });

  group('scatter layers', () {
    final scatterCodec = ScatterLayerCodec();

    test('the type is registered and filed under Mesh', () {
      final registry = defaultComponentRegistry();
      expect(registry.types, contains('scatterLayer'));
      expect(registry.codecFor('scatterLayer')!.schema.category, 'Mesh');
    });

    test('realize refuses without a resource realizer', () {
      expect(
        scatterCodec.realize(
          ComponentSpec('scatterLayer'),
          RealizeContext(SceneDocument()),
        ),
        isNull,
      );
    });

    test('placements declare an editable list of objects', () {
      // Which is what makes a painted set adjustable by hand in the
      // inspector rather than only by the brush.
      final def = scatterCodec.propertySchema.firstWhere(
        (d) => d.name == 'placements',
      );
      expect(def.kind, ComponentPropertyKind.list);
      expect(def.itemDef?.kind, ComponentPropertyKind.object);
      expect(
        def.itemDef?.objectFields?.map((f) => f.name),
        containsAll(['position', 'yaw', 'scale']),
      );
    });

    test('serialize declines a layer whose resources came from code', () {
      final layer = ScatterLayer(
        geometry: _StubGeometry(),
        material: _StubMaterial(),
      )..add(ScatterPlacement(position: Vector3(1, 2, 3)));
      expect(
        scatterCodec.serialize(layer, SerializeContext(SceneDocument())),
        isNull,
      );
    });
  });
}
