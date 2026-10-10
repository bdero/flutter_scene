// Covers .fscene realization: building a live Node graph from a document and
// serializing one back. These exercise the GPU-free parts (node graph,
// transforms, layers, light/camera components, and the component
// codec registry); mesh/resource realization is a separate, GPU-bound step.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/animation.dart'
    show RotationTimelineResolver, TranslationTimelineResolver;
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A tagged component plus its codec, for the registry-extensibility test.
class _TagComponent extends Component {
  _TagComponent(this.tag);
  final String tag;
}

class _TagCodec extends ComponentCodec {
  @override
  String get type => 'tag';

  @override
  Component realize(ComponentSpec spec, RealizeContext context) =>
      _TagComponent(readString(spec.properties, 'tag', ''));

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) =>
      component is _TagComponent
      ? ComponentSpec('tag', properties: {'tag': StringValue(component.tag)})
      : null;
}

// Builds: world (root) -> { sun (directionalLight), eye (camera), pivot }.
SceneDocument _sampleScene() {
  final doc = SceneDocument();

  final world = doc.createNode(name: 'world', root: true);
  final sun = doc.createNode(
    name: 'sun',
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(5.0),
          'castsShadow': const BoolValue(true),
        },
      ),
    ],
  );
  final eye = doc.createNode(
    name: 'eye',
    components: [
      ComponentSpec(
        'camera',
        properties: {'fovRadiansY': const DoubleValue(1.2)},
      ),
    ],
  );
  final pivot = doc.createNode(name: 'pivot', layers: 4);
  world.children.addAll([sun.id, eye.id, pivot.id]);
  return doc;
}

