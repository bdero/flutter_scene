import 'dart:async' show Completer;

import 'package:flutter/foundation.dart'
    show
        Uint8List,
        debugPrint,
        immutable,
        internal,
        listEquals,
        visibleForTesting;
import 'package:flutter/rendering.dart'
    show
        BoxConstraints,
        BoxHitTestResult,
        ContainerBoxParentData,
        ContainerRenderObjectMixin,
        Offset,
        PaintingContext,
        RenderBox,
        RenderObject;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Builder,
        FlutterError,
        InheritedWidget,
        MultiChildRenderObjectWidget,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        Widget,
        WidgetBuilder;
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import 'package:flutter_scene/src/animation.dart'
    show AnimationClip, DecomposedTransform;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/materials_variants_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/widgets/scene_view.dart';

/// The declarative scene layer, widgets that own and reconcile [Node]s in a
/// retained [Scene]. Widgets are immutable descriptions; each widget's state
/// holds the engine object and applies property diffs on rebuild, so an
/// unchanged rebuild writes nothing and structural changes are proportional
/// to what changed.
///
/// The ownership rule is that a scene widget owns the [Node] it creates. Imperative code
/// may read those nodes (raycasts, queries) but must not restructure them or
/// write properties the widget also sets; such writes are overwritten by the
/// next build. The bridges between the two worlds are [SceneNodeHost]
/// (imperative subtree mounted inside a declarative tree) and
/// [SceneNodeController] (imperative handle to a widget-owned node).

/// Grants imperative access to the [Node] managed by a scene widget.
///
/// Attach one to a [SceneNode], [SceneMesh], or [SceneModel] and read [node]
/// to raycast against it, follow it with a camera, or drive per-frame motion.
/// Null while the widget is unmounted. For [SceneModel] the node is the
/// wrapper the imported content mounts under once loaded.
///
/// Writes are subject to the ownership rule: do not set properties the
/// owning widget also declares (they are overwritten on its next build).
/// A controller may be attached to at most one widget at a time.
/// {@category Widgets}
class SceneNodeController {
  _NodeLifecycle? _state;

  /// The managed node, or null while the owning widget is unmounted.
  Node? get node => _state?._node;
}

/// Provides the parent [Node] that descendant scene widgets attach to.
class _SceneParentScope extends InheritedWidget {
  const _SceneParentScope({required this.parent, required super.child});

  final Node parent;

  @override
  bool updateShouldNotify(_SceneParentScope oldWidget) =>
      !identical(parent, oldWidget.parent);
}

/// Resolves the node new scene widgets should attach under: the nearest
/// [_SceneParentScope], else the enclosing [SceneView]'s scene root.
Node _resolveParent(BuildContext context) {
  final scope = context.dependOnInheritedWidgetOfExactType<_SceneParentScope>();
  if (scope != null) return scope.parent;
  final sceneScope = SceneScope.maybeOf(context);
  if (sceneScope != null) return sceneScope.scene.root;
  throw FlutterError(
    'Scene widgets must be placed below a SceneView (or a SceneSubtree with an '
    'explicit parent). No SceneScope or scene parent was found above this '
    'widget.',
  );
}

/// Hosts scene-widget children in the element tree while occupying no layout
/// space and painting nothing. Scene widgets describe engine [Node]s, not
/// pixels; this host exists so their elements live in the tree and reconcile.
class _NodeChildHost extends MultiChildRenderObjectWidget {
  const _NodeChildHost({super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNodeChildHost();
}

class _NodeHostParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderNodeChildHost extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _NodeHostParentData> {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _NodeHostParentData) {
      child.parentData = _NodeHostParentData();
    }
  }

