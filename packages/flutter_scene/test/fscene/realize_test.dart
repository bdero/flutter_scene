// Covers .fscene realization: building a live Node graph from a document and
// serializing one back. These exercise the GPU-free parts (node graph,
// transforms, layers, light/camera components, handedness, and the component
// codec registry); mesh/resource realization is a separate, GPU-bound step.

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
SceneDocument _sampleScene({Handedness handedness = Handedness.right}) {
  final doc = SceneDocument();
  doc.stage.handedness = handedness;

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
      expect(root.excludeFromWindingParity, isTrue);
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

    test('a right-handed stage flips the synthesized root', () {
      expect(
        realizeScene(
          _sampleScene(handedness: Handedness.right),
        ).localTransform.determinant(),
        lessThan(0),
      );
      expect(
        realizeScene(
          _sampleScene(handedness: Handedness.left),
        ).localTransform.determinant(),
        greaterThan(0),
      );
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
  });

  group('serializeScene', () {
    test('round-trips structure and components through a live graph', () {
      final doc = _sampleScene();
      final back = serializeScene(realizeScene(doc));

      expect(back.stage.handedness, doc.stage.handedness);
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
