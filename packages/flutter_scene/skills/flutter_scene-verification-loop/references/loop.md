# The verification loop in detail

The core loop, the readiness gate, and the blind-judgment rule are in `SKILL.md`. This file has the
tool table (what exists where), the settle details, and the symptom to action map.

---

## Two tooling tiers

### Baseline (any project, no MCP)

This always works and needs nothing installed beyond the package setup.

- Launch: `flutter run --enable-flutter-gpu` (native; add `-d chrome` for web). The flag is mandatory.
- Console: read the run log. The readiness line, `debugPrint` output, asserts, and the 0.22.0
  blank-frame diagnostic all land here.
- Frame: take a screenshot of the running app after it settles.

That is the whole loop when there is no editor. Run, settle, screenshot, read the log, correct.

### Editor MCP (`flutter_scene_mcp`, when connected)

The editor exposes richer observation. Tool names below are exact. Do not assume they exist unless
the MCP is actually connected for the current project.

| Tool | What it does | Reach for it when |
| --- | --- | --- |
| `run_project` | Launch the editor-managed Play session (a managed `flutter run`). | Starting a session under the editor. |
| `build_project` | Start the selected build config; output streams to the console. | You want a build without launching. |
| `stop_project` | Stop the running session. | Ending or restarting cleanly. |
| `hot_reload` | Hot reload the running debug session. | A Dart-only change, fastest turnaround. |
| `hot_restart` | Hot restart the session. | State or startup changed, or reload did not take. |
| `get_console` | The build/run console tail plus building/running flags. | EVERY iteration, paired with a screenshot. |
| `screenshot_viewport` | The viewport as a PNG, what the user sees. | EVERY iteration, paired with the console. |
| `describe_scene` | The scene-graph tree (ids, paths, names, component types). | Confirming a node/mesh is actually in the scene. |
| `scan_for_nans` | Capture a frame and scan every float render target for NaN/Inf in pass order. | A black or garbage frame with no error. Find where non-finite values start. |
| `capture_render_graph` | Capture the next frame's graph with thumbnails. | You need to see intermediate buffers. |
| `list_render_passes` | The executed passes in order with CPU timings and the buffer keys each read/wrote, plus target formats and sizes. No images. | Learning which pass owns which buffer, and the key names to read. |
| `get_pass_output` | Render one captured buffer (a key like `scene_color`, `linear_depth`) as a PNG. NaN paints magenta, Inf yellow, negative blue. | Eyeballing an intermediate buffer to see which stage broke. |
| `read_pass_pixel` | One pixel's exact float RGBA from a captured buffer, with NaN/Inf flags. | Confirming an exact value (is this really 0, or NaN, or negative). |
| `list_viewport_debug_modes` | The available debug outputs (final, HDR color, linear depth, normals, AO, shadow atlas, ...) and which is active. | Seeing what debug views exist. |
| `set_viewport_debug_mode` | Render one debug output full-viewport. Set `final` to restore. | Inspecting depth/normals/AO live, paired with `screenshot_viewport`. |

Render-graph capture (`capture_render_graph`, `list_render_passes`, `get_pass_output`,
`read_pass_pixel`, `scan_for_nans`) is gated on `Scene.debugAllowRenderGraphCapture`. It is a debug
opt-in, so a release build or a scene that never armed it returns nothing. The editor arms it for you;
outside the editor, set `Scene.debugAllowRenderGraphCapture = true` and call
`Scene.captureRenderGraph(...)` directly.

---

## Settle, do not seed

Frames differ from run to run for benign reasons. That is normal, not a bug to eliminate.

- **Auto-exposure** (`Scene.autoExposure`) ramps toward the target over `speedUp`/`speedDown` seconds,
  so the first second is darker or brighter than the settled image.
- **Particles and trails** carry a random phase, so a `ParticleSystem` looks different every launch.
- **Animations** are mid-clip unless you seek them, so a screenshot lands on an arbitrary frame.
- **Image-based lighting** re-bakes after the first present on some paths, so reflections dim in for
  a frame before they are correct.

So let the scene settle before you trust a capture. Watch until the image stops changing, or advance
a fixed few frames, then screenshot. Judge the settled frame, not the first one.