  @override
  void performLayout() {
    var child = firstChild;
    while (child != null) {
      child.layout(const BoxConstraints.tightFor(width: 0, height: 0));
      child = (child.parentData! as _NodeHostParentData).nextSibling;
    }
    size = constraints.smallest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}

/// Mounts declarative scene widgets under an app-owned [Node].
///
/// This is the bridge from an imperative scene to declarative subtrees: place
/// it anywhere below a [SceneView] and its [children] attach under [parent]
/// (or the scene root when [parent] is null). The same scene widgets work
/// unchanged under either root mode.
///
/// ```dart
/// SceneView(
///   scene,
///   children: [
///     SceneSubtree(
///       parent: markerAnchor,
///       children: [SceneMesh(geometry: g, material: m)],
///     ),
///   ],
/// )
/// ```
/// {@category Widgets}
class SceneSubtree extends StatelessWidget {
  const SceneSubtree({super.key, this.parent, this.children = const []});

  /// The node the [children] attach under. When null, the enclosing scene's
  /// root.
  final Node? parent;

  /// Scene widgets describing the subtree.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SceneParentScope(
      parent: parent ?? _resolveParent(context),
      child: _NodeChildHost(children: children),
    );
  }
}

/// The shared props of the node-managing scene widgets ([SceneNode],
/// [SceneMesh], [SceneModel]), so the lifecycle mixin diffs them in one
/// place and a new prop cannot be forgotten in one widget's diff.
abstract class _SceneNodeWidgetBase extends StatefulWidget {
  const _SceneNodeWidgetBase({
    super.key,
    this.name,
    this.position,
    this.rotation,
    this.scale,
    this.transform,
    this.visible = true,
    this.components = const [],
    this.controller,
    this.children = const [],
  }) : assert(
         transform == null ||
             (position == null && rotation == null && scale == null),
         'Provide either transform or position/rotation/scale, not both.',
       );

  /// The node's name, for lookups and debugging. Defaults to ''.
  final String? name;

  /// Local translation. Identity when null.
  final Vector3? position;

  /// Local rotation. Identity when null.
  final Quaternion? rotation;

  /// Local scale. One when null.
  final Vector3? scale;

  /// Full local transform. Mutually exclusive with the decomposed props.
  final Matrix4? transform;

  /// Whether the node (and its subtree) renders.
  final bool visible;

  /// Engine-side behavior attached to the node. Diffed by identity: keep a
  /// component instance stable across rebuilds to keep its state.
  final List<Component> components;

  /// Imperative handle to the managed node.
  final SceneNodeController? controller;

  /// Scene widgets describing this node's children.
  final List<Widget> children;
}

