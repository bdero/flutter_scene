# Structuring a flutter_scene app

Which API to build the scene with, and how to combine them. The short version is in SKILL.md;
this is the depth, with patterns that compile against 0.22.0.

flutter_scene exposes the same scene graph two ways. The declarative widgets describe it as Flutter
widgets that rebuild-diff into the graph; the imperative API hands you the retained `Scene`/`Node`/
`Component` graph directly. They are not competing renderers, they drive the same engine. The choice
is about how your app tracks state, and it is worth making deliberately because reworking a large
scene from one to the other is a rewrite.

---

## The decision

Go **declarative** when app state maps directly onto a fixed set of shown objects and nothing
simulates. A product configurator, a data-driven diagram, a few models whose transforms follow some
`setState` values. Flutter already owns the state, and the widgets keep the scene tracking it for
free.

Go **imperative** when the scene simulates. Complex physics, network replication, a character
walking around under input, procedural generation. Any one of these means imperative. Here the
scene's state is the app's state, it changes every frame, and you want to own the loop rather than
express each frame as a widget rebuild.

If you are unsure, ask whether anything in the scene changes on its own between user actions. If yes,
imperative. If the scene only changes when the user changes a value, declarative.

---

## Declarative

`SceneView.declarative` owns an internal `Scene`; its `children` are the whole scene description.

```dart
class Configurator extends StatefulWidget {
  const Configurator({super.key});
  @override
  State<Configurator> createState() => _ConfiguratorState();
}

class _ConfiguratorState extends State<Configurator> {
  // Build engine objects once, not per rebuild. Constructing GPU resources
  // every build is the main performance hazard of the declarative layer.
  final Geometry _geometry = CuboidGeometry(vm.Vector3(1, 1, 1));
  final PhysicallyBasedMaterial _material = PhysicallyBasedMaterial();
  double _spin = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: SceneView.declarative(
          camera: PerspectiveCamera(position: vm.Vector3(2, 2, -4)),
          children: [
            SceneMesh(
              geometry: _geometry,
              material: _material,
              rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _spin),
            ),
          ],
        ),
      ),
      Slider(
        value: _spin,
        max: 6.28,
        onChanged: (v) => setState(() => _spin = v),
      ),
    ]);
  }
}
```

The scene tracks widget state through the normal rebuild path. Note two things the example shows:
engine objects (`geometry`, `material`) are created once and held as fields (they are diffed by
identity, and rebuilding them every frame is the classic mistake), while cheap value props
(`rotation`) are fine to pass fresh each build.

Declarative building blocks (all under `SceneView.declarative` or a `SceneView` with `children`):

- `SceneMesh(geometry:, material:, ...)` a node with a mesh.
- `SceneNode(...)` a bare transform node, for grouping children.
- `SceneModel('assets/x.glb', animations: [...])` a loaded model (runtime glTF path).
- `SceneSubtree(parent:, children:)` mounts children under a given imperative `Node`.
- Every node widget takes `position`/`rotation`/`scale` (or a full `transform`), `visible`,
  `components:` (attach imperative `Component`s), `controller:` (a `SceneNodeController` handle), and
  `children:`.

---

## Imperative

Own the `Scene`, add `Node`s, attach `Component`s, display with `SceneView(scene, camera:, onTick:)`.
For anything beyond a demo, do not scatter this across a `StatefulWidget`. Put it in a plain Dart
class that owns the scene and the game state, and keep the widget thin.

```dart
// Pure Dart, no Flutter import. Owns the scene and the game state.
class Game {
  final Scene scene = Scene();
  late final Node player;

  Future<void> load() async {
    await Scene.initializeStaticResources();

    // The camera lives in the scene as a node, not on the widget. A camera
    // node's transform is its view: the translation is the eye, local +Z is
    // the look direction, +Y is up. lookAtFrom sets both at once, so there is
    // no view-matrix math to hand-roll.
    final cameraNode = Node()
      ..addComponent(CameraComponent(activateOnMount: true))
      ..lookAtFrom(vm.Vector3(0, 3, -8), vm.Vector3.zero());
    scene.add(cameraNode);
    // activateOnMount makes this the scene's primary camera when the node
    // mounts, so SceneView needs no `camera:` argument. (The first mounted
    // camera auto-promotes anyway; this states the intent explicitly, and is
    // how you pick one when several cameras exist.)

    player = Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)),
        PhysicallyBasedMaterial()));
    player.addComponent(PlayerController());
    scene.add(player);
  }

  // Per-frame app logic that is not tied to one node. Component updates run
  // on their own (see below), so this is for whole-game concerns.
  void tick(double dt) {
    // advance timers, spawn waves, read input, etc.
  }
}
```

```dart
// Thin widget: builds the game, forwards ticks, renders the scene.
class GameView extends StatefulWidget {
  const GameView({super.key});
  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  final Game game = Game();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    game.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    // No `camera:` here: the view resolves the scene's active camera, which is
    // the CameraComponent added in Game.load. Resolution order is the explicit
    // `camera:` (absent), then `cameraBuilder`, then `scene.camera` (the active
    // CameraComponent), then a default camera.
    return SceneView(
      game.scene,
      onTick: (elapsed, dt) => game.tick(dt),
    );
  }
}
```

