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
  void update(double deltaSeconds) {}

  /// Called when the owning node leaves a live scene graph.
  void onUnmount() {}

  /// Called when this component is removed from a node.
  void onDetach() {}

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
}