/// The shared engine-node lifecycle behind [SceneNode], [SceneMesh], and
/// [SceneModel]: creates the node, keeps it attached under the parent
/// resolved from context, applies transform/component/controller diffs, and
/// detaches on removal.
///
/// Transform props are diffed with the vector_math value equality the types
/// define; mutating one after passing it to a widget is undefined behavior,
/// matching Flutter's rule for collection props.
mixin _NodeLifecycle<T extends _SceneNodeWidgetBase> on State<T> {
  final Node _node = Node();
  Node? _attachedTo;
  List<Component> _declaredComponents = const [];
  List<Component> _appliedComponents = const [];
  SceneNodeController? _controller;

  /// The hosted child widgets; [SceneModel]'s state adds its
  /// placeholder/error subtrees.
  List<Widget> get _children => widget.children;

  @override
  void initState() {
    super.initState();
    _node.name = widget.name ?? '';
    _applyTransform();
    _node.visible = widget.visible;
    _syncComponents();
    _syncController();
  }

  void didUpdateProps(_SceneNodeWidgetBase oldWidget) {
    if (widget.name != oldWidget.name) {
      _node.name = widget.name ?? '';
    }
    if (widget.transform != oldWidget.transform ||
        widget.position != oldWidget.position ||
        widget.rotation != oldWidget.rotation ||
        widget.scale != oldWidget.scale) {
      _applyTransform();
    }
    if (widget.visible != _node.visible) {
      _node.visible = widget.visible;
    }
    _syncComponents();
    _syncController();
  }

  void _applyTransform() {
    final transform = widget.transform;
    if (transform != null) {
      // Clone so later in-place mutation of the caller's matrix cannot skew
      // the node behind the diff's back.
      _node.localTransform = transform.clone();
      return;
    }
    _node.setLocalTransformTrs(
      DecomposedTransform(
        translation: widget.position?.clone() ?? Vector3.zero(),
        rotation: widget.rotation?.clone() ?? Quaternion.identity(),
        scale: widget.scale?.clone() ?? Vector3(1.0, 1.0, 1.0),
      ),
    );
  }

  /// Identity-diffs the declared component list against what is attached:
  /// removed instances detach, added instances attach. Order changes alone
  /// are ignored (attach order is not semantic). An unchanged list instance
  /// (the common rebuild) skips the scan entirely.
  void _syncComponents() {
    final declared = widget.components;
    if (identical(declared, _declaredComponents)) return;
    _declaredComponents = declared;
    for (final component in _appliedComponents) {
      if (!declared.any((c) => identical(c, component))) {
        _node.removeComponent(component);
      }
    }
    for (final component in declared) {
      if (!_appliedComponents.any((c) => identical(c, component))) {
        _node.addComponent(component);
      }
    }
    _appliedComponents = List.of(declared);
  }

  void _syncController() {
    final controller = widget.controller;
    if (identical(controller, _controller)) return;
    if (identical(_controller?._state, this)) {
      _controller?._state = null;
    }
    _controller = controller;
    controller?._state = this;
  }

  /// Attaches the node under the parent resolved from context, moving it if
  /// the parent changed. Called from build, where inherited dependencies are
  /// registered, so scope changes rebuild us and re-sync.
  void _syncParent(BuildContext context) {
    final parent = _resolveParent(context);
    if (identical(parent, _attachedTo)) return;
    _detach();
    parent.add(_node);
    _attachedTo = parent;
  }

  void _detach() {
    final attachedTo = _attachedTo;
    if (attachedTo != null) {
      attachedTo.remove(_node);
      _attachedTo = null;
    }
  }

  @override
  void deactivate() {
    // Leave the scene while off the element tree; build re-attaches on
    // reinsertion (GlobalKey moves), dispose follows otherwise.
    _detach();
    super.deactivate();
  }

  @override
  void dispose() {
    // Detach the declared components so their onDetach cleanup runs and the
    // instances are reusable (a stable component instance declared by a
    // conditional subtree must attach again on the next mount).
    for (final component in _appliedComponents) {
      _node.removeComponent(component);
    }
    _appliedComponents = const [];
    _declaredComponents = const [];
    if (identical(_controller?._state, this)) {
      _controller?._state = null;
    }
    super.dispose();
  }

  Widget buildHost(BuildContext context) {
    _syncParent(context);
    return _SceneParentScope(
      parent: _node,
      child: _NodeChildHost(children: _children),
    );
  }
}

/// A declarative [Node]: a transform in the scene graph, described in
/// `build()`.
///
/// The widget owns a retained engine [Node]; rebuilding with changed
/// properties applies only the differences, and removing the widget detaches
/// the node. Give it [children] to describe a subtree, [components] for
/// engine-side behavior, and a [controller] for imperative access.
///
/// Provide the transform either decomposed ([position], [rotation], [scale])
/// or as a full [transform] matrix, not both. Transform props are treated as
/// immutable values; do not mutate a vector after passing it (pass a new one
/// instead). For motion every frame, prefer a [Component] or a
/// [SceneNodeController] over rebuilding, so no widgets rebuild per frame.
///
/// ```dart
/// SceneNode(
///   position: Vector3(0, 1, 0),
///   components: [SpinComponent()],
///   children: [SceneMesh(geometry: geometry, material: material)],
/// )
/// ```
/// {@category Widgets}
class SceneNode extends _SceneNodeWidgetBase {
  const SceneNode({
    super.key,
    super.name,
    super.position,
    super.rotation,
    super.scale,
    super.transform,
    super.visible,
    super.components,
    super.controller,
    super.children,
  });

