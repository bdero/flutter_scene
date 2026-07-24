// Smoke tests for the physics abstraction: lifecycle of the
// fixedUpdate hook on Component, traversal order of
// Node.sceneFixedPass, and the fixed-step substepping driver
// (Scene.advancePhysics).

import 'dart:async';

import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart'
    show
        JointDesc,
        SimCollisionEvent,
        SimOverlapHit,
        SimRaycastHit,
        SimShapeCastHit;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class FixedTickRecorder extends Component {
  int fixedCalls = 0;
  int frameCalls = 0;
  double lastFixedDt = 0;

  @override
  void fixedUpdate(double fixedDt) {
    fixedCalls++;
    lastFixedDt = fixedDt;
  }

  @override
  void update(double deltaSeconds) {
    frameCalls++;
  }
}

class FakeSimulation extends PhysicsSimulation {
  final List<double> stepCalls = [];
  final List<double> interpolateCalls = [];

  @override
  String get backendName => 'fake';

  @override
  Stream<SimCollisionEvent> get collisions => const Stream.empty();

  @override
  int createBody({
    required PoseTarget target,
    required BodyType type,
    double? additionalMass,
  }) => 1;

  @override
  void destroyBody(int bodyHandle) {}

  @override
  void setBodyKind(int bodyHandle, BodyType type) {}

  @override
  int createAnchorBody() => 1;

  @override
  void destroyAnchorBody(int bodyHandle) {}

  @override
  (Vector3, Quaternion) readBodyPose(int bodyHandle) =>
      (Vector3.zero(), Quaternion.identity());

  @override
  Vector3 readBodyLinearVelocity(int bodyHandle) => Vector3.zero();

  @override
  Vector3 readBodyAngularVelocity(int bodyHandle) => Vector3.zero();

  @override
  void setBodyLinearVelocity(int bodyHandle, Vector3 velocity) {}

  @override
  void setBodyAngularVelocity(int bodyHandle, Vector3 velocity) {}

  @override
  void setBodyLinearDamping(int bodyHandle, double damping) {}

  @override
  void setBodyAngularDamping(int bodyHandle, double damping) {}

  @override
  void setBodyGravityScale(int bodyHandle, double scale) {}

  @override
  void setBodyCcdEnabled(int bodyHandle, bool enabled) {}

  @override
  void setBodyAdditionalMass(int bodyHandle, double mass) {}

  @override
  void setBodyAxisLocks(int bodyHandle, Vector3 linear, Vector3 angular) {}

  @override
  void setBodyKinematicTargetPose(
    int bodyHandle,
    Vector3 translation,
    Quaternion rotation,
  ) {}

  @override
  void applyForce(int bodyHandle, Vector3 force, {Vector3? atWorldPoint}) {}

  @override
  void applyImpulse(int bodyHandle, Vector3 impulse, {Vector3? atWorldPoint}) {}

  @override
  void applyTorque(int bodyHandle, Vector3 torque) {}

  @override
  void applyAngularImpulse(int bodyHandle, Vector3 impulse) {}

  @override
  bool isBodySleeping(int bodyHandle) => false;

  @override
  void wakeBody(int bodyHandle) {}

  @override
  void sleepBody(int bodyHandle) {}

  @override
  List<int> createColliders(
    int bodyHandle,
    Shape shape, {
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
    bool isTrigger = false,
    Matrix4? localPose,
    int collisionLayer = 0xFFFFFFFF,
    int collisionMask = 0xFFFFFFFF,
  }) => [1];

  @override
  void destroyCollider(int colliderHandle) {}

  @override
  void setColliderMaterial(int colliderHandle, PhysicsMaterial material) {}

  @override
  void setColliderFilter(int colliderHandle, int layer, int mask) {}

  @override
  int createJoint(JointDesc desc) => 1;

  @override
  void updateJoint(int jointHandle, JointDesc desc) {}

  @override
  void destroyJoint(int jointHandle) {}

  @override
  SimRaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => null;

  @override
  List<SimRaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => const [];

  @override
  List<SimOverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => const [];

  @override
  List<SimOverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => const [];

  @override
  SimShapeCastHit? shapeCast(
    Shape shape,
    Matrix4 from,
    Vector3 direction,
    double distance, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) => null;

  @override
  void step(double fixedDt) => stepCalls.add(fixedDt);

