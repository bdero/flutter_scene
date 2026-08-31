// Covers the nav mesh surface codec: the settings round-trip as a delta, the
// bake itself rides a payload, a re-save overwrites that payload rather than
// adding another, and a payload from an incompatible build loses the mesh
// without losing the level. GPU-free; the components are never mounted.

import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/nav_codecs.dart';
import 'package:flutter_scene/src/navigation/nav_mesh_surface_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/navigation.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart' show ReadOnly;
import 'package:vector_math/vector_math.dart';

/// A flat floor spanning [size] x [size], centred on the origin.
NavGeometry floor(double size) {
  final half = size / 2;
  final builder = NavGeometryBuilder();
  builder.addMesh(
    positions: [
      -half, 0, -half, //
      half, 0, -half, //
      half, 0, half, //
      -half, 0, half,
    ],
    triangleIndices: [0, 2, 1, 0, 3, 2],
    area: NavArea.walkable,
  );
  return builder.build();
}

const _config = NavMeshConfig(
  cellSize: 0.3,
  cellHeight: 0.2,
  agentRadius: 0.4,
  agentHeight: 1.8,
);

void main() {
  final codec = NavMeshSurfaceCodec();

  ComponentSpec serialize(
    NavMeshSurfaceComponent component,
    SceneDocument document,
  ) {
    final spec = codec.serialize(component, SerializeContext(document));
    expect(spec, isNotNull);
    return spec!;
  }

  NavMeshSurfaceComponent realize(ComponentSpec spec, SceneDocument document) {
    final live = codec.realize(spec, RealizeContext(document));
    expect(live, isA<NavMeshSurfaceComponent>());
    return live! as NavMeshSurfaceComponent;
  }

  test('a component at its defaults serializes to nothing', () {
    final spec = serialize(NavMeshSurfaceComponent(), SceneDocument());
    expect(spec.type, 'navMeshSurface');
    expect(spec.properties, isEmpty);
  });

  test('the settings round-trip', () {
    final document = SceneDocument();
    final original = NavMeshSurfaceComponent(
      config: _config.copyWith(agentMaxClimb: 0.4, maxVertsPerPolygon: 4),
      includePattern: 'static_',
      includeInstances: false,
      blockedWaterDepth: 12,
    );
    final restored = realize(serialize(original, document), document);

    expect(restored.config.agentRadius, 0.4);
    expect(restored.config.agentHeight, 1.8);
    expect(restored.config.cellSize, 0.3);
    expect(restored.config.agentMaxClimb, 0.4);
    expect(restored.config.maxVertsPerPolygon, 4);
    expect(restored.includePattern, 'static_');
    expect(restored.includeInstances, isFalse);
    expect(restored.includeWaterVolumes, isTrue);
    expect(restored.blockedWaterDepth, 12);
    expect(restored.tiling, isNull);
  });

  test('a tiling round-trips, and a tile count under the floor means none', () {
    final document = SceneDocument();
    final original = NavMeshSurfaceComponent(
      tiling: const NavTileConfig(tileCells: 48, borderCells: 5),
    );
    final restored = realize(serialize(original, document), document);
    expect(restored.tiling?.tileCells, 48);
    expect(restored.tiling?.borderCells, 5);

    final off = realize(
      ComponentSpec(
        'navMeshSurface',
        properties: {'tileCells': const IntValue(0)},
      ),
      document,
    );
    expect(off.tiling, isNull);
  });

  test('a baked mesh travels in a payload and comes back whole', () {
    final document = SceneDocument();
    final original = NavMeshSurfaceComponent(config: _config)
      ..mesh = buildNavMesh(floor(20), _config);
    expect(original.mesh!.polygonCount, greaterThan(0));

    final spec = serialize(original, document);
    final token = spec.properties['baked'];
    expect(token, isA<StringValue>());
    final payload = document.payload(
      LocalId.parse((token! as StringValue).value),
    );
    expect(payload, isNotNull);
    expect(payload!.format, 'navMesh');
    expect(payload.bytes, isNotNull);

    final restored = realize(spec, document);
    expect(restored.mesh, isNotNull);
    expect(restored.mesh!.polygonCount, original.mesh!.polygonCount);
    expect(restored.mesh!.config.agentRadius, _config.agentRadius);
  });

  test('a tiled bake travels as the whole set, still linked', () {
    final document = SceneDocument();
    final original =
        NavMeshSurfaceComponent(
            config: _config,
            tiling: const NavTileConfig(tileCells: 24),
          )
          ..tileSet = bakeNavMeshTiled(
            floor(30),
            _config,
            tiling: const NavTileConfig(tileCells: 24),
          ).tiles;
    expect(original.tileSet!.tileCount, greaterThan(1));

    final restored = realize(serialize(original, document), document);
    expect(restored.mesh, isNull, reason: 'a tiled world has no single mesh');
    expect(restored.tileSet!.tileCount, original.tileSet!.tileCount);
    expect(restored.tiling?.tileCells, 24);

    final path = NavTileMeshQuery(
      restored.tileSet!,
    ).findPath(Vector3(-13, 0, -13), Vector3(13, 0, 13));
    expect(path.status, NavPathStatus.complete);
  });

  test('re-saving overwrites the bake payload rather than adding one', () {
    final document = SceneDocument();
    final component = NavMeshSurfaceComponent(config: _config)
      ..mesh = buildNavMesh(floor(20), _config);

    final first = serialize(component, document);
    expect(document.payloads, hasLength(1));
    final firstToken = (first.properties['baked']! as StringValue).value;

    final second = serialize(component, document);
    expect(
      document.payloads,
      hasLength(1),
      reason: 'a second save of the same bake must not mint a second payload',
    );
    expect((second.properties['baked']! as StringValue).value, firstToken);

    // A rebake replaces the mesh; the payload it occupies stays the same one.
    component.mesh = buildNavMesh(floor(24), _config);
    final third = serialize(component, document);
    expect(document.payloads, hasLength(1));
    expect((third.properties['baked']! as StringValue).value, firstToken);
    expect(realize(third, document).mesh!.polygonCount, greaterThan(0));
  });

  test('a loaded bake keeps its payload when the scene is saved again', () {
    final source = SceneDocument();
    final spec = serialize(
      NavMeshSurfaceComponent(config: _config)
        ..mesh = buildNavMesh(floor(20), _config),
      source,
    );
    final loaded = realize(spec, source);

    serialize(loaded, source);
    expect(
      source.payloads,
      hasLength(1),
      reason: 'saving what was just loaded must not duplicate the payload',
    );
  });

  test('an unreadable bake loses the mesh, not the settings', () {
    final document = SceneDocument();
    final payload = document.addPayload(
      PayloadSpec(
        document.newId(),
        encoding: PayloadEncoding.bytes,
        format: 'navMesh',
        bytes: Uint8List.fromList(List.filled(64, 7)),
      ),
    );
    final restored = realize(
      ComponentSpec(
        'navMeshSurface',
        properties: {
          'agentRadius': const DoubleValue(0.4),
          'baked': StringValue(payload.id.toToken()),
        },
      ),
      document,
    );

    expect(restored.mesh, isNull);
    expect(restored.tileSet, isNull);
    expect(restored.config.agentRadius, 0.4);
  });

  test('a missing or malformed token is simply no bake', () {
    final document = SceneDocument();
    for (final token in ['', 'not-an-id']) {
      final restored = realize(
        ComponentSpec(
          'navMeshSurface',
          properties: {'baked': StringValue(token)},
        ),
        document,
      );
      expect(restored.mesh, isNull);
    }
  });

  test('the baked property is not something a person edits', () {
    final baked = codec.propertySchema.firstWhere((p) => p.name == 'baked');
    expect(baked.constraint<ReadOnly>(), isNotNull);
    expect(baked.transient, isFalse, reason: 'it has to be saved');
  });
}