  @override
  State<SceneNode> createState() => _SceneNodeState();
}

class _SceneNodeState extends State<SceneNode> with _NodeLifecycle<SceneNode> {
  @override
  void didUpdateWidget(SceneNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    didUpdateProps(oldWidget);
  }

  @override
  Widget build(BuildContext context) => buildHost(context);
}

/// A declarative mesh node: [SceneNode] plus a [Geometry] and [Material].
///
/// The [geometry] and [material] are engine objects diffed by identity, so
/// the mesh is only reassigned when a different instance is passed. Create
/// them once (for example in `initState` or a field) rather than per build;
/// constructing new GPU resources every rebuild is the main performance
/// hazard of the declarative layer.
///
/// ```dart
/// SceneMesh(
///   geometry: CuboidGeometry(Vector3(1, 1, 1)),
///   material: PhysicallyBasedMaterial(),
///   position: Vector3(0, 1, 0),
/// )
/// ```
/// {@category Widgets}
class SceneMesh extends _SceneNodeWidgetBase {
  const SceneMesh({
    super.key,
    required this.geometry,
    required this.material,
    super.name,
    super.position,
    super.rotation,
    super.scale,
    super.transform,
    super.visible,
    super.components,
    super.controller,
    super.children,
  });

  /// The vertex data to draw.
  final Geometry geometry;

  /// The material shading [geometry].
  final Material material;

  @override
  State<SceneMesh> createState() => _SceneMeshState();
}

class _SceneMeshState extends State<SceneMesh> with _NodeLifecycle<SceneMesh> {
  @override
  void initState() {
    super.initState();
    _node.mesh = Mesh(widget.geometry, widget.material);
  }

  @override
  void didUpdateWidget(SceneMesh oldWidget) {
    super.didUpdateWidget(oldWidget);
    didUpdateProps(oldWidget);
    if (!identical(widget.geometry, oldWidget.geometry) ||
        !identical(widget.material, oldWidget.material)) {
      _node.mesh = Mesh(widget.geometry, widget.material);
    }
  }

  @override
  Widget build(BuildContext context) => buildHost(context);
}

/// Mounts an app-owned [Node] subtree inside a declarative tree.
///
/// The inverse bridge to [SceneSubtree]: the declarative tree decides where
/// [node] hangs (wrap in a [SceneNode] to position it), while the application
/// owns everything inside it, imported models, procedurally generated
/// content, nodes shared with other systems. The widget attaches [node] on
/// mount and detaches it on removal; it never modifies or disposes the
/// node's contents.
///
/// The node must not be attached anywhere else while hosted.
/// {@category Widgets}
class SceneNodeHost extends StatefulWidget {
  const SceneNodeHost({super.key, required this.node});

  /// The app-owned subtree to mount.
  final Node node;

  @override
  State<SceneNodeHost> createState() => _SceneNodeHostState();
}

class _SceneNodeHostState extends State<SceneNodeHost> {
  Node? _attachedTo;

  void _syncParent(BuildContext context) {
    final parent = _resolveParent(context);
    if (identical(parent, _attachedTo)) return;
    _detach(widget.node);
    parent.add(widget.node);
    _attachedTo = parent;
  }

  void _detach(Node node) {
    final attachedTo = _attachedTo;
    if (attachedTo != null) {
      attachedTo.remove(node);
      _attachedTo = null;
    }
  }

  @override
  void didUpdateWidget(SceneNodeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.node, oldWidget.node)) {
      _detach(oldWidget.node);
    }
  }

  @override
  void deactivate() {
    _detach(widget.node);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    _syncParent(context);
    return const SizedBox.shrink();
  }
}

/// Describes where a [SceneModel] loads its model bytes from.
///
/// Mirrors the `ImageProvider` pattern: the widget diffs sources by
/// [cacheKey], so rebuilding with an equal-keyed source does not reload.
/// Built-in sources are [AssetModelSource] and [MemoryModelSource]; apps
/// with custom transports (network, local cache) subclass this or download
/// bytes themselves and wrap them in a [MemoryModelSource].
/// {@category Widgets}
abstract class SceneModelSource {
  const SceneModelSource();

