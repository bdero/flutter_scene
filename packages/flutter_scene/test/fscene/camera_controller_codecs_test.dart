// Covers the camera-controller codecs beyond what the generic delta probe in
// component_schema_test.dart can reach: the nested objects (lens, head bob,
// edge scroll, map bounds, dolly path), the node references, the
// infinity-as-zero distance convention, and the pose-through-the-constructor
// contract.
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/dolly_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/first_person_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/follow_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/orbit_camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/rts_camera_controller.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final registry = defaultComponentRegistry();
  final doc = SceneDocument();

  /// Realizes a component of [type] from [properties].
  T realize<T extends Component>(
    String type, [
    Map<String, PropertyValue> properties = const {},
  ]) =>
      registry
              .codecFor(type)!
              .realize(
                ComponentSpec(type, properties: properties),
                RealizeContext(doc),
              )!
          as T;

  /// The property bag a live component serializes to.
  Map<String, PropertyValue> serialize(String type, Component component) =>
      registry
          .codecFor(type)!
          .serialize(component, SerializeContext(doc))!
          .properties;

  group('distance limits', () {
    test('an unlimited maxDistance is spelled 0 in the document', () {
      // double.infinity has no JSON form, so the codec uses the same
      // "0 means no limit" convention a point light's range uses.
      final unlimited = realize<OrbitCameraController>('orbitCameraController');
      expect(unlimited.maxDistance, double.infinity);
      expect(
        serialize('orbitCameraController', unlimited),
        isNot(contains('maxDistance')),
        reason: 'the default is unlimited, so it is not a delta',
      );

      final zero = realize<OrbitCameraController>('orbitCameraController', {
        'maxDistance': const DoubleValue(0),
      });
      expect(zero.maxDistance, double.infinity);
    });

    test('a finite maxDistance survives a round trip', () {
      final limited = realize<OrbitCameraController>('orbitCameraController', {
        'maxDistance': const DoubleValue(12),
      });
      expect(limited.maxDistance, 12);
      final back = serialize('orbitCameraController', limited);
      expect((back['maxDistance']! as DoubleValue).value, 12);
    });
  });

  group('pose', () {
    test('an authored pose is restored through the constructor', () {
      // Pose is read-only on the controller (input owns it), so it round-trips
      // via create rather than a property write.
      final orbit = realize<OrbitCameraController>('orbitCameraController', {
        'azimuth': const DoubleValue(1.2),
        'polar': const DoubleValue(0.5),
        'distance': const DoubleValue(14),
      });
      expect(orbit.azimuth, 1.2);
      expect(orbit.polar, 0.5);
      expect(orbit.distance, 14);

      final back = serialize('orbitCameraController', orbit);
      expect((back['azimuth']! as DoubleValue).value, 1.2);
      expect((back['polar']! as DoubleValue).value, 0.5);
      expect((back['distance']! as DoubleValue).value, 14);
    });

    test('a pose outside its limits is clamped on the way in', () {
      final orbit = realize<OrbitCameraController>('orbitCameraController', {
        'minPolar': const DoubleValue(-0.5),
        'maxPolar': const DoubleValue(0.5),
        'polar': const DoubleValue(2.0),
      });
      expect(orbit.polar, 0.5);
    });
  });

  group('the shot lens', () {
    test('a perspective lens round-trips', () {
      final controller = realize<FirstPersonCameraController>(
        'firstPersonCameraController',
        {
          'lens': MapValue({
            'projection': const StringValue('perspective'),
            'fovRadiansY': const DoubleValue(0.9),
            'near': const DoubleValue(0.2),
            'far': const DoubleValue(400),
          }),
        },
      );
      // The lens is applied after create, through the field's write.
      expect(controller.lens, isA<PerspectiveProjection>());

      final back = serialize('firstPersonCameraController', controller);
      final lens = back['lens']! as MapValue;
      expect((lens.values['projection']! as StringValue).value, 'perspective');
      expect((lens.values['fovRadiansY']! as DoubleValue).value, 0.9);
      expect(lens.values, isNot(contains('height')));
    });

    test('an orthographic lens round-trips', () {
      final controller = realize<DollyCameraController>(
        'dollyCameraController',
        {
          'path': MapValue({
            'waypoints': ListValue([
              Vec3Value(Vector3.zero()),
              Vec3Value(Vector3(0, 0, 10)),
            ]),
          }),
          'lens': MapValue({
            'projection': const StringValue('orthographic'),
            'height': const DoubleValue(18),
          }),
        },
      );
      expect((controller.lens! as OrthographicProjection).height, 18);

      final lens = serialize('dollyCameraController', controller)['lens']!;
      expect(
        ((lens as MapValue).values['projection']! as StringValue).value,
        'orthographic',
      );
      expect(lens.values, isNot(contains('fovRadiansY')));
    });

    test('no lens stays absent rather than becoming a default one', () {
      final controller = realize<FirstPersonCameraController>(
        'firstPersonCameraController',
      );
      expect(controller.lens, isNull);
      expect(
        serialize('firstPersonCameraController', controller),
        isNot(contains('lens')),
      );
    });
  });

  group('head bob', () {
    test('round-trips its four knobs', () {
      final controller = realize<FirstPersonCameraController>(
        'firstPersonCameraController',
        {
          'headBob': MapValue({
            'amplitude': const DoubleValue(0.09),
            'frequency': const DoubleValue(6),
            'lateralRatio': const DoubleValue(0.4),
            'rollAmount': const DoubleValue(0.03),
          }),
        },
      );
      expect(controller.headBob!.amplitude, 0.09);
      expect(controller.headBob!.frequency, 6);

      final bob =
          serialize('firstPersonCameraController', controller)['headBob']!
              as MapValue;
      expect((bob.values['lateralRatio']! as DoubleValue).value, 0.4);
      expect((bob.values['rollAmount']! as DoubleValue).value, 0.03);
    });

    test('absent head bob stays absent', () {
      final controller = realize<FirstPersonCameraController>(
        'firstPersonCameraController',
      );
      expect(controller.headBob, isNull);
      expect(
        serialize('firstPersonCameraController', controller),
        isNot(contains('headBob')),
      );
    });
  });

  group('rts optional configuration', () {
    test('edge scroll and map bounds round-trip', () {
      final controller = realize<RtsCameraController>('rtsCameraController', {
        'edgeScroll': MapValue({
          'margin': const DoubleValue(40),
          'speed': const DoubleValue(2),
        }),
        'bounds': MapValue({
          'min': Vec3Value(Vector3(-50, 0, -50)),
          'max': Vec3Value(Vector3(50, 0, 50)),
        }),
      });
      expect(controller.edgeScroll!.margin, 40);
      expect(controller.edgeScroll!.speed, 2);
      expect(controller.bounds!.min.x, -50);
      expect(controller.bounds!.max.z, 50);

      final back = serialize('rtsCameraController', controller);
      expect(
        ((back['edgeScroll']! as MapValue).values['margin']! as DoubleValue)
            .value,
        40,
      );
      expect(
        ((back['bounds']! as MapValue).values['max']! as Vec3Value).value.x,
        50,
      );
    });

    test('both stay absent when unset', () {
      final controller = realize<RtsCameraController>('rtsCameraController');
      expect(controller.edgeScroll, isNull);
      expect(controller.bounds, isNull);
      final back = serialize('rtsCameraController', controller);
      expect(back, isNot(contains('edgeScroll')));
      expect(back, isNot(contains('bounds')));
    });
  });

  group('the dolly path', () {
    test('waypoints and closedness round-trip', () {
      final controller = realize<DollyCameraController>(
        'dollyCameraController',
        {
          'path': MapValue({
            'waypoints': ListValue([
              Vec3Value(Vector3(0, 0, 0)),
              Vec3Value(Vector3(5, 1, 0)),
              Vec3Value(Vector3(10, 0, 5)),
            ]),
            'closed': const BoolValue(true),
          }),
        },
      );
      expect(controller.path.waypoints, hasLength(3));
      expect(controller.path.closed, isTrue);

      final path =
          serialize('dollyCameraController', controller)['path']! as MapValue;
      final points = (path.values['waypoints']! as ListValue).values;
      expect(points, hasLength(3));
      expect((points[1] as Vec3Value).value.x, 5);
      expect((path.values['closed']! as BoolValue).value, isTrue);
    });

    test('a path with too few waypoints falls back rather than throwing', () {
      // CameraPath asserts on fewer than two waypoints, so a truncated or
      // hand-edited document must not reach the constructor.
      final controller = realize<DollyCameraController>(
        'dollyCameraController',
        {
          'path': MapValue({
            'waypoints': ListValue([Vec3Value(Vector3.zero())]),
          }),
        },
      );
      expect(controller.path.waypoints, hasLength(2));
    });
  });

  group('node references', () {
    test('a follow target resolves and round-trips', () {
      final document = SceneDocument();
      final targetId = document.newId();
      document.addNode(NodeSpec(id: targetId, name: 'hero'), root: true);
      document.addNode(
        NodeSpec(
          id: document.newId(),
          name: 'rig',
          components: [
            ComponentSpec(
              'followCameraController',
              properties: {'followTarget': NodeRefValue(targetId)},
            ),
          ],
        ),
        root: true,
      );

      final root = realizeScene(document);
      final rig = root.getChildByName('rig')!;
      final controller = rig.getComponent<FollowCameraController>()!;
      expect(controller.followTarget, isNotNull);
      expect(controller.followTarget!.name, 'hero');

      final back = serializeScene(root);
      final rigSpec = back.rootNodes.firstWhere((n) => n.name == 'rig');
      final ref = rigSpec.components.single.properties['followTarget'];
      expect(ref, isA<NodeRefValue>());
    });

    test('an unresolvable follow target leaves the controller unset', () {
      final controller = realize<FollowCameraController>(
        'followCameraController',
        {'followTarget': NodeRefValue(doc.newId())},
      );
      expect(controller.followTarget, isNull);
    });
  });
}
