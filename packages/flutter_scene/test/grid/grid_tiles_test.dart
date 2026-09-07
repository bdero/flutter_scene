// Covers GridTileLayer: tiles land on their cells, the instance batch stays
// dense as tiles come and go, and removing one never displaces another.

import 'package:flutter_scene/grid.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Stub geometry and material, so the tests run without a Flutter GPU context.
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
  }) => throw UnsupportedError('Stub geometry is not renderable');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('Stub material is not renderable');
}

GridTileLayer _layer({Grid? grid}) => GridTileLayer(
  grid: grid ?? const SquareGrid(cellSize: 2.0),
  geometry: _StubGeometry(),
  material: _StubMaterial(),
);

Vector3 _instanceAt(GridTileLayer layer, GridCoord cell) {
  // Resolve through the layer's own bookkeeping the same way the renderer
  // does, so a stale index shows up as a wrong position rather than silently.
  final index = layer.cells.toList().indexOf(cell);
  expect(index, isNonNegative, reason: '$cell is not in the layer');
  return layer.mesh.instances[index].getTranslation();
}

void main() {
  group('GridTileLayer', () {
    test('places a tile on its cell centre', () {
      final layer = _layer();
      layer.set(const GridCoord(3, -1));

      expect(layer.length, 1);
      expect(layer.contains(const GridCoord(3, -1)), isTrue);
      expect(layer.mesh.instanceCount, 1);

      final position = layer.mesh.instances.single.getTranslation();
      expect(position.x, closeTo(6.0, 1e-5));
      expect(position.y, closeTo(0.0, 1e-5));
      expect(position.z, closeTo(-2.0, 1e-5));
    });

    test('lifts, turns, scales, and tints a tile', () {
      final layer = _layer();
      layer.set(
        GridCoord.origin,
        height: 1.5,
        yaw: 0.5,
        scale: Vector3(2.0, 2.0, 2.0),
        color: Vector4(1.0, 0.0, 0.0, 1.0),
      );
      final transform = layer.mesh.instances.single;
      expect(transform.getTranslation().y, closeTo(1.5, 1e-5));
      expect(transform.getColumn(0).length, closeTo(2.0, 1e-5));
    });

    test('setting an occupied cell replaces rather than stacks', () {
      final layer = _layer();
      layer.set(GridCoord.origin);
      layer.set(GridCoord.origin, height: 5.0);

      expect(layer.length, 1);
      expect(layer.mesh.instanceCount, 1);
      expect(
        layer.mesh.instances.single.getTranslation().y,
        closeTo(5.0, 1e-5),
      );
    });

    test('removing a tile leaves every other tile where it was', () {
      // The swap-remove is the subtle part: pulling a tile out of the middle
      // moves the last instance into its slot, and the bookkeeping has to
      // follow or two tiles end up drawn on top of each other.
      final layer = _layer();
      final cells = [for (var x = 0; x < 6; x++) GridCoord(x, 0)];
      for (final cell in cells) {
        layer.set(cell);
      }

      expect(layer.remove(const GridCoord(2, 0)), isTrue);
      expect(layer.remove(const GridCoord(0, 0)), isTrue);
      expect(layer.length, 4);
      expect(layer.mesh.instanceCount, 4);

      for (final cell in cells) {
        if (cell.x == 0 || cell.x == 2) {
          expect(layer.contains(cell), isFalse);
          continue;
        }
        final position = _instanceAt(layer, cell);
        expect(position.x, closeTo(cell.x * 2.0, 1e-5), reason: '$cell moved');
        expect(position.z, closeTo(0.0, 1e-5));
      }
    });

    test('removing an empty cell reports it', () {
      final layer = _layer();
      expect(layer.remove(const GridCoord(9, 9)), isFalse);
    });

    test('removing every tile in turn leaves nothing behind', () {
      final layer = _layer();
      final cells = [
        for (var x = -3; x <= 3; x++)
          for (var y = -3; y <= 3; y++) GridCoord(x, y),
      ];
      for (final cell in cells) {
        layer.set(cell);
      }
      for (final cell in cells) {
        expect(layer.remove(cell), isTrue);
      }
      expect(layer.isEmpty, isTrue);
      expect(layer.mesh.instanceCount, 0);
    });

    test('fills a region', () {
      final layer = _layer();
      layer.fill(GridRect.sized(GridCoord.origin, 4, 3), height: 0.5);
      expect(layer.length, 12);
      expect(layer.mesh.instanceCount, 12);
      expect(layer.mesh.instances.first.getTranslation().y, closeTo(0.5, 1e-5));
    });

    test('fills from a GridMap, asking how each tile looks', () {
      final terrain = GridMap<int>();
      terrain[const GridCoord(0, 0)] = 1;
      terrain[const GridCoord(1, 0)] = 3;

      final layer = _layer();
      layer.fillFrom(
        terrain,
        build: (cell, value) => GridTileAppearance(height: value.toDouble()),
      );

      expect(layer.length, 2);
      expect(_instanceAt(layer, const GridCoord(1, 0)).y, closeTo(3.0, 1e-5));
    });

    test('clear empties the batch', () {
      final layer = _layer();
      layer.fill(GridRect.sized(GridCoord.origin, 3, 3));
      layer.clear();
      expect(layer.isEmpty, isTrue);
      expect(layer.mesh.instanceCount, 0);
    });

    test('rebuild follows a changed grid', () {
      final layer = _layer();
      layer.set(const GridCoord(2, 0));
      expect(
        layer.mesh.instances.single.getTranslation().x,
        closeTo(4.0, 1e-5),
      );

      layer.grid = const SquareGrid(cellSize: 5.0);
      layer.rebuild();
      expect(
        layer.mesh.instances.single.getTranslation().x,
        closeTo(10.0, 1e-5),
      );
    });

    test('draws through an instanced mesh component once attached', () {
      final layer = _layer();
      final node = Node();
      node.addComponent(layer);
      expect(node.getComponent<InstancedMeshComponent>(), isNotNull);

      node.removeComponent(layer);
      expect(node.getComponent<InstancedMeshComponent>(), isNull);
    });

    test('works on a hex grid', () {
      final layer = _layer(grid: const HexGrid(cellSize: 1.0));
      layer.set(const GridCoord(1, 0));
      final position = layer.mesh.instances.single.getTranslation();
      // One step east on a pointy-top hex grid is sqrt(3) across.
      expect(position.x, closeTo(1.7320508, 1e-4));
      expect(position.z, closeTo(0.0, 1e-5));
    });
  });

  test('rebuild keeps each tile\'s height, yaw and scale', () {
    // rebuild() used to write a bare translation, so changing the grid
    // silently flattened every tile that had been lifted, turned or scaled --
    // exactly the case its own doc tells you to call it for.
    var grid = const SquareGrid(cellSize: 1.0);
    final layer = GridTileLayer(
      grid: grid,
      geometry: _StubGeometry(),
      material: _StubMaterial(),
    );
    const cell = GridCoord(2, 3);
    layer.set(cell, height: 1.5, yaw: 0.8, scale: Vector3(2.0, 2.0, 2.0));

    grid = const SquareGrid(cellSize: 4.0);
    layer.grid = grid;
    layer.rebuild();

    final look = layer.appearanceOf(cell)!;
    expect(look.height, 1.5);
    expect(look.yaw, 0.8);
    expect(look.scale!.x, 2.0);

    final center = grid.center(cell);
    final placed = layer.mesh.getInstanceTransform(0);
    expect(placed.getTranslation().y, closeTo(center.y + 1.5, 1e-6));
    expect(placed.getTranslation().x, closeTo(center.x, 1e-6));
  });

  test('removing a tile forgets its appearance', () {
    final layer = GridTileLayer(
      grid: const SquareGrid(cellSize: 1.0),
      geometry: _StubGeometry(),
      material: _StubMaterial(),
    );
    const cell = GridCoord(0, 0);
    layer.set(cell, height: 2.0);
    expect(layer.appearanceOf(cell), isNotNull);
    expect(layer.remove(cell), isTrue);
    expect(layer.appearanceOf(cell), isNull);
    expect(layer.tiles, isEmpty);
  });
}
