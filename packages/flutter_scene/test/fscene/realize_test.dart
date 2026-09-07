// Covers .fscene realization: building a live Node graph from a document and
// serializing one back. These exercise the GPU-free parts (node graph,
// transforms, layers, light/camera components, and the component
// codec registry); mesh/resource realization is a separate, GPU-bound step.

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/builtin_codecs.dart';
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

  group('camera lenses', () {
    SceneDocument cameraDoc(Map<String, PropertyValue> properties) {
      final doc = SceneDocument();
      doc.createNode(
        name: 'eye',
        root: true,
        components: [ComponentSpec('camera', properties: properties)],
      );
      return doc;
    }

    CameraComponent cameraIn(SceneDocument doc) =>
        realizeScene(doc).children.single.getComponent<CameraComponent>()!;

    ComponentSpec serializedCamera(Node root) =>
        serializeScene(root).rootNodes.single.components.single;

    test('a document with no projection key realizes as perspective', () {
      // Every camera authored before orthographic existed looks like this.
      final camera = cameraIn(
        cameraDoc({'fovRadiansY': const DoubleValue(1.2)}),
      );
      final projection = camera.projection as PerspectiveProjection;
      expect(projection.fovRadiansY, 1.2);
    });

    test('an orthographic document realizes an orthographic lens', () {
      final camera = cameraIn(
        cameraDoc({
          'projection': const StringValue('orthographic'),
          'height': const DoubleValue(20),
          'near': const DoubleValue(0.5),
          'far': const DoubleValue(500),
        }),
      );
      final projection = camera.projection as OrthographicProjection;
      expect(projection.height, 20);
      expect(projection.near, 0.5);
      expect(projection.far, 500);
    });

    test('an orthographic camera survives a round trip', () {
      // It used to be dropped outright: claims() only accepted a perspective
      // projection, so serialize() returned null and the camera vanished.
      final doc = cameraDoc({
        'projection': const StringValue('orthographic'),
        'height': const DoubleValue(8),
      });
      final spec = serializedCamera(realizeScene(doc));

      expect(spec.type, 'camera');
      expect(
        (spec.properties['projection'] as StringValue).value,
        'orthographic',
      );
      expect((spec.properties['height'] as DoubleValue).value, 8);

      final projection = cameraIn(cameraDoc(spec.properties)).projection;
      expect((projection as OrthographicProjection).height, 8);
    });

    test('each lens serializes only its own size key', () {
      final ortho = serializedCamera(
        realizeScene(
          cameraDoc({'projection': const StringValue('orthographic')}),
        ),
      );
      expect(ortho.properties, isNot(contains('fovRadiansY')));

      final perspective = serializedCamera(
        realizeScene(cameraDoc({'fovRadiansY': const DoubleValue(1.2)})),
      );
      expect(perspective.properties, isNot(contains('height')));
    });

    test('swapping the lens carries the clip range across', () {
      // near/far belong to both lenses, so toggling must not silently reset
      // them to the incoming lens's defaults.
      final camera = cameraIn(
        cameraDoc({
          'near': const DoubleValue(0.25),
          'far': const DoubleValue(750),
        }),
      );

      final field = CameraCodec().fields.firstWhere(
        (f) => f.def.name == 'projection',
      );
      field.write!(
        camera,
        const StringValue('orthographic'),
        RealizeContext(SceneDocument()),
      );

      final projection = camera.projection as OrthographicProjection;
      expect(projection.near, 0.25);
      expect(projection.far, 750);
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
