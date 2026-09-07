// Covers the codecs whose properties point at *other* nodes: a director's
// shot stack and a sequence's director and cut list. The document has no
// component reference, so each names the node carrying the component, and
// both resolve after the whole document is realized — which is the part
// worth testing, since the referenced nodes usually do not exist yet when the
// referring component is created.
import 'package:flutter_scene/src/camera_controllers/camera_director.dart';
import 'package:flutter_scene/src/camera_controllers/camera_sequence.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/kit/interaction/path_follower_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

/// A document with a director node plus [cameraCount] orbit-camera nodes.
/// The director is added FIRST on purpose: it references cameras that have
/// not been realized at the moment its own codec runs.
({SceneDocument doc, LocalId director, List<LocalId> cameras}) _rig({
  int cameraCount = 2,
  ComponentSpec Function(List<LocalId> cameras)? directorSpec,
  ComponentSpec Function(LocalId director, List<LocalId> cameras)? extra,
}) {
  final doc = SceneDocument();
  final directorId = doc.newId();
  final cameraIds = [for (var i = 0; i < cameraCount; i++) doc.newId()];

  doc.addNode(
    NodeSpec(
      id: directorId,
      name: 'director',
      components: [
        directorSpec?.call(cameraIds) ?? ComponentSpec('cameraDirector'),
        if (extra != null) extra(directorId, cameraIds),
      ],
    ),
    root: true,
  );
  for (var i = 0; i < cameraIds.length; i++) {
    doc.addNode(
      NodeSpec(
        id: cameraIds[i],
        name: 'cam$i',
        components: [ComponentSpec('orbitCameraController')],
      ),
      root: true,
    );
  }
  return (doc: doc, director: directorId, cameras: cameraIds);
}

ListValue _shots(List<LocalId> cameras, {List<double>? priorities}) =>
    ListValue([
      for (var i = 0; i < cameras.length; i++)
        MapValue({
          'node': NodeRefValue(cameras[i]),
          'priority': DoubleValue(priorities?[i] ?? i.toDouble()),
          'name': StringValue('shot$i'),
        }),
    ]);

