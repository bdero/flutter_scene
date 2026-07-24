// Covers serializeScene's live-graph recovery: stable identity-tag ids,
// skins, parsed animations, lazy prefab placeholders, visibility, and the
// geometry topology field's codec round trip. GPU-free (component-less
// nodes; skins and animations realize without the GPU).

import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/stream/stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _skinnedNode = LocalId(7, 1);
const _joint = LocalId(7, 2);
const _skin = LocalId(7, 3);
const _ibm = LocalId(7, 4);
const _anim = LocalId(7, 5);
const _times = LocalId(7, 6);
const _keys = LocalId(7, 7);

Uint8List _floatBytes(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

// skinned (root, skin over [joint]) -> joint, plus a 'move' animation
// translating joint to y=1 over one second.
SceneDocument _skinned() {
  final doc = SceneDocument();
  doc.addNode(
    NodeSpec(
      id: _skinnedNode,
      name: 'skinned',
      children: [_joint],
      skin: _skin,
    ),
    root: true,
  );
  doc.addNode(NodeSpec(id: _joint, name: 'joint'));
  final ibm = Matrix4.identity()..setTranslation(Vector3(0, 2, 0));
  doc.addPayload(
    PayloadSpec(
      _ibm,
      encoding: PayloadEncoding.matrices,
      bytes: _floatBytes(ibm.storage.toList()),
    ),
  );
  doc.addSkin(SkinSpec(_skin, joints: [_joint], inverseBindMatrices: _ibm));
  doc.addPayload(
    PayloadSpec(
      _times,
      encoding: PayloadEncoding.floats,
      bytes: _floatBytes([0, 1]),
    ),
  );
  doc.addPayload(
    PayloadSpec(
      _keys,
      encoding: PayloadEncoding.floats,
      bytes: _floatBytes([0, 0, 0, 0, 1, 0]),
    ),
  );
  doc.addAnimation(
    AnimationSpec(
      _anim,
      name: 'move',
      channels: [
        AnimationChannelSpec(
          target: _joint,
          targetName: 'joint',
          property: AnimationProperty.translation,
          timeline: _times,
          keyframes: _keys,
        ),
      ],
    ),
  );
  return doc;
}

void main() {
  test('serializeScene keeps identity-tag ids stable', () {
    final doc = SceneDocument();
    const a = LocalId(2, 1);
    const b = LocalId(2, 2);
    doc.addNode(NodeSpec(id: a, name: 'a', children: [b]), root: true);
    doc.addNode(NodeSpec(id: b, name: 'b'));

    final restored = serializeScene(realizeScene(doc));
    expect(restored.nodes.keys.toSet(), {a, b});
    expect(restored.node(a)!.children, [b]);
  });

  test('skins and animations round-trip through the live graph', () {
    final restored = serializeScene(realizeScene(_skinned()));

    // The skinned node still references a skin over the same joint id.
    final skinned = restored.node(_skinnedNode)!;
    final skin = restored.skins[skinned.skin]!;
    expect(skin.joints, [_joint]);
    expect(
      restored.payload(skin.inverseBindMatrices)!.bytes,
      _skinned().payload(_ibm)!.bytes,
    );

    // The animation kept its name, target, and keyframe bytes.
    final animation = restored.animations.values.single;
    expect(animation.name, 'move');
    final channel = animation.channels.single;
    expect(channel.target, _joint);
    expect(channel.targetName, 'joint');
    expect(channel.property, AnimationProperty.translation);
    expect(
      restored.payload(channel.timeline)!.bytes,
      _skinned().payload(_times)!.bytes,
    );
    expect(
      restored.payload(channel.keyframes)!.bytes,
      _skinned().payload(_keys)!.bytes,
    );

    // And the restored document realizes back to a working binding.
    final again = realizeScene(restored);
    final joint = again.getChildByName('joint')!;
    expect(joint.isJoint, isTrue);
    expect(again.getChildByName('skinned')!.skin!.joints.single, same(joint));
    expect(again.findAnimationByName('move'), isNotNull);
  });

  test('a lazy placeholder serializes as its instance reference', () {
    final doc = SceneDocument();
    doc.addNode(
      NodeSpec(
        id: const LocalId(3, 1),
        name: 'spot',
        instance: PrefabInstanceSpec(
          source: const AssetRef('assets/tree'),
          load: LoadPolicy.lazy,
        ),
      ),
      root: true,
    );

    final realized = realizeScene(doc);
    final placeholder = realized.children.single;
    expect(isLazySubtree(placeholder), isTrue);

    final restored = serializeScene(realized);
    final spec = restored.node(const LocalId(3, 1))!;
    expect(spec.instance, isNotNull);
    expect(spec.instance!.load, LoadPolicy.lazy);
    expect(spec.instance!.source.key, 'assets/tree');
    // The placeholder's (unstreamed) children list stays empty.
    expect(spec.children, isEmpty);
  });

  test('visibility round-trips and reload patches it', () {
    final doc = SceneDocument();
    doc.addNode(
      NodeSpec(id: const LocalId(4, 1), name: 'hidden', visible: false),
      root: true,
    );
    final realized = realizeScene(doc);
    expect(realized.children.single.visible, isFalse);

    final restored = serializeScene(realized);
    expect(restored.node(const LocalId(4, 1))!.visible, isFalse);

    // The JSON form carries it.
    final decoded = readFscene(writeFscene(restored));
    expect(decoded.node(const LocalId(4, 1))!.visible, isFalse);
  });

  test('geometry topology round-trips through JSON', () {
    final doc = SceneDocument();
    final payload = doc.addPayload(
      PayloadSpec(
        doc.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned',
        bytes: Uint8List(48),
      ),
    );
    doc.addResource(
      GeometryResource(
        doc.newId(),
        vertices: payload.id,
        topology: 'lineStrip',
      ),
    );

    final restored = readFscene(writeFscene(doc));
    final geometry = restored.resources.values
        .whereType<GeometryResource>()
        .single;
    expect(geometry.topology, 'lineStrip');
  });

  test('an environment resource round-trips its look', () {
    final doc = SceneDocument();
    doc.addResource(
      EnvironmentResource(
        doc.newId(),
        name: 'dusk',
        environment: const EmptyEnvironment(),
        environmentIntensity: 1.5,
        exposure: 0.5,
        toneMapping: 'aces',
        radianceCubeSize: 1024,
        skybox: SkyboxSpec(PhysicalSkySpec(turbidity: 6.0), intensity: 2.0),
        skyEnvironment: SkyEnvironmentSpec(
          GradientSkySpec(),
          castShadows: true,
        ),
      ),
    );

    final restored = readFscene(writeFscene(doc));
    final env = restored.resources.values
        .whereType<EnvironmentResource>()
        .single;
    expect(env.name, 'dusk');
    expect(env.environment, isA<EmptyEnvironment>());
    expect(env.environmentIntensity, 1.5);
    expect(env.exposure, 0.5);
    expect(env.toneMapping, 'aces');
    expect(env.radianceCubeSize, 1024);
    expect((env.skybox!.source as PhysicalSkySpec).turbidity, 6.0);
    expect(env.skybox!.intensity, 2.0);
    expect(env.skyEnvironment!.castShadows, isTrue);
  });
}