  /// Identifies the model. A rebuild whose source has the same key keeps the
  /// loaded model; a different key discards it and loads the new source.
  String get cacheKey;

  /// Loads the model's `.glb` bytes.
  Future<Uint8List> load();

  /// Loads and imports the model, producing the shared template node tree.
  ///
  /// The default imports [load]'s bytes as a `.glb`. Override to import
  /// through another pipeline (or, in tests, to produce a hand-built tree
  /// with no GPU).
  Future<Node> createNode() async => Node.fromGlbBytes(await load());
}

/// Loads a `.glb` model from the asset bundle.
/// {@category Widgets}
class AssetModelSource extends SceneModelSource {
  const AssetModelSource(this.assetPath);

  /// The bundle path of the `.glb` asset.
  final String assetPath;

  @override
  String get cacheKey => 'asset:$assetPath';

  @override
  Future<Uint8List> load() async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// Wraps already-loaded `.glb` bytes, for models fetched by the app (a
/// network download, a local cache, generated content).
///
/// [key] must uniquely identify the bytes; the widget reloads when the key
/// changes, not when the buffer instance does. The buffer stays referenced
/// while the widget is mounted, since an unmount/remount cycle re-imports
/// from it after the shared template is evicted.
/// {@category Widgets}
class MemoryModelSource extends SceneModelSource {
  const MemoryModelSource(this.bytes, {required this.key});

  /// The `.glb` file contents.
  final Uint8List bytes;

  /// Uniquely identifies [bytes] for diffing.
  final String key;

  @override
  String get cacheKey => 'memory:$key';

  @override
  Future<Uint8List> load() async => bytes;
}

/// Declares the playback state of one of a [SceneModel]'s imported
/// animations.
///
/// An immutable value: rebuild with different values and the widget applies
/// the differences to the underlying [AnimationClip] as plain property
/// writes, so [weight] and [speed] can be driven by ordinary Flutter
/// animations (a `TweenAnimationBuilder` cross-fading two clips' weights,
/// for example). Clips for the same [name] persist across rebuilds; a spec
/// that disappears from [SceneModel.animations] stops its clip.
///
/// A one-shot spec ([loop] false) whose [playing] flips from false to true
/// restarts from the beginning; a looping spec resumes.
/// {@category Widgets}
@immutable
class SceneAnimationSpec {
  const SceneAnimationSpec(
    this.name, {
    this.playing = true,
    this.loop = true,
    this.weight = 1.0,
    this.speed = 1.0,
  });

  /// The imported animation's name.
  final String name;

  /// Whether the clip advances. Pausing keeps the current playback time.
  final bool playing;

  /// Whether the clip wraps at the end instead of pausing.
  final bool loop;

  /// Blend weight in `[0, 1]`; overlapping clips are weight-blended and
  /// normalized by the engine when the sum exceeds one.
  final double weight;

  /// Playback rate multiplier (negative plays in reverse).
  final double speed;

  @override
  bool operator ==(Object other) =>
      other is SceneAnimationSpec &&
      other.name == name &&
      other.playing == playing &&
      other.loop == loop &&
      other.weight == weight &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(name, playing, loop, weight, speed);
}

/// Applies [SceneAnimationSpec]s to a model root's animation clips: creates
/// clips lazily by name, diffs spec fields onto them, and stops clips whose
/// specs disappear. Kept separate from the widget so it is testable without
/// a GPU import.
@internal
class SceneAnimationBinder {
  final Map<String, AnimationClip> _clips = {};
  final Set<String> _warnedUnknown = {};
  Map<String, SceneAnimationSpec> _applied = const {};
  Node? _modelRoot;

  /// The clips created so far, keyed by animation name.
  Map<String, AnimationClip> get clips => Map.unmodifiable(_clips);

