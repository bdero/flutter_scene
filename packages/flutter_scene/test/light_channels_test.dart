// Covers light channel masks: the defaults are all-on, per-object light
// assignment drops lights whose channels an item does not share, a node's
// mask reaches its render items, and a directional light's shadow-caster
// mask is independent of the mask that decides what it lights.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/light_culling.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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

RenderItem _item({int channelMask = 0xFF, double x = 0.0}) =>
    RenderItem(geometry: _StubGeometry(), material: _StubMaterial())
      ..lightChannelMask = channelMask
      ..worldBounds = Aabb3.minMax(
        Vector3(x - 0.5, -0.5, -0.5),
        Vector3(x + 0.5, 0.5, 0.5),
      );

RenderItem _unboundedItem({int channelMask = 0xFF}) =>
    RenderItem(geometry: _StubGeometry(), material: _StubMaterial())
      ..lightChannelMask = channelMask;

List<int> _sliceOf(RenderItem item, LightCullResult result) => result.indices
    .sublist(item.lightListOffset, item.lightListOffset + item.lightListCount);

void main() {
  group('defaults', () {
    test('every light and node takes every channel', () {
      expect(DirectionalLight().channelMask, 0xFF);
      expect(DirectionalLight().shadowCasterChannelMask, 0xFF);
      expect(PointLight().channelMask, 0xFF);
      expect(SpotLight().channelMask, 0xFF);
      expect(RectAreaLight().channelMask, 0xFF);
      expect(Node().lightChannelMask, 0xFF);
      expect(
        RenderItem(
          geometry: _StubGeometry(),
          material: _StubMaterial(),
        ).lightChannelMask,
        0xFF,
      );
    });
  });

  group('assignLightsToItems channel filtering', () {
    test('an infinite light skips items outside its channels', () {
      final lit = _item(channelMask: 0x01);
      final unlit = _item(channelMask: 0x02, x: 100);
      final items = [lit, unlit];
      final result = assignLightsToItems(
        items: items,
        bvh: Bvh.build(items),
        lights: const [CullableLight(3, null, channelMask: 0x01)],
        maxPerItem: 16,
      );
      expect(_sliceOf(lit, result), [3]);
      expect(unlit.lightListCount, 0);
    });

    test('items sharing a mask share one infinite slice', () {
      final a = _item(channelMask: 0x03);
      final b = _item(channelMask: 0x03, x: 50);
      final items = [a, b];
      final result = assignLightsToItems(
        items: items,
        bvh: Bvh.build(items),
        lights: const [
          CullableLight(0, null, channelMask: 0x01),
          CullableLight(1, null, channelMask: 0x04),
          CullableLight(2, null, channelMask: 0x02),
        ],
        maxPerItem: 16,
      );
      expect(a.lightListOffset, b.lightListOffset);
      expect(result.indices, [0, 2]);
    });

    test('a zero mask on either side is never lit', () {
      final darkItem = _item(channelMask: 0x00);
      final normalItem = _item(channelMask: 0xFF, x: 4);
      final items = [darkItem, normalItem];
      final result = assignLightsToItems(
        items: items,
        bvh: Bvh.build(items),
        lights: const [
          CullableLight(0, null),
          CullableLight(1, null, channelMask: 0x00),
        ],
        maxPerItem: 16,
      );
      expect(darkItem.lightListCount, 0);
      expect(_sliceOf(normalItem, result), [0]);
    });

    test('a ranged light is filtered by channels as well as reach', () {
      final inChannel = _item(channelMask: 0x01);
      final outOfChannel = _item(channelMask: 0x02, x: 1);
      final items = [inChannel, outOfChannel];
      final ranged = CullableLight(
        5,
        lightInfluenceBounds(Vector3.zero(), 10.0),
        worldPosition: Vector3.zero(),
        channelMask: 0x01,
      );
      final result = assignLightsToItems(
        items: items,
        bvh: Bvh.build(items),
        lights: [ranged],
        maxPerItem: 16,
      );
      expect(_sliceOf(inChannel, result), [5]);
      expect(outOfChannel.lightListCount, 0);
    });

    test('an unbounded item is still filtered by channels', () {
      final bounded = _item(channelMask: 0x01);
      final unbounded = _unboundedItem(channelMask: 0x02);
      final items = [bounded, unbounded];
      final result = assignLightsToItems(
        items: items,
        bvh: Bvh.build([bounded]),
        lights: [
          CullableLight(
            0,
            lightInfluenceBounds(Vector3(500, 0, 0), 1.0),
            worldPosition: Vector3(500, 0, 0),
            channelMask: 0x01,
          ),
          const CullableLight(1, null, channelMask: 0x02),
        ],
        maxPerItem: 16,
      );
      // The ranged light is out of the unbounded item's channels, so the
      // uncullable item receives only the infinite one.
      expect(_sliceOf(unbounded, result), [1]);
      expect(bounded.lightListCount, 0);
    });

    test('default masks assign exactly as an unmasked scene does', () {
      List<List<int>> assign(List<CullableLight> lights) {
        final items = [_item(), _item(x: 2), _unboundedItem()];
        final result = assignLightsToItems(
          items: items,
          bvh: Bvh.build([items[0], items[1]]),
          lights: lights,
          maxPerItem: 16,
        );
        return [for (final item in items) _sliceOf(item, result)];
      }

      final control = assign([
        CullableLight(
          0,
          lightInfluenceBounds(Vector3(1, 0, 0), 3.0),
          worldPosition: Vector3(1, 0, 0),
        ),
        const CullableLight(1, null),
      ]);
      final masked = assign([
        CullableLight(
          0,
          lightInfluenceBounds(Vector3(1, 0, 0), 3.0),
          worldPosition: Vector3(1, 0, 0),
          channelMask: 0xFF,
        ),
        const CullableLight(1, null, channelMask: 0xFF),
      ]);
      expect(masked, control);
    });
  });

  group('Node.lightChannelMask', () {
    test('reaches mesh and instanced render items', () {
      final renderScene = RenderScene();
      final root = Node()..debugMountInto(renderScene);
      final meshNode = Node(mesh: Mesh(_StubGeometry(), _StubMaterial()))
        ..lightChannelMask = 0x05;
      final instancedNode = Node()..lightChannelMask = 0x0A;
      instancedNode.addComponent(
        InstancedMeshComponent(
          InstancedMesh(geometry: _StubGeometry(), material: _StubMaterial())
            ..addInstance(Matrix4.identity()),
        ),
      );
      root
        ..add(meshNode)
        ..add(instancedNode);

      root.scenePrePass(0);

      final masks = renderScene.items
          .map((item) => item.lightChannelMask)
          .toList();
      expect(masks, containsAll(<int>[0x05, 0x0A]));
    });
  });

  group('shadow-caster channels', () {
    RenderItem caster({int channelMask = 0xFF}) =>
        RenderItem(geometry: _StubGeometry(), material: _StubMaterial())
          ..visible = true
          ..lightChannelMask = channelMask;

    test('the default caster mask accepts every visible caster', () {
      expect(
        shadowCasterAccepted(caster(), ShadowCasterFilter.all, 0xFF),
        isTrue,
      );
    });

    test('a caster outside the light caster channels is dropped', () {
      expect(
        shadowCasterAccepted(
          caster(channelMask: 0x02),
          ShadowCasterFilter.all,
          0x01,
        ),
        isFalse,
      );
    });

    test('lighting and caster masks are independent', () {
      // Lit by the light but kept out of its shadow map.
      final litNotCasting = caster(channelMask: 0x01);
      final light = DirectionalLight()
        ..channelMask = 0x01
        ..shadowCasterChannelMask = 0x02;
      expect(light.channelMask & litNotCasting.lightChannelMask, isNonZero);
      expect(
        shadowCasterAccepted(
          litNotCasting,
          ShadowCasterFilter.all,
          light.shadowCasterChannelMask,
        ),
        isFalse,
      );

      // Casts into the shadow map without receiving the light.
      final castingNotLit = caster(channelMask: 0x02);
      expect(light.channelMask & castingNotLit.lightChannelMask, 0);
      expect(
        shadowCasterAccepted(
          castingNotLit,
          ShadowCasterFilter.all,
          light.shadowCasterChannelMask,
        ),
        isTrue,
      );
    });

    test('channels do not override the existing caster rules', () {
      expect(
        shadowCasterAccepted(
          caster()..shadowCastingMode = ShadowCastingMode.off,
          ShadowCasterFilter.all,
          0xFF,
        ),
        isFalse,
      );
      expect(
        shadowCasterAccepted(
          caster()..visible = false,
          ShadowCasterFilter.all,
          0xFF,
        ),
        isFalse,
      );
      expect(
        shadowCasterAccepted(caster(), ShadowCasterFilter.staticOnly, 0xFF),
        isFalse,
      );
    });
  });
}
