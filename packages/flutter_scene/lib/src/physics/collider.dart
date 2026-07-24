import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:flutter/foundation.dart';
import 'package:scene/scene.dart' as sim;
import 'package:vector_math/vector_math.dart';

/// A collision volume attached to a [Node].
///
/// Pairs a [shape] with a [material] and a local pose; a node may carry
/// several colliders forming a compound. When the node also carries a
/// [RigidBody] the collider attaches to it (add the body first); without
/// one it becomes static environment geometry through an implicit fixed
/// body.
/// {@category Physics}
class Collider extends Component {
  Collider({
    required sim.Shape shape,
    sim.PhysicsMaterial material = sim.PhysicsMaterial.defaultMaterial,
    int collisionLayer = 0xFFFFFFFF,
    int collisionMask = 0xFFFFFFFF,
    bool isTrigger = false,
    Matrix4? localPose,
  }) : _shape = shape,
       _material = material,
       _collisionLayer = collisionLayer,
       _collisionMask = collisionMask,
       _isTrigger = isTrigger,
       _localPose = localPose ?? Matrix4.identity();

  PhysicsWorld? _world;
  final List<int> _handles = [];
  int? _implicitBodyHandle;

  sim.Shape _shape;
  sim.PhysicsMaterial _material;
  int _collisionLayer;
  int _collisionMask;
  bool _isTrigger;
  Matrix4 _localPose;

  /// The owning world while mounted.
  PhysicsWorld? get world => _world;

  /// The simulation collider handles while mounted (compound shapes may
  /// produce several).
  @internal
  List<int> get handles => List.unmodifiable(_handles);

  sim.Shape get shape => _shape;

  /// Replacing the shape rebuilds the simulation colliders.
  set shape(sim.Shape value) {
    _shape = value;
    _rebuild();
  }

  sim.PhysicsMaterial get material => _material;
  set material(sim.PhysicsMaterial value) {
    _material = value;
    final world = _world;
    if (world == null) return;
    for (final handle in _handles) {
      world.simulation.setColliderMaterial(handle, value);
    }
  }

  /// Bitmask identifying this collider's layer. A contact is generated
  /// only when each side's layer is set in the other side's mask.
  int get collisionLayer => _collisionLayer;
  set collisionLayer(int value) {
    _collisionLayer = value;
    _pushFilter();
  }

  /// Bitmask of layers this collider responds to.
  int get collisionMask => _collisionMask;
  set collisionMask(int value) {
    _collisionMask = value;
    _pushFilter();
  }

  void _pushFilter() {
    final world = _world;
    if (world == null) return;
    for (final handle in _handles) {
      world.simulation.setColliderFilter(
        handle,
        _collisionLayer,
        _collisionMask,
      );
    }
  }

  /// When true this collider emits trigger events but produces no contact
  /// response. Changing it rebuilds the simulation colliders.
  bool get isTrigger => _isTrigger;
  set isTrigger(bool value) {
    if (value == _isTrigger) return;
    _isTrigger = value;
    _rebuild();
  }

  /// Pose of the collider relative to its owning node. Changing it
  /// rebuilds the simulation colliders.
  Matrix4 get localPose => _localPose;
  set localPose(Matrix4 value) {
    _localPose = value;
    _rebuild();
  }

  void _rebuild() {
    if (_world == null) return;
    _destroy();
    _create();
  }

  void _create() {
    final world = _world!;
    final body = node.getComponent<RigidBody>();
    final int bodyHandle;
    if (body != null) {
      final handle = body.handle;
      if (handle == null) {
        throw StateError(
          'Collider mounted before its sibling RigidBody; add the RigidBody '
          'component first',
        );
      }
      bodyHandle = handle;
    } else {
      // Static environment geometry, an implicit fixed body at the node.
      bodyHandle = world.simulation.createBody(
        target: NodePoseTarget(node),
        type: sim.BodyType.fixed,
      );
      _implicitBodyHandle = bodyHandle;
    }
    final created = world.simulation.createColliders(
      bodyHandle,
      _shape,
      material: _material,
      isTrigger: _isTrigger,
      localPose: _localPose,
      collisionLayer: _collisionLayer,
      collisionMask: _collisionMask,
    );
    if (created.isEmpty) {
      throw UnsupportedError(
        '${world.backendName} could not build colliders for '
        '${_shape.runtimeType}',
      );
    }
    _handles.addAll(created);
    for (final handle in created) {
      world.rememberCollider(handle, this);
    }
  }

  void _destroy() {
    final world = _world;
    if (world == null) return;
    for (final handle in _handles) {
      world.forgetCollider(handle);
      world.simulation.destroyCollider(handle);
    }
    _handles.clear();
    final implicit = _implicitBodyHandle;
    if (implicit != null) {
      world.simulation.destroyBody(implicit);
      _implicitBodyHandle = null;
    }
  }

  @override
  void onMount() {
    final world = findAncestorWorld(node);
    if (world == null) {
      throw StateError(
        'Collider mounted with no PhysicsWorld on an ancestor node',
      );
    }
    _world = world;
    _create();
  }

  @override
  void onUnmount() {
    _destroy();
    _world = null;
  }
}