void main() {
  group('realizeScene', () {
    test('builds the node graph with components and layers', () {
      final root = realizeScene(_sampleScene());
      expect(root.name, 'root');
      expect(root.localTransform, Matrix4.identity());
      expect(root.children, hasLength(1));

      final world = root.children.single;
      expect(world.name, 'world');
      expect(world.children, hasLength(3));

      final sun = world.getChildByName('sun')!;
      final light = sun.getComponent<DirectionalLightComponent>();
      expect(light, isNotNull);
      expect(light!.light.intensity, 5.0);
      expect(light.light.castsShadow, isTrue);

      final eye = world.getChildByName('eye')!;
      expect(eye.getComponent<CameraComponent>(), isNotNull);

      final pivot = world.getChildByName('pivot')!;
      expect(pivot.layers, 4);
      expect(pivot.getComponents<Component>(), isEmpty);
    });

    test('skips a component with no registered codec', () {
      final doc = SceneDocument();
      doc.createNode(
        name: 'mystery',
        root: true,
        components: [ComponentSpec('notRegistered')],
      );
      final root = realizeScene(doc);
      expect(root.children.single.getComponents<Component>(), isEmpty);
    });

    test(
      'migrated v5 document conjugates legacy skin IBMs and reflects animations',
      () {
        final source = SceneDocument();
        final ibmId = source.newId();
        final timesId = source.newId();
        final transId = source.newId();
        final rotId = source.newId();
        source.addPayload(
          PayloadSpec(ibmId, encoding: PayloadEncoding.matrices),
        );
        source.addPayload(
          PayloadSpec(timesId, encoding: PayloadEncoding.floats),
        );
        source.addPayload(
          PayloadSpec(transId, encoding: PayloadEncoding.floats),
        );
        source.addPayload(PayloadSpec(rotId, encoding: PayloadEncoding.floats));

        final joint = source.createNode(name: 'jointNode');
        final skin = SkinSpec(
          source.newId(),
          joints: [joint.id],
          inverseBindMatrices: ibmId,
        );
        source.addSkin(skin);
        final meshNode = source.addNode(
          NodeSpec(
            id: source.newId(),
            name: 'meshNode',
            skin: skin.id,
            children: [joint.id],
          ),
          root: true,
        );
        final anim = AnimationSpec(
          source.newId(),
          name: 'move',
          channels: [
            AnimationChannelSpec(
              target: joint.id,
              property: AnimationProperty.translation,
              timeline: timesId,
              keyframes: transId,
            ),
            AnimationChannelSpec(
              target: joint.id,
              property: AnimationProperty.rotation,
              timeline: timesId,
              keyframes: rotId,
            ),
          ],
        );
        source.addAnimation(anim);

        final json = jsonDecode(writeFscene(source)) as Map<String, dynamic>;
        json['fscene'] = 5;
        final doc = readFscene(jsonEncode(json));

        final ibmFloats = Float32List.fromList([
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          1,
          2,
          3,
          1,
        ]);
        final timesFloats = Float32List.fromList([0.0]);
        final transFloats = Float32List.fromList([4.0, 5.0, 6.0]);
        final rotFloats = Float32List.fromList([0.1, 0.2, 0.3, 0.9]);
        doc.payload(ibmId)!.bytes = Uint8List.sublistView(ibmFloats);
        doc.payload(timesId)!.bytes = Uint8List.sublistView(timesFloats);
        doc.payload(transId)!.bytes = Uint8List.sublistView(transFloats);
        doc.payload(rotId)!.bytes = Uint8List.sublistView(rotFloats);

        final root = realizeScene(doc);
        final realizedMesh = root.getChildByName(meshNode.name)!;
        final ibm = realizedMesh.skin!.inverseBindMatrices.single;
        expect(ibm.getTranslation().x, closeTo(1.0, 1e-6));
        expect(ibm.getTranslation().y, closeTo(2.0, 1e-6));
        expect(ibm.getTranslation().z, closeTo(-3.0, 1e-6));

        final realizedAnim = root.findAnimationByName('move')!;
        final transValue =
            (realizedAnim.channels[0].resolver as TranslationTimelineResolver)
                .values
                .single;
        final rotValue =
            (realizedAnim.channels[1].resolver as RotationTimelineResolver)
                .values
                .single;
        expect(transValue.x, closeTo(4.0, 1e-6));
        expect(transValue.y, closeTo(5.0, 1e-6));
        expect(transValue.z, closeTo(-6.0, 1e-6));
        expect(rotValue.x, closeTo(-0.1, 1e-6));
        expect(rotValue.y, closeTo(-0.2, 1e-6));
        expect(rotValue.z, closeTo(0.3, 1e-6));
        expect(rotValue.w, closeTo(0.9, 1e-6));
      },
    );
  });

  group('serializeScene', () {
    test('round-trips structure and components through a live graph', () {
      final doc = _sampleScene();
      final back = serializeScene(realizeScene(doc));

      expect(back.rootNodes, hasLength(1));

      final world = back.rootNodes.single;
      final childNames = world.children
          .map((id) => back.node(id)!.name)
          .toSet();
      expect(childNames, {'sun', 'eye', 'pivot'});

      final sunSpec = world.children
          .map((id) => back.node(id)!)
          .firstWhere((n) => n.name == 'sun');
      final lightSpec = sunSpec.components.single;
      expect(lightSpec.type, 'directionalLight');
      expect((lightSpec.properties['intensity'] as DoubleValue).value, 5.0);
    });

    test('round-trips a TRS transform without matrix decomposition', () {
      // A mirrored-axis scale must survive as authored; recovering it from
      // the composed matrix would move the negative sign to X and break
      // animation blending on mirrored bones.
      final doc = SceneDocument();
      doc.createNode(
        name: 'mirrored',
        root: true,
        transform: TrsTransform(
          translation: Vector3(1, 2, 3),
          scale: Vector3(1, -1, 1),
        ),
      );

      final root = realizeScene(doc);
      final node = root.children.single;
      final trs = node.localTransformTrs!;
      expect(trs.scale.y, -1);
      expect(trs.translation, Vector3(1, 2, 3));

      final back = serializeScene(root);
      final spec = back.rootNodes.single.transform as TrsTransform;
      expect(spec.scale.y, -1);
      expect(spec.translation, Vector3(1, 2, 3));
    });
  });

  group('component registry', () {
    test('a custom codec realizes and serializes a custom component', () {
      final registry = defaultComponentRegistry()..register(_TagCodec());

      final doc = SceneDocument();
      doc.createNode(
        name: 'tagged',
        root: true,
        components: [
          ComponentSpec('tag', properties: {'tag': const StringValue('hello')}),
        ],
      );

      final root = realizeScene(doc, registry: registry);
      final tag = root.children.single.getComponent<_TagComponent>();
      expect(tag, isNotNull);
      expect(tag!.tag, 'hello');

      final back = serializeScene(root, registry: registry);
      final spec = back.rootNodes.single.components.single;
      expect(spec.type, 'tag');
      expect((spec.properties['tag'] as StringValue).value, 'hello');
    });
  });
}