void main() {
  group('cameraDirector', () {
    test('resolves shots that are realized after it', () {
      final rig = _rig(
        directorSpec: (cameras) => ComponentSpec(
          'cameraDirector',
          properties: {'shots': _shots(cameras)},
        ),
      );
      final root = realizeScene(rig.doc);
      final director = root
          .getChildByName('director')!
          .getComponent<CameraDirector>()!;

      expect(director.cameras, hasLength(2));
      final registrations = director.registrations.toList();
      expect(registrations[0].name, 'shot0');
      expect(registrations[1].priority, 1.0);
      // Nothing is live until a frame runs: the director selects on update,
      // so a restored shot stack proves itself by driving one.
      expect(director.activeCamera, isNull);
      director.update(1 / 60);
      expect(director.activeCamera, same(registrations[1].camera));
    });

    test('the shot stack round-trips as node references', () {
      final rig = _rig(
        directorSpec: (cameras) => ComponentSpec(
          'cameraDirector',
          properties: {
            'shots': _shots(cameras, priorities: [5, 2]),
          },
        ),
      );
      final back = serializeScene(realizeScene(rig.doc));
      final spec = back.rootNodes
          .firstWhere((n) => n.name == 'director')
          .components
          .firstWhere((c) => c.type == 'cameraDirector');
      final shots = (spec.properties['shots']! as ListValue).values;

      expect(shots, hasLength(2));
      final first = shots.first as MapValue;
      expect(first.values['node'], isA<NodeRefValue>());
      expect((first.values['priority']! as DoubleValue).value, 5.0);
      expect((first.values['name']! as StringValue).value, 'shot0');
    });

    test('a shot naming a node with no controller is dropped, not fatal', () {
      final doc = SceneDocument();
      final emptyId = doc.newId();
      doc.addNode(NodeSpec(id: emptyId, name: 'empty'), root: true);
      doc.addNode(
        NodeSpec(
          id: doc.newId(),
          name: 'director',
          components: [
            ComponentSpec(
              'cameraDirector',
              properties: {
                'shots': ListValue([
                  MapValue({'node': NodeRefValue(emptyId)}),
                ]),
              },
            ),
          ],
        ),
        root: true,
      );

      final root = realizeScene(doc);
      final director = root
          .getChildByName('director')!
          .getComponent<CameraDirector>()!;
      expect(director.cameras, isEmpty);
    });

    test('the blend curve round-trips by name', () {
      final rig = _rig(
        directorSpec: (_) => ComponentSpec(
          'cameraDirector',
          properties: {
            'defaultBlend': MapValue({
              'duration': const DoubleValue(1.5),
              'curve': const StringValue('easeOutCubic'),
            }),
          },
        ),
      );
      final root = realizeScene(rig.doc);
      final director = root
          .getChildByName('director')!
          .getComponent<CameraDirector>()!;
      expect(director.defaultBlend.duration, 1.5);

      final back = serializeScene(root);
      final spec = back.rootNodes
          .firstWhere((n) => n.name == 'director')
          .components
          .firstWhere((c) => c.type == 'cameraDirector');
      final blend = spec.properties['defaultBlend']! as MapValue;
      expect((blend.values['curve']! as StringValue).value, 'easeOutCubic');
    });

    test('shake configuration round-trips and starts still', () {
      final rig = _rig(
        directorSpec: (_) => ComponentSpec(
          'cameraDirector',
          properties: {
            'shake': MapValue({
              'decayRate': const DoubleValue(2.0),
              'frequency': const DoubleValue(30.0),
            }),
          },
        ),
      );
      final root = realizeScene(rig.doc);
      final director = root
          .getChildByName('director')!
          .getComponent<CameraDirector>()!;
      expect(director.shake!.decayRate, 2.0);
      expect(director.shake!.frequency, 30.0);
      // Trauma is live state; a scene must not load already shaking.
      expect(director.shake!.trauma, 0.0);

      final back = serializeScene(root);
      final spec = back.rootNodes
          .firstWhere((n) => n.name == 'director')
          .components
          .firstWhere((c) => c.type == 'cameraDirector');
      final shake = spec.properties['shake']! as MapValue;
      expect((shake.values['decayRate']! as DoubleValue).value, 2.0);
      expect(shake.values, isNot(contains('trauma')));
    });

    test('no shake stays absent', () {
      final rig = _rig();
      final root = realizeScene(rig.doc);
      expect(
        root.getChildByName('director')!.getComponent<CameraDirector>()!.shake,
        isNull,
      );
    });
  });

  group('cameraSequence', () {
    test('resolves its director and cut list after realize', () {
      final rig = _rig(
        directorSpec: (cameras) => ComponentSpec(
          'cameraDirector',
          properties: {'shots': _shots(cameras)},
        ),
        extra: (directorId, cameras) => ComponentSpec(
          'cameraSequence',
          properties: {
            'director': NodeRefValue(directorId),
            'loop': const BoolValue(true),
            'shots': ListValue([
              for (final id in cameras)
                MapValue({
                  'node': NodeRefValue(id),
                  'hold': const DoubleValue(2.5),
                }),
            ]),
          },
        ),
      );
      final root = realizeScene(rig.doc);
      final node = root.getChildByName('director')!;
      final sequence = node.getComponent<CameraSequence>()!;
      final director = node.getComponent<CameraDirector>()!;

      expect(sequence.director, same(director));
      expect(sequence.loop, isTrue);
      expect(sequence.shots, hasLength(2));
      expect(sequence.shots.first.hold, 2.5);
      expect(sequence.totalDuration, 5.0);
    });

    test('a sequence with no resolvable director still realizes', () {
      final doc = SceneDocument();
      doc.addNode(
        NodeSpec(
          id: doc.newId(),
          name: 'seq',
          components: [
            ComponentSpec(
              'cameraSequence',
              properties: {'director': NodeRefValue(doc.newId())},
            ),
          ],
        ),
        root: true,
      );
      final root = realizeScene(doc);
      final sequence = root
          .getChildByName('seq')!
          .getComponent<CameraSequence>()!;
      // It falls back to its placeholder rather than throwing; it simply has
      // nothing to drive.
      expect(sequence.shots, isEmpty);
      expect(sequence.isPlaying, isFalse);
    });
  });

  group('pathFollower', () {
    test('round-trips its movement tuning', () {
      final doc = SceneDocument();
      doc.addNode(
        NodeSpec(
          id: doc.newId(),
          name: 'mover',
          components: [
            ComponentSpec(
              'pathFollower',
              properties: {
                'speed': const DoubleValue(7.5),
                'facesTravel': const BoolValue(false),
                'slowRadius': const DoubleValue(2.0),
              },
            ),
          ],
        ),
        root: true,
      );

      final root = realizeScene(doc);
      final follower = root
          .getChildByName('mover')!
          .getComponent<PathFollowerComponent>()!;
      expect(follower.speed, 7.5);
      expect(follower.facesTravel, isFalse);
      expect(follower.slowRadius, 2.0);
      // A freshly loaded follower is idle: a half-walked route is play, not
      // authoring, so it is not a property.
      expect(follower.isMoving, isFalse);
      expect(follower.waypoints, isEmpty);

      final spec = serializeScene(root).rootNodes.single.components.single;
      expect((spec.properties['speed']! as DoubleValue).value, 7.5);
      expect(spec.properties, isNot(contains('waypoints')));
    });
  });
}