  /// Targets [modelRoot] (or null to unbind), clearing all clip state.
  void bind(Node? modelRoot) {
    _modelRoot = modelRoot;
    _clips.clear();
    _warnedUnknown.clear();
    _applied = const {};
  }

  /// Diffs [specs] against the previously applied set.
  void apply(List<SceneAnimationSpec> specs) {
    final root = _modelRoot;
    if (root == null) return;
    final wanted = {for (final spec in specs) spec.name};
    for (final entry in _clips.entries) {
      if (!wanted.contains(entry.key)) {
        // Stopping is not enough: the player blends every registered clip
        // regardless of playing, so a lingering clip would keep posing the
        // model at its first frame and dilute the remaining weights.
        entry.value.stop();
        root.removeAnimationClip(entry.value);
      }
    }
    _clips.removeWhere((name, _) => !wanted.contains(name));
    for (final spec in specs) {
      var clip = _clips[spec.name];
      if (clip == null) {
        final animation = root.findAnimationByName(spec.name);
        if (animation == null) {
          if (_warnedUnknown.add(spec.name)) {
            debugPrint(
              'SceneModel: unknown animation "${spec.name}" (available: '
              '${root.parsedAnimations.map((a) => a.name).toList()}).',
            );
          }
          continue;
        }
        clip = root.createAnimationClip(animation);
        _clips[spec.name] = clip;
      }
      final previous = _applied[spec.name];
      clip.loop = spec.loop;
      clip.weight = spec.weight;
      clip.playbackTimeScale = spec.speed;
      if (spec.playing) {
        // A one-shot re-triggered after finishing (or after an explicit
        // pause) restarts; a looping clip just resumes.
        final restarted = previous != null && !previous.playing;
        if (restarted && !spec.loop) {
          clip.replay();
        } else {
          clip.play();
        }
      } else {
        clip.pause();
      }
    }
    _applied = {for (final spec in specs) spec.name: spec};
  }
}

/// A refcounted template per [SceneModelSource.cacheKey]: bytes are loaded
/// and imported once, and each [SceneModel] instance mounts a [Node.clone]
/// of the shared template (geometry, textures, and materials stay shared;
/// primitives, skins, and the variants component are per instance). The
/// entry is evicted when the last user releases it.
class _ModelTemplateCache {
  static final Map<String, _ModelTemplateEntry> _entries = {};

  static Future<Node> acquire(SceneModelSource source) {
    final entry = _entries.putIfAbsent(
      source.cacheKey,
      () => _ModelTemplateEntry(_import(source)),
    );
    entry.refCount++;
    return entry.template;
  }

  static Future<Node> _import(SceneModelSource source) async {
    try {
      return await source.createNode();
    } catch (_) {
      // Evict so a later mount retries instead of caching the failure.
      _entries.remove(source.cacheKey);
      rethrow;
    }
  }

  /// Drops the entry for [cacheKey] so the next acquire re-imports. Live
  /// holders keep their clones; their later releases become no-ops.
  static void evict(String cacheKey) => _entries.remove(cacheKey);

  // TODO(model-cache-keepalive): eviction is immediate at refcount zero, so
  // an unmount/remount cycle (a list scrolling a model off and back)
  // re-imports from scratch; add a small keep-alive or unify with the
  // SceneRegistry template cache.
  static void release(String cacheKey) {
    final entry = _entries[cacheKey];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount <= 0) {
      _entries.remove(cacheKey);
    }
  }
}

class _ModelTemplateEntry {
  _ModelTemplateEntry(this.template);
  final Future<Node> template;
  int refCount = 0;
}

