// The IK constraint and the late pass it depends on. Nodes and components run
// without a GPU, so the ordering guarantee and the solve are both testable.
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Records the order update and lateUpdate ran in.
class _Recorder extends Component {
  _Recorder(this.label, this.log, {this.late = false});

  final String label;
  final List<String> log;
  final bool late;

  @override
  bool get wantsLateUpdate => late;

  @override
  void update(double deltaSeconds) => log.add('update:$label');

  @override
  void lateUpdate(double deltaSeconds) => log.add('late:$label');
}

/// A limb: root at the origin, mid out along X, tip down from there.
({Node root, Node bone0, Node bone1, Node bone2}) limb() {
  final root = Node(name: 'character');
  final bone0 = Node(name: 'thigh')..position = Vector3(0, 0, 0);
  final bone1 = Node(name: 'shin')..position = Vector3(1, 0, 0);
  final bone2 = Node(name: 'foot')..position = Vector3(0, -1, 0);
  bone1.add(bone2);
  bone0.add(bone1);
  root.add(bone0);
  return (root: root, bone0: bone0, bone1: bone1, bone2: bone2);
}

/// Components only tick once mounted and loaded, and loading completes on a
/// microtask.
Future<void> mountAll(List<Component> components) async {
  for (final component in components) {
    component.mount();
  }
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('the late pass', () {
    test('runs after every component in the subtree has updated', () async {
      // This is the ordering the constraint depends on: correcting a pose
      // has to happen after the pose exists.
      final log = <String>[];
      final root = Node(name: 'root');
      final child = Node(name: 'child');
      root.add(child);
      final rootComponent = _Recorder('root', log, late: true);
      final childComponent = _Recorder('child', log);
      root.addComponent(rootComponent);
      child.addComponent(childComponent);
      await mountAll([rootComponent, childComponent]);

      root.scenePrePass(1 / 60);

      expect(log, ['update:root', 'update:child', 'late:root']);
    });

    test('a component that does not ask for it is never late-ticked', () async {
      final log = <String>[];
      final component = _Recorder('a', log);
      final root = Node(name: 'root')..addComponent(component);
      await mountAll([component]);
      root.scenePrePass(1 / 60);
      expect(log, ['update:a']);
    });

    test('removing a component takes it out of the late pass', () async {
      final log = <String>[];
      final component = _Recorder('a', log, late: true);
      final root = Node(name: 'root')..addComponent(component);
      await mountAll([component]);
      root.scenePrePass(1 / 60);
      expect(log, containsAllInOrder(['update:a', 'late:a']));

      log.clear();
      root.removeComponent(component);
      root.scenePrePass(1 / 60);
      expect(log, isEmpty);
    });
  });

  group('the constraint', () {
    test('pulls the tip onto its target', () async {
      final rig = limb();
      final target = Vector3(1.2, -0.4, 0);
      final constraint = IkConstraintComponent(
        rootBone: 'thigh',
        midBone: 'shin',
        tipBone: 'foot',
        target: (_) => target,
      );
      rig.root.addComponent(constraint);
      await mountAll([constraint]);

      rig.root.scenePrePass(1 / 60);

      final tip = rig.bone2.globalTransform.getTranslation();
      expect((tip - target).length, lessThan(1e-4));
    });

    test('a null target leaves the limb where the animation put it', () async {
      // How a planted foot stops being planted the moment it leaves the
      // ground, without the limb snapping.
      final rig = limb();
      final before = rig.bone2.globalTransform.getTranslation();
      final constraint = IkConstraintComponent(
        rootBone: 'thigh',
        midBone: 'shin',
        tipBone: 'foot',
        target: (_) => null,
      );
      rig.root.addComponent(constraint);
      await mountAll([constraint]);

      rig.root.scenePrePass(1 / 60);

      expect(
        (rig.bone2.globalTransform.getTranslation() - before).length,
        lessThan(1e-9),
      );
    });

    test('zero weight is the same as no constraint', () async {
      final rig = limb();
      final before = rig.bone2.globalTransform.getTranslation();
      final constraint = IkConstraintComponent(
        rootBone: 'thigh',
        midBone: 'shin',
        tipBone: 'foot',
        target: (_) => Vector3(1.2, -0.4, 0),
        weight: 0,
      );
      rig.root.addComponent(constraint);
      await mountAll([constraint]);
      rig.root.scenePrePass(1 / 60);
      expect(
        (rig.bone2.globalTransform.getTranslation() - before).length,
        lessThan(1e-9),
      );
    });

    test('a partial weight lands between the pose and the solve', () async {
      final rig = limb();
      final before = rig.bone2.globalTransform.getTranslation();
      final target = Vector3(1.2, -0.4, 0);
      final constraint = IkConstraintComponent(
        rootBone: 'thigh',
        midBone: 'shin',
        tipBone: 'foot',
        target: (_) => target,
        weight: 0.5,
      );
      rig.root.addComponent(constraint);
      await mountAll([constraint]);
      rig.root.scenePrePass(1 / 60);

      final tip = rig.bone2.globalTransform.getTranslation();
      expect((tip - before).length, greaterThan(1e-3), reason: 'it moved');
      expect(
        (tip - target).length,
        greaterThan(1e-3),
        reason: 'not all the way',
      );
    });

    test('the tip is reached even when the character is turned', () async {
      // The solve is world-space and bone rotations are local, so a turned
      // parent is where a missing basis change shows up.
      final rig = limb();
      rig.root.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), 1.0);
      final target = Vector3(0.4, -0.5, -0.9);
      final constraint = IkConstraintComponent(
        rootBone: 'thigh',
        midBone: 'shin',
        tipBone: 'foot',
        target: (_) => target,
      );
      rig.root.addComponent(constraint);
      await mountAll([constraint]);

      rig.root.scenePrePass(1 / 60);

      final tip = rig.bone2.globalTransform.getTranslation();
      expect((tip - target).length, lessThan(1e-3));
    });

    test('a missing bone leaves the rig alone rather than throwing', () async {
      final rig = limb();
      final before = rig.bone2.globalTransform.getTranslation();
      final constraint = IkConstraintComponent(
        rootBone: 'thigh',
        midBone: 'nope',
        tipBone: 'foot',
        target: (_) => Vector3(1, 0, 0),
      );
      rig.root.addComponent(constraint);
      await mountAll([constraint]);
      expect(() => rig.root.scenePrePass(1 / 60), returnsNormally);
      expect(
        (rig.bone2.globalTransform.getTranslation() - before).length,
        lessThan(1e-9),
      );
    });
  });
}
