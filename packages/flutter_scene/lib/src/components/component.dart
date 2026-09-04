import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/node.dart';

/// A unit of data or behavior attached to a [Node].
///
/// A node owns an ordered list of components. Components are added with
/// [Node.addComponent] and removed with [Node.removeComponent], and they
/// run logic through a set of overridable lifecycle hooks.
///
/// Subclasses override the `onX` hooks and [update]; all other members
/// are driven by the engine and should not be called directly.
/// {@category Scene graph}
abstract class Component {
  Node? _node;

  /// The node this component is attached to.
  ///
  /// Valid between [onAttach] and [onDetach]. Reading it while the
  /// component is detached throws.
  Node get node => _node!;

  /// Whether this component is currently attached to a node.
  bool get isAttached => _node != null;

  /// Whether this component's [update] hook runs each frame.
  ///
  /// When `false`, [update] is skipped while leaving the component
  /// attached and mounted. Defaults to `true`.
  bool enabled = true;

  bool _mounted = false;

  /// Whether the owning node is part of a live scene graph.
  bool get isMounted => _mounted;

  bool _loaded = false;

  /// Whether [onLoad] has completed.
  ///
  /// [update] is skipped until this is `true`.
  bool get isLoaded => _loaded;

  /// Called when this component is added to a node.
  void onAttach() {}

  /// Optional asynchronous setup, such as loading an asset.
  ///
  /// Runs once, the first time the owning node enters a live scene.
  /// [update] is deferred until the returned future completes.
  Future<void> onLoad() async {}

  /// Called when the owning node enters a live scene graph.
  void onMount() {}

  /// Called once per frame while the component is mounted, [enabled], and
  /// loaded. [deltaSeconds] is the elapsed time since the previous tick.
  /// A traversal visits each component at most once. Removing this component
  /// or an earlier sibling is safe. A component inserted before the current
  /// traversal position starts on the next frame. Reordering component or
  /// child lists during traversal is unsupported.
  void update(double deltaSeconds) {}

  /// Whether this component wants [lateUpdate]. Declared rather than
  /// detected, so a node only pays for a late pass when something asks for
  /// one.
  bool get wantsLateUpdate => false;

  /// Runs after this node's whole subtree has updated: every descendant's
  /// components have ticked and every animation player below has posed its
  /// bones.
  ///
  /// This is where anything that *corrects* an animated pose belongs — a
  /// limb solved onto a target, a head turned to look at something, a bone
  /// clamped to a limit. Doing that work in [update] reads the previous
  /// frame's pose and is overwritten moments later by the animation player,
  /// which is the sort of bug that looks like a one-frame lag rather than
  /// like wrong ordering.
  ///
  /// Costs nothing when unused: a node with no late components never calls
  /// this.
  void lateUpdate(double deltaSeconds) {}

  /// Called once per fixed physics step while the component is mounted,
  /// [enabled], and loaded. [fixedDt] is the fixed timestep of the
  /// surrounding [PhysicsWorld], not the frame interval.
  ///
  /// Runs before [update] for the same frame and may run several times
  /// per frame when the renderer falls behind the physics rate. Most
  /// components should not override this; it exists for behavior that
  /// must advance on the physics clock (kinematic body controllers,
  /// character motion drivers).
  /// Mutation follows the same traversal rules as [update].
  void fixedUpdate(double fixedDt) {}

  /// Called when the owning node leaves a live scene graph.
  void onUnmount() {}

  /// Called when this component is removed from a node.
  void onDetach() {}

  /// Returns a copy of this component for [cloneOwner], the [Node.clone]
  /// counterpart of the owning node, or null to not carry the component to
  /// clones (the default).
  ///
  /// Follows the clone's sharing rule for meshes, heavyweight payloads stay
  /// shared while per-node identity is fresh, so an override typically wraps
  /// the same payload in a new component instance (the light components
  /// share their light object). Components whose state references other
  /// nodes cannot self-clone through this hook and need caller-driven
  /// rebinding instead (see `MaterialsVariantsComponent`).
  Component? cloneFor(Node cloneOwner) => null;

  @internal
  void attachTo(Node node) {
    _node = node;
    onAttach();
  }

  @internal
  void detachFrom() {
    onDetach();
    _node = null;
  }

  @internal
  void mount() {
    if (_mounted) return;
    _mounted = true;
    onMount();
    if (!_loaded) {
      onLoad().then((_) {
        // Guard against the component being unmounted before the load
        // completes.
        if (_mounted) _loaded = true;
      });
    }
  }

  @internal
  void unmount() {
    if (!_mounted) return;
    _mounted = false;
    onUnmount();
  }

  @internal
  void tick(double deltaSeconds) {
    if (enabled && _mounted && _loaded) {
      update(deltaSeconds);
    }
  }

  /// Runs [lateUpdate] when this component is live, mirroring [tick].
  @internal
  void lateTick(double deltaSeconds) {
    if (enabled && _mounted && _loaded) {
      lateUpdate(deltaSeconds);
    }
  }

  @internal
  void fixedTick(double fixedDt) {
    if (enabled && _mounted && _loaded) {
      fixedUpdate(fixedDt);
    }
  }
}