/// A declarative imported model: loads a `.glb` and mounts it as a node.
///
/// The widget owns a wrapper [Node] carrying the transform props; the
/// imported content attaches under it when loading completes. While loading,
/// [placeholder] (a scene-widget builder, not 2D UI) is mounted in its
/// place; on failure, [error] is mounted instead. For a single reveal of a
/// whole scene, prefer gating the enclosing [SceneView] with its `loading`
/// arguments over per-model placeholders.
///
/// [variant] selects a named `KHR_materials_variants` material variant, and
/// can change on rebuild for interactive switching (a product configurator).
/// Null keeps the model's default materials.
///
/// [animations] declares which imported animations play and how (see
/// [SceneAnimationSpec]); rebuilding with changed specs applies the
/// differences to the underlying clips.
///
/// Models are cached and shared: widgets whose sources have equal cache keys
/// load and import once, and each mounts its own clone of the shared
/// template (geometry, textures, and materials stay shared on the GPU). The
/// template is evicted when the last widget using it unmounts.
///
/// ```dart
/// SceneModel(
///   'models/shoe.glb',
///   variant: selectedColorway,
///   animations: [SceneAnimationSpec('Spin', speed: 0.5)],
///   position: Vector3(0, 1, 0),
/// )
/// ```
/// {@category Widgets}
class SceneModel extends _SceneNodeWidgetBase {
  /// Loads the model from the asset bundle at [assetPath].
  ///
  /// Not const because the source is derived; use [SceneModel.from] with a
  /// const [AssetModelSource] when const construction matters.
  SceneModel(
    String assetPath, {
    super.key,
    this.variant,
    this.animations = const [],
    this.placeholder,
    this.error,
    this.onLoaded,
    super.name,
    super.position,
    super.rotation,
    super.scale,
    super.transform,
    super.visible,
    super.components,
    super.controller,
    super.children,
  }) : source = AssetModelSource(assetPath);

  /// Loads the model from an explicit [SceneModelSource].
  const SceneModel.from(
    this.source, {
    super.key,
    this.variant,
    this.animations = const [],
    this.placeholder,
    this.error,
    this.onLoaded,
    super.name,
    super.position,
    super.rotation,
    super.scale,
    super.transform,
    super.visible,
    super.components,
    super.controller,
    super.children,
  });

  /// Clears the shared model template cache (tests only).
  @visibleForTesting
  static void debugClearModelTemplateCache() =>
      _ModelTemplateCache._entries.clear();

  /// Where the model bytes come from. Diffed by [SceneModelSource.cacheKey].
  final SceneModelSource source;

  /// The animations to play, declared by name. See [SceneAnimationSpec].
  final List<SceneAnimationSpec> animations;

  /// The `KHR_materials_variants` variant to select, or null for the
  /// model's default materials. Unknown names log a warning and keep the
  /// defaults.
  final String? variant;

  /// Builds scene widgets mounted while the model loads.
  final WidgetBuilder? placeholder;

  /// Builds scene widgets mounted when loading fails.
  final Widget Function(BuildContext context, Object error)? error;

  /// Called with the imported model root after it mounts. Use it to reach
  /// imported content imperatively (play animations, look up nodes).
  final void Function(Node modelRoot)? onLoaded;

  @override
  State<SceneModel> createState() => _SceneModelState();
}