### The active camera

The scene owns which camera is active, and there are three levers:

- **`CameraComponent(activateOnMount: true)`** (above) selects this camera when its node mounts.
- **`cameraComponent.makeActive()`** switches to it at runtime, for example a chase-cam to a
  cutscene camera. Before its node mounts the choice is deferred and applied on mount.
- **`scene.camera = someCamera`** sets any `Camera` as the override directly, and `scene.camera`
  reads the active one back.

With no camera set at all, the first mounted `CameraComponent` auto-promotes, and a scene with none
still renders through a default camera. Move or rotate a `CameraComponent`'s node to move the view;
the `NodeCamera` reads the node's world transform live each frame. Aim it with `node.lookAt(target)`
(rotate toward a world point) or `node.lookAtFrom(eye, target)` (position and aim in one call); +Z is
the forward axis, so the same helpers aim lights and imported models. A follow-cam is then a one-line
component that calls `node.lookAtFrom(...)` in `update` each frame.

### Camera controllers (interactive cameras)

For a user-controlled camera, do not hand-roll the drag/scroll/key math: attach a camera controller
component to the camera node. `OrbitCameraController` (turntable around a target, drag rotates, scroll
dollies), `FlyCameraController` (WASD + drag free flight, `moveVertical: false` gives grounded
first-person), and `FollowCameraController` (third-person that eases behind a target node). Each holds
the camera state, eases toward it with frame-rate-independent smoothing, clamps pitch so the view
never flips, and writes the node via `lookAtFrom`.

Wire input with the `CameraControls` widget wrapping the view; it forwards Flutter gestures and keys
to the controller. `SceneView` itself has no camera-input knobs, so nothing camera-specific leaks into
it.

```dart
final camera = Node()
  ..addComponent(CameraComponent(activateOnMount: true))
  ..addComponent(OrbitCameraController(target: vm.Vector3.zero(), distance: 8));
scene.add(camera);

// In build:
return CameraControls(
  controller: camera.getComponent<OrbitCameraController>()!,
  child: SceneView(scene),
);
```

The controllers also expose intent methods (`orbitBy`, `dollyBy`, `panBy`, `look`), so an app with its
own input handling can drive them without the widget.

### Behavior lives in components, not in the tick

The bulk of per-object logic should be custom `Component`s, not a giant `onTick`. A component is
attached to a node and the engine runs it through the lifecycle. Crucially, component ticks are
driven automatically by the render path, so you do not call them yourself, and `onTick` is only for
game-wide concerns that do not belong to a single node.

```dart
class PlayerController extends Component {
  vm.Vector3 velocity = vm.Vector3.zero();

  @override
  void onMount() {
    // node is available here; wire up input, cache references.
  }

  @override
  void update(double deltaSeconds) {
    // `node` is the node this component is attached to.
    node.mutateLocalTransform(
      (m) => m.translateByVector3(velocity * deltaSeconds),
    );
  }
}
```

Component lifecycle hooks (subclass `Component`, override what you need):

- `onAttach()` added to a node, before it is in a live scene.
- `Future<void> onLoad()` async setup (await assets); mount waits for it.
- `onMount()` the node entered a live scene; `node` is usable.
- `update(double deltaSeconds)` per rendered frame.
- `fixedUpdate(double fixedDt)` fixed-step, driven by the physics accumulator when a `PhysicsWorld`
  is present. Put physics-coupled logic here, not in `update`.
- `onUnmount()` / `onDetach()` teardown.

This is the structure that scales. A character is a node with a controller component; an enemy is a
node with an AI component; a pickup is a node with a trigger component. The `Game` class holds what
is genuinely global (score, wave state, the input map), and everything spatial is a component on a
node.

---

## Hybrid interop

The two APIs share one graph, so you can mix them at the seam that suits the app.

**Declarative shell, imperative pockets.** A declarative node accepts `components:`, so an otherwise
declarative scene can attach imperative behavior to any node without leaving the widget tree.

```dart
SceneMesh(
  geometry: _geometry,
  material: _material,
  components: [Spinner()], // a custom Component, ticked by the engine
)
```

**Imperative scene, declarative subtrees.** `SceneView(scene, children: [...])` mounts declarative
widgets over an app-owned scene. Use `SceneSubtree(parent: someNode, children: [...])` to attach a
declarative subtree under a specific imperative node, for example UI-like markers that follow a
game object.

```dart
SceneView(
  game.scene,
  camera: PerspectiveCamera(position: vm.Vector3(0, 3, -8)),
  children: [
    SceneSubtree(
      parent: game.player,
      children: [SceneModel('assets/hat.glb')],
    ),
  ],
)
```

**Reaching an imperative node from a declarative widget.** Pass a `SceneNodeController` as
`controller:` and read `controller.node` for the managed `Node` (null while unmounted). This is the
escape hatch when a declarative node needs an imperative handle for a one-off operation.

The rule of thumb: pick the mode that matches how the *majority* of the scene is driven, then use the
seam above for the exceptions. Do not build a whole simulation out of declarative widgets to avoid
the imperative API, and do not hand-roll a diffing layer over the imperative graph to avoid the
declarative one.