**Seeding is a different job.** Strict determinism (a fixed random seed, a pinned animation time, a
frozen exposure) is what you set up for pixel-exact regression comparison, where two runs must be
byte-identical. You do not need it for ordinary observation. For "does this change look right", settle
and look. Reserve the seeding work for when you are building a golden or diffing two runs at the pixel
level.

---

## Symptom to action map

Localize before editing. Each row says what to capture first and the mistakes it usually points back
to. The mistakes are detailed in the `flutter_scene-idioms` skill's `references/traps.md`; this map
routes a symptom to the right one.

### Entirely black frame

1. Read the console FIRST. If `Flutter Scene is not ready to render. Skipping frame.` is printing, it
   is the readiness gate, not your scene. Wait for `Scene.initializeStaticResources()`. Stop here.
2. In 0.22.0 a frame that issues zero draws prints once in debug naming the likely cause (not ready,
   empty region, no views, no visible meshes, or a layer mask matching nothing). Read that line.
3. If draws are happening but the image is black, `scan_for_nans`. A NaN or Inf anywhere upstream
   collapses the final image to black, and the scan names the first offending pass. Then
   `get_pass_output` on that pass's buffer (NaN shows magenta) to confirm.
4. Common non-NaN causes: a degenerate camera (target equals position, `up` parallel to the view
   direction on a top-down camera, FOV passed in degrees not radians), `layerMask: 0`, an oversized
   environment texture that failed to allocate on the device. See traps #23 and #16.

### Washed-out, low-contrast, or too-bright color

1. `screenshot_viewport` after settling, and check whether auto-exposure has finished ramping (a
   too-bright first second is just the ramp).
2. If it persists, suspect a shader-output contract break. A custom `ShaderMaterial`/`PostEffect`/sky
   shader must output linear HDR premultiplied by alpha. Tone-mapping or gamma-encoding in the shader
   gets applied a second time by the resolve pass, giving exactly this washed-out look. See traps #37
   and the root `MATERIALS.md`.
3. Also check for a non-color texture bound as color (a normal or metallic-roughness map without the
   right `TextureContent`), which reads wrong and distance-dependent. Trap #2.
4. Hand-packed vertex data at the wrong stride also washes out color (the color attribute lands at the
   wrong offset). `describe_scene` plus trap #17.

### See-through or inside-out faces

1. `set_viewport_debug_mode` to normals (or `get_pass_output` on the normals buffer) and look at the
   orientation. Inverted normals confirm a winding problem.
2. Cause is almost always clockwise hand-built triangles. flutter_scene front faces wind
   COUNTER-CLOCKWISE (CCW) in model space, matching glTF and standard conventions. Ensure triangle
   indices wind CCW around the outward face normal, or omit normals and let the constructor derive
   them. NEVER fix orientation with a per-triangle winding flip on an imported model; that leaves
   normals and IBL wrong. Traps #13 and #17.
3. For an imported model rendered mirrored, check you did not overwrite the runtime importer's
   `scale(1, 1, -1)` handedness root. Trap #5.

### Missing or popping geometry

1. `describe_scene` to confirm the node is actually in the graph. If it is absent, it is a scene-build
   bug, not a render bug.
2. If it is present but invisible, check the layer mask (`Node.layers` is a bitmask, NOT inherited,
   and must match the view's `layerMask`; `layers = 2` means `1 << 1`, not "layer 2"). Trap #10.
3. If it appears and disappears with camera angle, the bounds do not cover the geometry (a
   caller-supplied `bounds` or `setLocalBounds` that is too small, or a swapped primitive geometry on
   an older version). Widen or omit the bounds. Traps #8 and #24.
4. A moved skinned mesh that will not move is the skinned-node transform being ignored by design; move
   the skeleton root instead. Trap #4.

### A value looks numerically wrong (not visually)

Use `read_pass_pixel` on the relevant buffer to read the exact float RGBA at a coordinate, with NaN/Inf
flags. This settles "is this pixel actually 0.5, or is it NaN, or negative" without eyeballing a PNG
that the display remap has already clamped.

---

## Judgment, restated

The blind-pairwise rule from `SKILL.md` is the part most likely to be skipped, so it bears repeating
here. When you have a before and an after, put them side by side and pick the better one as a binary
A-or-B choice against a reference or the previous frame. Do not narrate a score. A solo score climbs
on its own because you are grading your own progress; a blind pick between two concrete frames does
not. Every visual review runs through a pairwise pick, including the ones that feel too obvious to
bother with.