class _SceneModelState extends State<SceneModel>
    with _NodeLifecycle<SceneModel> {
  Node? _modelRoot;
  Object? _loadError;
  int _loadGeneration = 0;
  String? _heldTemplateKey;
  bool _warnedUnknownVariant = false;
  final SceneAnimationBinder _animations = SceneAnimationBinder();

  // Ties this widget's load into the enclosing SceneView's reveal gate (the
  // loading/warmUp machinery), so a gated view stays on its loading widget
  // until declarative models are mounted. Registered once, on first build.
  Completer<void>? _loadGate;
  bool _gateChecked = false;

  @override
  List<Widget> get _children => [
    ...widget.children,
    if (_modelRoot == null && _loadError == null && widget.placeholder != null)
      Builder(builder: widget.placeholder!),
    if (_loadError != null && widget.error != null)
      Builder(builder: (context) => widget.error!(context, _loadError!)),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final source = widget.source;
    try {
      final template = await _ModelTemplateCache.acquire(source);
      if (!mounted || generation != _loadGeneration) {
        _ModelTemplateCache.release(source.cacheKey);
        return;
      }
      // Each widget mounts its own clone of the shared template; heavy GPU
      // resources stay shared, primitives/skins are per instance, and
      // components come along through Component.cloneFor plus the variants
      // rebind.
      final modelRoot = template.clone();
      MaterialsVariantsComponent.rebindClone(template, modelRoot);
      _node.add(modelRoot);
      _heldTemplateKey = source.cacheKey;
      setState(() {
        _modelRoot = modelRoot;
        _loadError = null;
      });
      _applyVariant();
      _animations.bind(modelRoot);
      _animations.apply(widget.animations);
      _registerHotReload(source, modelRoot);
      widget.onLoaded?.call(modelRoot);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() => _loadError = e);
    } finally {
      _settleLoadGate();
    }
  }

  // Asset-sourced models participate in asset hot reload: when the .glb's
  // bytes change, the shared template is evicted and this instance reloads
  // in place. Debug only (the coordinator no-ops otherwise). The closure
  // holds this state weakly so a dead widget cannot pin itself (the
  // registration itself is dropped once the model root is collected).
  void _registerHotReload(SceneModelSource source, Node modelRoot) {
    if (source is! AssetModelSource) return;
    final weakState = WeakReference<_SceneModelState>(this);
    HotReloadCoordinator.instance.registerScene(
      modelRoot,
      assetKey: source.assetPath,
      onReload: () async {
        _ModelTemplateCache.evict(source.cacheKey);
        final state = weakState.target;
        if (state == null || !state.mounted) return;
        state.setState(state._resetModel);
        await state._load();
      },
    );
  }

  void _registerLoadGate(BuildContext context) {
    if (_gateChecked) return;
    _gateChecked = true;
    final group = SceneScope.maybeOf(context)?.internalChildLoads;
    if (group == null) return;
    // Already-settled loads (a warm cache) register a completed future, so
    // the gate never waits on them.
    _loadGate = Completer<void>();
    if (_modelRoot != null || _loadError != null) {
      _loadGate!.complete();
    }
    group.add(_loadGate!.future);
  }

  void _settleLoadGate() {
    final gate = _loadGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void _releaseTemplate() {
    final held = _heldTemplateKey;
    if (held != null) {
      _ModelTemplateCache.release(held);
      _heldTemplateKey = null;
    }
  }

  void _resetModel() {
    _loadGeneration++;
    final modelRoot = _modelRoot;
    if (modelRoot != null) {
      _node.remove(modelRoot);
    }
    _releaseTemplate();
    _animations.bind(null);
    _modelRoot = null;
    _loadError = null;
  }

  @override
  void dispose() {
    _resetModel();
    _settleLoadGate();
    super.dispose();
  }

  void _applyVariant() {
    final modelRoot = _modelRoot;
    if (modelRoot == null) return;
    final variant = widget.variant;
    for (final component in MaterialsVariantsComponent.allOf(modelRoot)) {
      if (variant != null && !component.variants.contains(variant)) {
        if (!_warnedUnknownVariant) {
          _warnedUnknownVariant = true;
          debugPrint(
            'SceneModel: unknown material variant "$variant" '
            '(available: ${component.variants}); keeping defaults.',
          );
        }
        component.select(null);
        continue;
      }
      component.select(variant);
    }
  }

  @override
  void didUpdateWidget(SceneModel oldWidget) {
    super.didUpdateWidget(oldWidget);
    didUpdateProps(oldWidget);
    if (widget.source.cacheKey != oldWidget.source.cacheKey) {
      setState(_resetModel);
      _load();
      return;
    }
    if (widget.variant != oldWidget.variant) {
      _warnedUnknownVariant = false;
      _applyVariant();
    }
    if (!listEquals(widget.animations, oldWidget.animations)) {
      _animations.apply(widget.animations);
    }
  }

  @override
  Widget build(BuildContext context) {
    _registerLoadGate(context);
    return buildHost(context);
  }
}
