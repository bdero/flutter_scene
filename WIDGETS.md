# Widgets in scenes

flutter_scene can place live Flutter widget trees on scene surfaces: the
widgets keep running (state, tickers, animations, buttons) while their visual
output is streamed into a texture that any material can sample, and pointer
input is forwarded back into them through scene raycasts. A control panel on
a wall, a screen in a cockpit, or a menu floating in space is one component.

```dart
scene.add(
  Node(name: 'panel')
    ..addComponent(WidgetComponent(
      size: const Size(480, 300),   // the widget's logical layout size
      pixelRatio: 2.0,              // texels per logical pixel
      worldHeight: 1.5,             // world units; width follows the aspect
      child: const MyControlPanel(),
    )),
);
```

That is the whole setup. The component creates an aspect-correct,
alpha-blended quad, `SceneView` hosts the widget invisibly (it never appears
in the 2D UI and takes no layout space), streams its output into the texture,
and forwards taps, drags, and scroll wheel input automatically: a press
raycasts into the scene, and when the panel is the nearest hit, the
interaction lands on the widgets at exactly the point you see. Geometry in
front of the panel blocks input, and a drag that slides off the panel's edge
stays captured by it, so sliders and scrolls behave.

## Bring your own surface

Three tiers share the one component; each takes over a little more.

**Your geometry.** Any surface with a sane 0..1 UV unwrap works, curved
screens included; input accuracy follows the UVs automatically:

```dart
WidgetComponent(
  size: const Size(480, 300),
  geometry: myCurvedScreenGeometry,
  child: const MyControlPanel(),
)
```

**Your material.** Known built-in materials bind implicitly (the capture
lands in `baseColorTexture`); everything else takes a `bind` callback, which
is also the hook for multi-slot binding:

```dart
WidgetComponent(
  size: const Size(480, 300),
  geometry: crtScreen,
  material: crtMaterial,           // e.g. a ShaderMaterial from an .fmat
  bind: (texture) {
    crtMaterial.parameters.setTexture('screen_tex', texture);
    crtMaterial.parameters.setTexture('glow_tex', texture);
  },
  child: const MyControlPanel(),
)
```

The texture object is stable across captures (it is overwritten in place)
and replaced only when the capture size changes; `bind` re-fires exactly on
replacement.

**No surface at all.** For a screen that already exists, such as a display
inside an imported model, `bindOnly` captures and binds without creating any
mesh. Input still works: the raycast hits the imported mesh, and its
authored UVs drive the forwarding:

```dart
final screen = car.getChildByName('DashScreen')!;
screen.addComponent(WidgetComponent.bindOnly(
  size: const Size(320, 240),
  bind: (texture) =>
      (screen.mesh!.primitives.first.material as PhysicallyBasedMaterial)
        ..baseColorTexture = texture
        ..emissiveTexture = texture,
  child: const SpeedometerUI(),
));
```

## Update policies

Captures default to `WidgetUpdatePolicy.everyFrame`: the widget is
re-recorded each frame, which is the only trigger that observes every
change (repaints inside the child's own repaint boundaries, scrollable
items, progress indicators, update their layers without notifying
ancestors). The recording reuses the child's retained layers, so the
steady-state cost is rasterizing and reading back content that actually
changes. `WidgetUpdatePolicy.interval(duration)` throttles that cadence,
and `WidgetUpdatePolicy.manual` captures only on
`controller.requestCapture()`, right for genuinely static panels. Captures
are asynchronous and throttled to one in flight; content that changes
faster than captures complete skips intermediate frames and converges on
the latest.

`pixelRatio` sets texel density independently of world size. Blurry panel
text means the texture is too small for its on-screen size; raise
`pixelRatio` rather than the world size.

## Input

Automatic input (`WidgetInput.automatic`, the default) is driven by
`SceneView` and needs no setup. It never enters gesture arenas, so it does
not fight the app's own gesture handling; events pass through to your
handlers regardless of what they hit. Set `WidgetInput.manual` to opt a
surface out.

When something does not respond, set `SceneView.debugWidgetInput: true`: it
overlays the pointer's hit node, distance, and UV, and marks the pointer
green over a widget surface and orange over anything else.

For programmatic input, a crosshair in a first-person game, a gamepad-driven
virtual cursor, drive a `ScenePointer`:

```dart
final pointer = ScenePointer(scene, maxDistance: 3.0);

// Each frame (or whenever your input source moves):
pointer.pointAt(crosshairPosition, camera: camera, viewSize: viewSize);
crosshair.highlight = pointer.hoveredWidget != null;

// Input bindings:
onUseDown: () => pointer.press(),
onUseUp:   () => pointer.release(),
onScroll: (d) => pointer.scroll(d),
```

`pointAlong(ray)` takes an arbitrary world ray instead of a screen position.
Filtering has two independent axes: `layerMask`, `where`, and `maxDistance`
control what the ray hits (so a wall blocks a press without being
interactive), and `interactionMask` controls which widget surfaces this
pointer may drive. Multiple pointers coexist with independent capture and
hover. `pressTravel` reports the UV-space travel between press and release
for click-versus-drag decisions.

Below `ScenePointer`, every component's `controller` accepts direct UV-space
events (`pointerDown(uv)`, `pointerMove`, `pointerUp`, `pointerCancel`,
`pointerScroll`, `tapAt`), and below that, `Scene.raycast` returns hits with
interpolated UVs for fully custom routing. Each layer is a strict superset
of control over the one above it.

## Scene raycasting

The same query that powers input is general-purpose:

```dart
final hit = scene.raycast(camera.screenPointToRay(tapPosition, viewSize));
// hit: node, distance, worldPoint, worldNormal, uv, barycentrics,
//      triangleIndex, primitiveIndex
```

It tests the rendered meshes directly, no colliders or physics setup, and
interpolates the texture coordinate from the vertex data, so a hit on any
shape carries the surface UV. Invisible subtrees are skipped by default
(`includeInvisible:` opts in), and candidates are filtered by `layerMask`
(against `Node.layers`), the per-node `raycastable` flag, and an optional
`where` predicate. `raycastAll` returns every hit sorted nearest-first.
Skinned meshes are tested at rest pose, and this is distinct from the
physics queries (`PhysicsWorld.raycast`), which test collision shapes.

## Current limitations

* Captures round-trip through the CPU (rasterize, read back, upload). The
  cost is a few milliseconds per capture at typical panel sizes and is paid
  only when content changes; a future engine API will keep captures on the
  GPU with no change to this surface.
* Hover is queryable on `ScenePointer` but not forwarded into the widgets
  (`MouseRegion` enter/exit does not fire on panel widgets yet).
* Keyboard input and focus are not forwarded; text fields on panels are not
  yet usable.
* Widget components do not serialize to `.fscene` (a widget tree is code);
  attach them at runtime.