  @override
  void interpolatePoses(double alpha) => interpolateCalls.add(alpha);

  @override
  void dispose() {}
}

void main() {
  group('Component.fixedUpdate', () {
    test('default implementation is a no-op', () {
      // Calling the base method directly must not throw.
      const fixedDt = 1.0 / 60.0;
      expect(() => _BaseComponent().fixedUpdate(fixedDt), returnsNormally);
    });

    test('fixedTick is gated on enabled, mounted, and loaded', () async {
      final component = FixedTickRecorder();
      Node().addComponent(component);

      component.fixedTick(0.016);
      expect(component.fixedCalls, 0, reason: 'not mounted yet');

      component.mount();
      component.fixedTick(0.016);
      expect(component.fixedCalls, 0, reason: 'onLoad has not resolved');

      await Future<void>.delayed(Duration.zero);
      component.fixedTick(0.016);
      expect(component.fixedCalls, 1);

      component.enabled = false;
      component.fixedTick(0.016);
      expect(component.fixedCalls, 1, reason: 'disabled');
    });
  });

  group('Node.sceneFixedPass', () {
    test('visits parent components before child components', () async {
      final events = <String>[];
      Component recorder(String label) {
        final c = _LabeledRecorder(label, events);
        return c;
      }

      final root = Node();
      final parentRecorder = recorder('parent');
      root.addComponent(parentRecorder);

      final child = Node();
      final childRecorder = recorder('child');
      child.addComponent(childRecorder);
      root.add(child);

      // Mount and let onLoad resolve so fixedTick fires.
      parentRecorder.mount();
      childRecorder.mount();
      await Future<void>.delayed(Duration.zero);

      root.sceneFixedPass(0.016);
      expect(events, ['parent', 'child']);
    });
  });

  group('Scene.advancePhysics', () {
    test('takes the expected number of substeps and lerps the residual', () {
      final world = PhysicsWorld(FakeSimulation())
        ..fixedTimestep = 1.0 / 60.0
        ..maxSubsteps = 8;
      final walks = <double>[];
      final accumulator = Scene.advancePhysics(
        world: world,
        fixedUpdateWalk: walks.add,
        accumulator: 0,
        frameDt: 0.05,
      );

      // 0.05 / (1/60) = 3.0 steps exactly.
      expect((world.simulation as FakeSimulation).stepCalls.length, 3);
      expect(walks.length, 3);
      expect(
        (world.simulation as FakeSimulation).interpolateCalls,
        hasLength(1),
      );
      // Residual is effectively zero after a clean three-step consumption.
      expect(accumulator, closeTo(0.0, 1e-9));
      expect(
        (world.simulation as FakeSimulation).interpolateCalls.single,
        closeTo(0.0, 1e-9),
      );
    });

    test('residual produces a non-zero interpolation alpha', () {
      final world = PhysicsWorld(FakeSimulation())..fixedTimestep = 0.02;
      final accumulator = Scene.advancePhysics(
        world: world,
        fixedUpdateWalk: (_) {},
        accumulator: 0,
        frameDt: 0.025,
      );

      expect((world.simulation as FakeSimulation).stepCalls.length, 1);
      expect(accumulator, closeTo(0.005, 1e-9));
      expect(
        (world.simulation as FakeSimulation).interpolateCalls.single,
        closeTo(0.25, 1e-9),
      );
    });

    test('caps substeps at maxSubsteps and drops leftover time', () {
      final world = PhysicsWorld(FakeSimulation())
        ..fixedTimestep = 0.01
        ..maxSubsteps = 2;
      final accumulator = Scene.advancePhysics(
        world: world,
        fixedUpdateWalk: (_) {},
        accumulator: 0,
        // 10x the per-substep budget, well past the cap.
        frameDt: 0.1,
      );

      expect((world.simulation as FakeSimulation).stepCalls.length, 2);
      expect(
        accumulator,
        0.0,
        reason: 'leftover time should be dropped, not spiralled',
      );
      expect((world.simulation as FakeSimulation).interpolateCalls.single, 0.0);
    });
  });
}

class _BaseComponent extends Component {}

class _LabeledRecorder extends Component {
  _LabeledRecorder(this.label, this.events);

  final String label;
  final List<String> events;

  @override
  void fixedUpdate(double fixedDt) => events.add(label);
}
