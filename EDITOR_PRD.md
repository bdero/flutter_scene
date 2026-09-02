# Flutter Scene Editor — Product Requirements

**Status:** Draft 1 · 2026-09-02
**Scope:** `flutter_scene_editor`, `flutter_scene_editor_core`, `flutter_scene_mcp`, `apps/flutter_scene_editor_app`, and the engine surfaces the editor has to expose
**Reference product:** PlayCanvas — [Editor](https://playcanvas.com/products/editor), [Engine](https://playcanvas.com/products/engine), [SuperSplat](https://playcanvas.com/products/supersplat), [Viewer](https://playcanvas.com/products/viewer)
**Sibling document:** `Orbis/PRD.md`. Orbis is a PlayCanvas fork rebuilt local-first; this repo is a Flutter-native engine that arrives at the same place from the other side. Where the two need the same subsystem — notably Build Settings — this document reuses Orbis §9.4's model and states where Flutter forces a different answer.

---

## 1. Thesis

> **The engine is not the gap. Getting in and getting out are.**

PlayCanvas's product is not its renderer. It is that a stranger can be looking at their own
model 90 seconds after opening the site, and can send someone a link to a running game one
click after that. Everything between those two moments — panels, gizmos, inspectors — every
serious editor has.

Flutter Scene already has the middle. §2 measures it: ten docked panels, gizmos, a command
palette, a visual scripter with blueprints-as-classes, an animator state graph, terrain
sculpt-and-paint, nav-mesh baking, VFX presets, an MCP tool surface for agent-driven editing.
The engine measurably matches or exceeds the PlayCanvas engine feature list (§3.1) — the
glTF extension set is *wider*, and gaussian splats, SSGI, PCSS, god rays and auto-exposure
are all already there.

What is missing is **the layout**, and the two ends.

**The layout is the main goal of this document.** The reference editor is four fixed regions,
a tool rail, one header shape and one row shape — and nothing else on screen. This editor is a
Unity-shaped dock: tab strips over every region, two stacked chrome bars above the viewport,
card radius and accent bars inside the panels, and a Scene view that competes with the Game
view for the same tab slot. Every individual piece of that was a reasonable decision; together
they spend the pixels and the attention the scene should have. §5.1 specifies the region map,
the panel grammar and the density rules that replace it, and how "exactly like" gets checked.

And the two ends:

| End | PlayCanvas | Flutter Scene today |
| --- | --- | --- |
| **Getting in** | Open a URL | Install Flutter, `flutter create`, `pub add`, `dart run flutter_scene:init`, remember `--enable-flutter-gpu`, then find a directory that already has a `pubspec.yaml` before the editor will call it a project |
| **Getting out** | One-click publish, CDN-hosted link | A free-form command template whose target platform is a side effect of which device happens to be plugged in, and five platform files that must be hand-edited or the shipped game renders nothing |

This document is about the layout first, then those two ends, then the handful of in-editor
moments where the absence of feedback (no play mode, no profiler, no asset library) makes a
capable editor feel unfinished.

**The positioning it should defend:**

> Everything PlayCanvas made easy, on a stack that does not need a browser, a cloud account,
> or a server round-trip to save a scene — and that ships to six platforms from one project.

### 1.1 What this document deliberately does not copy from PlayCanvas

Cloud is PlayCanvas's product, not its usability. Accounts, hosted project storage,
real-time multi-user collaboration, in-editor chat and a paid asset store are all §9 non-goals.
The friction they remove is friction this editor does not have, because the project is plain
files on the user's disk.

---

## 2. Where the editor actually is (2026-09-02)

Measured, not assumed.

| Package | Size | What it is |
| --- | --- | --- |
| `flutter_scene_editor` | 92 files, ~45,300 lines | The editor UI: shell, docking, panels, viewport, gizmos, inspector |
| `flutter_scene_editor_core` | 13 files, ~7,500 lines | Headless command/undo core. `builtin_commands.dart` alone is 4,270 lines |
| `flutter_scene_mcp` | ~1,800 lines | The agent tool surface |
| `apps/flutter_scene_editor_app` | 1,643 lines | The desktop shell: native windows, MCP server, packaging |

**Panels shipped** (`editorPanelTitles`, [editor_shell.dart:56](packages/flutter_scene_editor/lib/src/shell/editor_shell.dart#L56)):
Scene · Game · Hierarchy · Inspector · Project · Console · Animation · Visual Scripter ·
History · Render Graph.

**Shell surfaces:** drag-to-dock layout tree with named layouts and id migration
([dock_layout.dart](packages/flutter_scene_editor/lib/src/shell/dock_layout.dart)),
menu bar, centred transport row, one-line status bar, command palette, project launcher
gallery with cover art, settings dialog, scene-settings dialog, shader-toolchain manager,
multi-window scene views.

**Authoring surfaces:** transform gizmos, component gizmos, orientation gizmo, terrain sculpt
and splat paint, scatter tool, nav-mesh editor, material section with live preview and an
`.fmat` library, particle/VFX editing, weather and sky controls, water conversion in place,
blueprint editor screen, animator graph + timeline, canvas/UI anchoring in the viewport.

**Project surfaces:** `.fproject` with named build configurations and tasks, Flutter
installation management with health badges, device catalogue from `flutter devices --machine`,
a Build button, and a Play session that owns `flutter run --machine` end to end — structured
progress, hot reload, hot restart, stop, restart-on-save.

That is a serious editor. The gap list in §4 should be read against it: these are the missing
*ends*, not a missing middle.

### 2.1 The engine is not the gap — measured against the PlayCanvas engine page

| PlayCanvas engine claim | Flutter Scene | Evidence |
| --- | --- | --- |
| WebGL2 + WebGPU, compute | Flutter GPU (Impeller) native; built-in WebGL2 backend on web | `packages/flutter_scene/lib/gpu.dart` |
| Physically based rendering, IBL | ✅ | `EnvironmentMap`, `irradiance_pass.dart` |
| TAA, Bloom, DoF, SSAO, Vignette | ✅ and more — GTAO, SSR, SSGI, god rays, auto exposure, LUT grading, fog | `lib/src/post_process/`, `POST_PROCESSING.md` |
| Shader chunk system (GLSL/WGSL) | ✅ `.fmat` materials + `ShaderMaterial` | `MATERIALS.md` |
| 3D Gaussian splatting, GPU sort | ✅ | `lib/src/splats/gaussian_splats.dart` |
| Clustered + area lighting | ✅ (froxel clustering merged from upstream 2026-08-31) | `lib/src/render/` |
| PCF / VSM / PCSS shadows | ✅ PCSS + contact shadows | `lib/src/render/` |
| Cubemap prefiltering | ✅ | `irradiance_pass.dart` |
| SDF text | ⚠️ Text via `widget_texture` / UI layer, not SDF | `lib/src/ui/` |
| Spec-compliant glTF 2.0 + extensions | ✅ **wider** — 18 KHR extensions including draco, meshopt, quantization, basisu, variants, iridescence, anisotropy, dispersion | `lib/src/importer/src/gltf/extensions.dart` |
| Basis / KTX2 texture compression | ✅ | `inline_assets.dart` |
| GPU skinning, morph targets | ✅ | `lib/src/animation/` |
| Rigid body physics | ✅ two backends (Rapier, box3d) behind one contract | `package:scene/physics.dart` |
| GPU particles | ✅ plus collision, twelve VFX presets | `lib/src/particles/` |
| Positional 3D audio | ✅ two backends (SoLoud, FMOD) | `lib/audio.dart` |
| WebXR | ❌ none | — |
| Entity-component framework | ✅ | `lib/src/components/` |
| Asset streaming | ⚠️ partial | `lib/src/runtime_importer/` |

**One real engine gap (WebXR), one partial (SDF text).** Everything else on PlayCanvas's
engine page is already here. This is why the rest of this document is about the editor.

---

## 3. The usability bar — the PlayCanvas Editor feature map

Every capability claimed on the PlayCanvas Editor page, against what this editor does today.

| PlayCanvas Editor capability | Flutter Scene today | Verdict | Lands in |
| --- | --- | --- | --- |
| **Layout: four fixed regions, a tool rail, one header and one row shape** | Unity-shaped dock: tab strips, two chrome bars, card radius, no tool rail | ⚠️ **Partial — the main goal** | **§5.1** |
| Real-time collaboration (Google-Docs style) | — | ❌ **Non-goal** (§9) | — |
| In-editor chat | — | ❌ **Non-goal** | — |
| Team management / roles | — | ❌ **Non-goal** | — |
| Zero compile time, instant iteration | Hot reload/restart through the Play session, but the app is a separate process and there is no in-editor play | ⚠️ **Partial** | §5.3 |
| On-device development and testing | Device catalogue + `flutter run` to any attached device | ✅ **Have** — better than a browser | — |
| Hot reloading of code and assets | Code ✅ (session hot reload, restart-on-save); assets ⚠️ (no watch-and-reimport) | ⚠️ **Partial** | §5.4 |
| Multi-platform editor access | Desktop only (macOS/Windows/Linux) | ⚠️ **Deliberate** — desktop only, and exploit it | §9 |
| Debugging and profiling | Console panel with collapse/filter/detail; Game view Stats; `FLUTTER_SCENE_PROFILE` prints to stdout | ⚠️ **Partial** — no profiler surface | §5.6 |
| In-app visual profiler | — | ❌ **Missing** | §5.6 |
| Asset import (FBX/OBJ/glTF/GLB, HDR, audio) | glTF/GLB with an options dialog; HDR environments; no FBX, no OBJ, no audio import UI | ⚠️ **Partial** | §5.4 |
| Asset filtering / search over large collections | Project panel is a "read-and-drag-in first version" by its own docstring | ⚠️ **Partial** | §5.4 |
| Drag a file in from the desktop | No OS drop target anywhere in the editor | ❌ **Missing** | §5.4 |
| Asset store (free + premium content) | — (queued: a `flutter_scene_examples` repo the launcher can install from) | ❌ **Missing** | §5.7 |
| glTF / USDZ export | No export path of any kind | ❌ **Missing** | §5.7 |
| Mesh compression | Import-side ✅ (draco, meshopt, quantization); no compress-on-export | ⚠️ **Partial** | §5.7 |
| Material editor | ✅ Material section, live preview, `.fmat` library | ✅ **Have** | — |
| Sprite editor / atlases | Engine has `texture_atlas.dart` and `sprite.dart`; no editor surface | ❌ **Missing** | §5.4 |
| Visual UI editing (responsive in-game UI) | Canvas + anchor-based layout drawn in the viewport (landed as #57) | ⚠️ **In progress** | §5.8 |
| Animation state graph editor with layers | ✅ Full node-graph animator with layers and masks | ✅ **Have** | — |
| Cubemap prefiltering | ✅ | ✅ **Have** | — |
| One-click publish to the web | — | ❌ **Missing** | §5.2, §5.7 |
| App hosting on a CDN | — | ❌ **Non-goal** (local static output instead) | §5.7 |
| Version control with checkpoints | — (the project is plain files; bring your own git) | ❌ **Non-goal** (§9) | — |
| Templates / reusable entity hierarchies | ✅ Prefabs, drag-to-prefab extraction, blueprints as assets, four scene templates | ✅ **Have** | — |
| Entity-component framework | ✅ | ✅ **Have** | — |
| REST API for automation | — | ⚠️ Covered by MCP | §5.9 |
| Editor API for extensions | — (no public extension surface) | ❌ **Missing** | §5.9 |
| MCP server for AI agents | ✅ `flutter_scene_mcp`, ~1,800 lines of tool surface | ✅ **Have** — ahead | — |
| VS Code extension / assisted coding | — (the MCP server covers the same ground from any agent) | ⚠️ **Partial** | §5.9 |
| **Build Settings and shipping** *(not on their page — PlayCanvas only ships to the web)* | Free-form command template | ❌ **Missing** | **§5.2** |

Read down the verdict column: eight ❌ that matter, and six of the eight are the two ends
from §1.

---

## 4. The seven frictions that actually cost a user

Each of these is a specific, reproducible moment where a person who wants to make a game
stops and does something else.

### F0 — The chrome competes with the scene

Not a matter of taste, and measurable. Above the viewport sit two full-width strips (the menu
bar and the centred transport row, #32) plus a 30 px tab strip, before a single pixel of scene.
Every region is a tab group, so Scene and Game cannot both be visible, and opening the Console
hides the assets you were dragging from. Inside the panels, 8 px card radius, full borders and
accent-barred section headers make each block look like a separate object, which is exactly
what a dense property list must not look like. The reference spends none of this: one header
row, hairline rules, flat sections, and the viewport starts 24 px from the top. → §5.1

### F1 — First run costs a terminal, and the editor cannot help

"New Project…" opens a directory picker and writes a `.fproject` beside an existing
`pubspec.yaml`. If the directory has no `pubspec.yaml` it refuses:

> *"The directory has no pubspec.yaml; an fproject wraps an existing Flutter project."*
> — [fproject.dart:284](packages/flutter_scene_editor/lib/src/project/fproject.dart#L284)

So before the editor is usable at all, the user has to know to run `flutter create`,
`flutter pub add flutter_scene`, `dart run flutter_scene:init`, and `flutter create .
--platforms=…`. **The editor's first-run experience is a README.** → §5.5

### F2 — Play is somewhere else

Play launches `flutter run --machine` as a separate process and a separate window
([app_session.dart](packages/flutter_scene_editor/lib/src/project/app_session.dart)). It is
a genuinely good implementation — structured events, hot reload, restart-on-save — but it is
not play *mode*. Consequences already visible in the codebase: the Console panel's Error
Pause was deliberately omitted because "there is no in-editor play mode"; the Game view is a
camera preview and says so in its own docstring. Nothing in the editor ever *runs* the scene:
physics never steps, blueprints never tick, particles never simulate under the author's
hands. → §5.3

### F3 — You cannot ship, and the failure is silent

Three defects compound:

1. **There is no target platform.** The default build command is
   `${FLUTTER_CLI} build ${BUILD_TARGET} --${MODE}` where `${BUILD_TARGET}` is derived from
   *the selected device* ([device_catalog.dart](packages/flutter_scene_editor/lib/src/toolchains/device_catalog.dart)).
   Unplug the phone and you build something else.
2. **There is no scene list.** Nothing declares which scenes ship or which one boots.
3. 🔴 **The shipped game probably does not render.** Flutter GPU has to be enabled, and the
   run configuration's default args carry `--enable-flutter-gpu`
   ([fproject.dart:373](packages/flutter_scene_editor/lib/src/project/fproject.dart#L373))
   — but the *build* command template does not, and for a real build the switch lives in a
   platform file that nobody has edited: `Info.plist` on iOS/macOS, `AndroidManifest.xml` on
   Android, and a C/C++ edit in the runner on Windows and Linux, which additionally needs
   Flutter 3.47.1 (`packages/flutter_scene/README.md` §Enable Flutter GPU). A release build
   made from the editor today launches to a black screen and nothing explains why. → **§5.2**

### F4 — Assets are a file list, not a library

The Project panel scans the project root and lists files. There is no OS drag-and-drop target
(no drop package is a dependency), no type filter, no folder tree you can drop *into* (the
browser "has no current-folder notion" — a known gap from the drag-to-prefab work), no
thumbnail grid for textures or materials, and no import presets. PlayCanvas's asset panel is
the surface people spend the most time in; here it is the least finished. → §5.4

### F5 — Nothing tells you why it is slow

The engine has a profile mode (`--dart-define=FLUTTER_SCENE_PROFILE=true` prints 120-frame
render-graph, culling, encoding, binding, draw and instance summaries) and a
`memory_report.dart`. None of it has a surface. The editor's own performance skill says
"measure which thread is over" — and then gives you stdout. → §5.6

### F6 — There is nothing to show anyone

No export, no viewer, no shareable output. A person who finishes something has no artifact
smaller than "install Flutter and clone my repo". PlayCanvas's answer is a link; SuperSplat's
is an embeddable viewer; the Viewer is a URL you drop a `.glb` onto. → §5.7

---

## 5. Requirements

Requirement ids are `R<section>.<n>` and are referenced by the milestones in §7.

### 5.1 🔴 The layout — the complete working model

**The main goal of this document.** Not a skin over the current arrangement: the region map,
the panel grammar, the density, and the way the editor is *worked* — one selection, one place
each thing lives, and nothing on screen that is not either the scene or the thing you are
editing.

Three decisions were taken before this section was written, and they close what would
otherwise be its three biggest open questions:

| Decision | Choice | Consequence |
| --- | --- | --- |
| How literal | **The complete working model** — fixed regions, no docking, no tabs | The dock tree, tab strips, panel-visibility toggles and named layouts retire (§5.1.9) |
| Palette | **Keep the blue-violet surfaces and the amber editable-value convention** | The reference contributes *structure, density and flatness*, not colour. The 2026-08-30 visual pass survives |
| Top chrome | **One strip** | File / Edit / Add / View retire into the tool rail, the panel headers and the command palette (§5.1.7) |

#### 5.1.1 The region map

There is no global menu bar and no global toolbar. Every region carries its own 24 px header,
and those headers line up across the top of the window — which is most of why the reference
reads as clean at a glance: one horizontal line, not three stacked strips of chrome.

```
┌────┬──────────────┬────────────────────────────────┬──────────────┐
│ ⬢  │ HIERARCHY  ⊕ │ project ⌄  macOS ⌄  ⊞          │ INSPECTOR  ◂ │  ← headers align
├────┼──────────────┤          Perspective ⌄  ⚙ ⛶ ▸  ├──────────────┤
│ ▣  │ Search       ├────────────────────────────────┤   ⬤ preview  │
│ ↻  │ ▾ Root       │                                │ ─────────────│
│ ⤢  │   ▸ car      │                                │ id           │
│ ▧  │   ▸ ground   │           VIEWPORT             │ name         │
│ ◈  │     light    │                                │ ▾ MATERIAL   │
│    │              │                                │ ▸ DIFFUSE    │
│    │              │                                │ ▸ SPECULAR   │
│    │              ├────────────────────────────────┤ ▸ EMISSIVE   │
│ ?  │              │ ASSETS  ⊕ 🗑 ⇅ ▦   All ⌄  Search│ ▸ OPACITY    │
│ ⌨  │              ├──────────┬─────────────────────┤ ▸ NORMALS    │
│ ◇  │              │ ▾ /      │ ▦  ▦  ▦  ▦  ▦  ▦    │              │
│ ⚙  │              │   ▸ car  │ ▦  ▦  ▦  ▦  ▦  ▦    │              │
├────┴──────────────┴──────────┴─────────────────────┴──────────────┤
│ material.diffuse                                          0 tasks │  ← 20 px status bar
└───────────────────────────────────────────────────────────────────┘
```

| Region | Size | Behaviour |
| --- | --- | --- |
| **Tool rail** | 40 px fixed, full height | Never hidden, never resized. Tools top-aligned, utility bottom-aligned |
| **Hierarchy** | 220 px default, 180–420 drag range | Collapses to its 24 px header, which stays clickable |
| **Viewport** | Fills; 480 × 320 minimum | Its header *is* the window's top strip (§5.1.7) |
| **Assets shelf** | 260 px default, bottom of the **centre column only** | Under the viewport, not under the hierarchy. Collapsible |
| **Inspector** | 300 px default, 260–520 drag range | Collapsible; the ◂ in its header is the collapse control |
| **Status bar** | 20 px, full width | The focused property's path on the left, counters on the right |

- **R5.1.1** The four regions are fixed. Panels cannot be dragged, tabbed, floated or hidden individually; they resize and collapse, and that is all.
- **R5.1.2** The assets shelf sits under the viewport only. *(This reverses the arrangement adopted in #31, where the bottom shelf spanned the hierarchy as well. The hierarchy running full height is what keeps a deep tree usable while the shelf is open.)*
- **R5.1.3** Region sizes and collapse states persist per user, keyed by project — not in the project file.
- **R5.1.4** Every region header is 24 px and they align. Nothing sits above them but the window's own title bar.

#### 5.1.2 The tool rail

- **R5.1.5** A 40 px icon rail down the left, 28 px hit targets, tooltips carrying the keybinding. Exactly one tool is active at all times.
- **R5.1.6** Top group, in order: Select · Translate (W) · Rotate (E) · Scale (R) · a divider · Space toggle (world/local) · Snap · a divider · the mode tools this editor has and the reference does not — Terrain sculpt, Terrain paint, Scatter, Nav mesh, Canvas. Mode tools appear only when the selection or the scene admits them, rather than sitting dead.
- **R5.1.7** Bottom group: Help · Keyboard shortcuts · Agent/MCP status · Settings.
- **R5.1.8** The active tool shows an accent left bar and a filled icon — the same treatment the nav rail already uses in the launcher and the settings window, so the editor has one rail idiom rather than three.

#### 5.1.3 Panel grammar — the part that reads as "clean"

One header shape, one row shape, one section shape, everywhere. This is the section that most
of the visual work lands in, and it is mechanical.

| Element | Spec |
| --- | --- |
| **Panel header** | 24 px. A 6 px marker dot at the left, then the panel name — uppercase, 10.5 px, 0.09 em tracking, muted. Actions inline at the right as 20 px icon buttons. Collapse chevron last |
| **Section header** (inside a panel) | Uppercase 10.5 px with a ▸/▾ chevron at the **left**, flush to the panel edge, hairline rule beneath. No accent bar, no card |
| **Property row** | 22 px. Label column 96 px fixed, muted 11 px, left-aligned, **no colon**. Control column fills. 8 px side padding, 6 px gutter |
| **Icon button** | 20 px, no background until hover |
| **Radius** | **0 in docked chrome.** Controls keep 3 px. Dialogs keep their card radius |
| **Borders** | A single 1 px rule between regions. A panel never draws a box around itself |
| **Shadows** | None in docked chrome. Dialogs and popovers only |
| **Type ramp** | Four sizes and no others: 9 micro · 10.5 uppercase header · 11 label · 12 body |
| **Accent** | Selection blue, and amber for a value you can edit. No third accent anywhere in the chrome |
| **Scrollbars** | One per panel body, overlay, 6 px, visible on hover |

- **R5.1.9** `editorPanelBox` (8 px radius, full border) stops being used by docked chrome; it survives for dialogs only.
- **R5.1.10** `EditorSectionHeader`'s accent left bar is replaced by the chevron form above, in the inspector and in every dialog that borrowed it, so the two do not diverge.
- **R5.1.11** **A density audit runs in CI and fails the build** when docked chrome introduces a corner radius above 0, a shadow, a fifth type size, or a third accent colour. Cleanliness that is not enforced is cleanliness that lasts one feature branch.

#### 5.1.4 The inspector

- **R5.1.12** The inspector shows whatever is selected, entity **or asset**, with the type named in its header (ENTITY · MATERIAL · TEXTURE · SCENE · TERRAIN). Selecting a material in the assets shelf fills the inspector with that material — one selection model, two sources.
- **R5.1.13** Asset types lead with a preview: the material sphere, the texture, the environment. Entities lead with their identity block.
- **R5.1.14** Identity block first, always the same rows in the same order: id · name · tags · type · source · size, then the type's own actions.
- **R5.1.15** Then collapsible sections in a fixed per-type order, collapse state remembered per type rather than per object, so the section you work in is open on the next thing you select.
- **R5.1.16** A component is a section with an enable checkbox in its header and a ⋯ menu carrying remove / reset / copy / paste.
- **R5.1.17** A resource slot is one row shape everywhere: 28 px thumbnail · name · clear × · channel or UV dropdown. Textures, environments, materials, meshes and prefab references all use it.
- **R5.1.18** Mixed values across a multi-selection show a dash, and editing one applies to all.

#### 5.1.5 The hierarchy

- **R5.1.19** Header actions: ⊕ Add (the retired Add menu, in the place the reference puts it), Duplicate, Delete.
- **R5.1.20** A search field directly beneath the header, filtering the tree and keeping ancestors visible.
- **R5.1.21** 20 px rows: type icon, name, expand caret. Drag to reparent, shift/cmd multi-select, rename in place, and the same selection the viewport has.

#### 5.1.6 The assets shelf

- **R5.1.22** Two panes: a 180 px folder tree on the left, the contents on the right. The tree's selection is the current folder, which is what new assets, imports and drops land in — the "no current-folder notion" gap, closed by the layout rather than patched around.
- **R5.1.23** Header: ⊕ create/import · delete · sort · grid/list toggle · a type filter · search, then Library and settings at the far right.
- **R5.1.24** Grid tiles are 72 px with the name beneath and a type badge; the list form is the same data at 22 px rows.
- **R5.1.25** Console and Animation share the shelf, chosen from a compact segmented control at the right of the shelf header — not a dock tab strip, and never more than one visible.

#### 5.1.7 The top strip and what the menus become

One 32 px strip, and it belongs to the viewport rather than to the window.

| Position | Contents |
| --- | --- |
| Left | Project name ⌄ (the retired **File** menu: new, open, save, import, project settings) · build target ⌄ (where the reference puts the branch — §5.2 owns it) · a panels ⌄ menu for the two collapsible regions |
| Centre | **Nothing.** The strip's middle stays empty and is the window-drag region. Help and command search live in the palette (⌘P) and the rail's Help button; the transport moved to the right cluster, so nothing needs the middle |
| Right | Camera mode ⌄ (Perspective · Top · Front · Side · the scene's cameras) · render settings ⚙ · maximise ⛶ · **▸ Play** |

- **R5.1.26** **Edit** retires entirely into keybindings and the command palette; **View** retires into the panels menu and the rail; **Add** moves to the hierarchy's ⊕.
- **R5.1.27** Scene and Game stop being two panels: they are two modes of one viewport, toggled in the camera dropdown. The Game mode keeps its aspect list and stats readout.
- **R5.1.28** The reference's chat-and-avatar cluster at the viewport's bottom-left becomes the **agent presence** chip: which MCP clients are attached to this scene and what they last did. It is the same slot answering the same question — who else is working in here.
- **R5.1.29** The status bar's left half shows the focused property's path (`material.diffuse`), which is also what the copy-property and MCP-address actions use. Its right half keeps the existing single-line message contract: an error outranks anything newer, and clicking raises the console.

#### 5.1.8 Editors you enter, rather than panels you tab to

The reference has no dock because its heavier tools are *screens*. This editor already agrees
with that — `dock_layout.dart` says so about the visual scripter in its own comment — and this
makes it uniform.

| Tool | Today | Becomes |
| --- | --- | --- |
| Visual Scripter | Dock panel | Full-screen editor entered from a blueprint, left with Esc |
| Animator graph | Side panel | Full-screen editor entered from an animator asset |
| Blueprint editor | Already a screen | Unchanged — it is the model |
| Render Graph | Dock panel | Full-screen diagnostic screen (§5.6) |
| History | Dock panel | Popover from the status bar |
| Console · Animation timeline | Dock panels | Shelf modes (R5.1.25) |

- **R5.1.30** Entering an editor keeps the rail and the top strip, replaces everything else, and shows what you are editing in the strip's left slot. Esc always leaves.

#### 5.1.9 What is deleted

Stated plainly, because it is a deletion and someone will miss it.

- Drag-to-dock, `DockZone`, tab groups and tab context menus.
- Named layouts, Save Current Layout, Manage Layouts, Reset Layout, and the View menu's panel checkmarks.
- Per-panel visibility toggles.
- The menu bar and the separate centred transport row (#32) — the transport moves into the top strip's right cluster.
- Extra scene views and floating panel windows. *(The multi-window machinery in the app shell stays: it is what the full-screen editors and dialogs use.)*

- **R5.1.31** `renamedPanelIds` is not deleted — its own rule is that entries are never removed — but it stops being consulted once layouts are no longer persisted. Saved layouts are dropped with a one-line release note; they were per-user state.
- **R5.1.32** The net change is a deletion: `dock_layout.dart` (437 lines) and most of `docking_shell.dart` (657) retire, against a region scaffold that should not exceed 300. `editor_shell.dart` gives up its menu bar, its layout manager and its panel bookkeeping.

#### 5.1.10 How "exactly like" is checked

- **R5.1.33** A reference comparison lives in the repository: the editor at 1440 × 900 beside the reference screenshot at the same size, with the region boundaries annotated. Every boundary within **8 px**, no tabs, no radius in docked chrome.
- **R5.1.34** Golden widget tests for the four headers, the property row, the section header and the resource slot, so the grammar cannot drift one panel at a time.
- **R5.1.35** The density audit of R5.1.11 runs on every commit.

---

### 5.2 🔴 Build Settings — the window

The largest single requirement in this document, and the one the user named directly. The
reference shape is the Build Settings window in the attached screenshot: a scene list on top,
a platform list bottom-left, per-target options bottom-right, and the buttons that switch
target and build. That shape is right and well understood; the requirements below adopt it
and state where Flutter differs.

**In one line:** a person picks a platform, presses Build, and gets a playable artifact for
that platform that renders correctly and contains no part of the editor.

#### 5.2.1 The surface

| Element | Behaviour | Notes against the reference |
| --- | --- | --- |
| **Scenes In Build** | Ordered list of `.fscene` paths with checkboxes and drag-reorder; index 0 is the boot scene; unchecked scenes are excluded from the bundle. Add Open Scenes button. | Same model. The list lives in `.fproject` (§5.2.2), reviewable in `git diff` |
| **Platform list** | Web · macOS · Windows · Linux · Android · iOS — six, all real | No greyed-out modules to install. A platform the project has not scaffolded shows **Add Platform** (§5.2.4), not a dead row |
| **Target platform / architecture** | Android `arm64-v8a`/`armeabi-v7a`/`x86_64`; macOS universal; Windows `x64`/`arm64`; iOS device/simulator; Web `js`/`wasm` + renderer | Web's "architecture" is the compile target, which the reference has no equivalent for |
| **Build mode** | Debug · Profile · Release, mapped to `flutter build --debug/--profile/--release` (§5.2.6) | "Development Build" and "Deep Profiling" collapse into Flutter's three modes |
| **🔴 Flutter GPU** | A status row per platform: enabled ✓ / **not enabled ✗ with a Fix button** that patches the platform file, and a version warning where the platform needs 3.47.1 | **New, and the most valuable row in the window.** F3 is the single most expensive silent failure in the product |
| **Compression / size** | `--tree-shake-icons`, split-debug-info, obfuscation, per-target asset codec | Same |
| **Player settings** | App name, bundle/application id, version+build number, icon, orientation, min SDK | The reference calls this a separate window; here it is a tab in the same one — six targets do not justify two windows |
| **Switch Platform** | Changes the active target and the Game view's aspect/tier preview. **Near-instant** for an already-scaffolded target (§5.2.4) | Cheap by construction here: switching does not reimport, because the `.fscene` bundle is not per-platform |
| **Build** / **Build and Run** | Emit to `build/<target>/`; Run launches the artifact (on device for mobile, a local static server for web) | Same |

- **R5.2.1** The window opens from File ▸ Build Settings…, from the toolbar's Build split-button, and from the command palette.
- **R5.2.2** Every disabled control in the window states its reason on hover, matching the existing toolbar convention ("buttons disable with an explanatory tooltip rather than a bare gray state" — [build_toolbar.dart](packages/flutter_scene_editor/lib/src/project/build_toolbar.dart)).
- **R5.2.3** The window is fully driveable from MCP (`get_build_settings`, `set_build_target`, `build_project`), because agents ship builds too (§5.9).

#### 5.2.2 Where build state lives — project vs user

This split is deliberate, and it is the correction Orbis §9.4.2 makes to the reference
behaviour. It applies unchanged here.

| State | Lives in | Committed | Why |
| --- | --- | --- | --- |
| `build.targets` — platforms this project supports | `.fproject` | ✅ | A property of the game |
| `build.scenes` — ordered scene list, index 0 boots | `.fproject` | ✅ | Content, not preference. Must be reviewable in a diff |
| Per-target options — architecture, mode defaults, compression, bundle id, version, icon path | `.fproject` under `build.<target>` | ✅ | Two people building Android should get the same `.apk` |
| **`activeTarget`** — what I am building right now | editor settings, keyed by project path | ❌ | **The important one.** A per-user working preference, exactly like the selected device and the last-opened scene already are today |
| Signing identities, keystore passwords, API tokens | OS keychain | ❌ never | A credential in a project file is a credential in the git history |

- **R5.2.4** `.fproject` gains a `build` key at `currentVersion: 3`, with a migration from v2 that synthesises `build.targets` from the existing configurations and leaves `build.scenes` empty (an empty list means "every scene under the project root", so no existing project breaks).
- **R5.2.5** Build configurations (§ the existing `BuildConfiguration` list) are **not** replaced. They stay as the escape hatch for free-form commands and tasks; Build Settings is the structured path, and the two share `${...}` variable substitution.

```jsonc
// .fproject, v3
"build": {
  "targets": ["web", "macos", "android"],
  "scenes": ["scenes/main.fscene", "scenes/level-2.fscene"],
  "macos":   { "arch": "universal" },
  "android": { "arch": "arm64-v8a", "minSdk": 26, "applicationId": "dev.example.mygame" },
  "web":     { "compile": "wasm", "base": "/" }
}
```

#### 5.2.3 What "Scenes In Build" means here

Flutter has no scene concept; this has to be built, and it is what makes the list more than
decoration.

- **R5.2.6** A build generates a scene catalogue into the project's `flutter_scene_generated/` directory: an ordered `const List<String>` of asset keys plus `bootScene`, exposed as `SceneCatalog.scenes` / `SceneCatalog.boot`.
- **R5.2.7** The build writes exactly the listed scenes and their transitively referenced resources into the app bundle, and declares them in `pubspec.yaml`'s asset list. A scene not in the list is not shipped, and this is verified by a bundle-content assertion, not by convention.
- **R5.2.8** `loadScene(SceneCatalog.boot)` in a template `main.dart` is what a new project ships with (§5.5), so the list is live from the first build.

#### 5.2.4 Switching platforms must be cheap, and adding one must be one click

- **R5.2.9** Switching to an already-scaffolded target is **interactive** — no progress bar, no project reload. It changes editor state only.
- **R5.2.10** Selecting a target the project has not scaffolded offers **Add Platform**, which runs `flutter create . --platforms=<target>` in the project root with the project's organisation and name, streams into the Console, and applies the §5.2.5 Flutter GPU patch for that platform on completion.
- **R5.2.11** After Add Platform, the editor re-reads the device catalogue rather than making the user hit refresh.

#### 5.2.5 🔴 Flutter GPU enablement is the editor's job, not the user's

The single highest-value requirement in this document, because it converts a black screen
into a checkbox.

- **R5.2.12** For each scaffolded platform the editor reports whether Flutter GPU is enabled by reading the platform file, and offers a Fix that writes it:

  | Target | File | What is written |
  | --- | --- | --- |
  | iOS | `ios/Runner/Info.plist` | `FLTEnableFlutterGPU` = `true` |
  | macOS | `macos/Runner/Info.plist` | `FLTEnableFlutterGPU` = `true` |
  | Android | `android/app/src/main/AndroidManifest.xml` | `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true"/>` inside `<application>` |
  | Windows | `windows/runner/main.cpp` | `project.set_enable_flutter_gpu(true);` |
  | Linux | `linux/runner/my_application.cc` | `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` |
  | Web | — | Nothing; the WebGL2 backend needs no flag |

- **R5.2.13** Windows and Linux additionally require Flutter 3.47.1 for a *release* build. Where the selected installation is older, the row states that, and Build refuses with that reason rather than producing a broken artifact.
- **R5.2.14** A patch is idempotent, is shown as a diff before it is applied, and is skipped with a note where the file has been edited by hand into an equivalent state.

#### 5.2.6 Build modes

| Build Settings mode | Flutter | Ships |
| --- | --- | --- |
| Release *(default)* | `flutter build <target> --release` | AOT, asserts stripped |
| Profile | `--profile` | VM service open, timeline on; the mode the performance skill requires for any number to count |
| Debug | `--debug` | JIT, asserts, hot reload |

- **R5.2.15** Profile builds pass `--dart-define=FLUTTER_SCENE_PROFILE=true` when "Engine counters" is checked, wiring the existing 120-frame summaries into the shipped build and into the profiler panel (§5.6).

#### 5.2.7 🔴 The editor boundary — no shipped game contains the editor

The requirement Orbis §9.4.3 states, and it is *sharper* here: the editor is a Flutter app in
the same pub workspace as the engine, resolving by path. A stray import from a game's
`main.dart` to `package:flutter_scene_editor` compiles and runs. Nothing visibly breaks; the
game just ships an entire editor.

- **R5.2.16** A build fails if the built entrypoint's resolved package graph contains `flutter_scene_editor`, `flutter_scene_editor_core`, `flutter_scene_mcp`, or `flutter_scene_codegen` (build-time only). The check reads the package graph, names the import that caused the leak, and is a **build failure, never a warning**.
- **R5.2.17** A per-target bundle-size budget is recorded on each successful build and a step change fails the next one. A leak shows up as size before it shows up any other way.
- **R5.2.18** Both checks run in CI on every target. A guarantee that is not tested is not a guarantee.

#### 5.2.8 Output layouts

| Target | Output |
| --- | --- |
| Web | `build/web/` static directory, servable as-is; optional local preview server |
| macOS | `.app` (universal by default) |
| Windows | `.exe` + data directory |
| Linux | Bundle directory |
| Android | `.apk` or `.aab`, chosen in the target options |
| iOS | `.ipa`, or an Xcode archive where signing is unconfigured |

#### 5.2.9 Not in v1

Build profiles, per-platform Dart define sets, addressable/asset-bundle groups, cloud build,
store submission. All additive; none change the `.fproject` shape.

---

### 5.3 Play in the editor

The answer to F2 and to PlayCanvas's "zero compile time" claim. Two distinct things, and the
distinction must survive into the UI:

| | **Play** (new) | **Launch** (exists) |
| --- | --- | --- |
| What runs | The open scene, simulated in the editor's own process | The real app, `flutter run --machine` |
| Starts in | < 300 ms | Seconds to minutes |
| Good for | Does the door open? does the enemy path? does the effect read? | Is it actually shipped and correct on this device? |

- **R5.3.1** A Play/Pause/Step transport in the Scene view runs the scene: components tick, physics steps, blueprints run construction→start→tick, animators advance, particles simulate, audio plays.
- **R5.3.2** **Stop restores the scene exactly.** Play mutates a copy; the document is untouched. This is non-negotiable — the reference editors' worst-known behaviour is losing work edited during play, and the command core already has the primitives to avoid it.
- **R5.3.3** Editing during play is allowed and is discarded on stop, with a persistent, unmissable indication that play mode is active (a viewport tint, as the reference does, plus the status bar).
- **R5.3.4** The Game view renders through the playing camera while play is active, and input routes to the game rather than the editor.
- **R5.3.5** Error Pause returns to the Console panel — deliberately omitted before for lack of a play mode, and worth having the moment one exists.
- **R5.3.6** MCP gains `play`, `pause`, `step`, `stop` so an agent can drive the verification loop without launching a process.

### 5.4 The asset library

The shelf's *shape* — two panes, the folder tree, the grid, the header actions — is §5.1.6.
This is what it has to do.

- **R5.4.1** **Drag from the OS into the editor.** Dropping a `.glb`, `.gltf`, image, HDR, audio file, or `.fscene` onto the Project panel imports it into the hovered folder; dropping onto the viewport imports it and places it where it lands.
- **R5.4.2** The Project panel gets a **folder tree plus a content grid** with thumbnails for models, textures, materials, environments and scenes — the environment thumbnail service already exists and generalises.
- **R5.4.3** Type filters and a search box that filters across the whole project, not the current folder.
- **R5.4.4** A current-folder notion, so drops, new-asset actions and drag-to-prefab extraction land somewhere the user chose. (Named as a known gap in the drag-to-prefab work; this is where it gets fixed.)
- **R5.4.5** Import presets per asset type, editable in an inspector when the asset is selected, with a **Reimport** that re-runs the pipeline — the glTF import options dialog becomes a persisted per-asset setting rather than a one-time modal.
- **R5.4.6** File-watch the project root: an asset changed on disk by another tool reimports and updates the open scene without a reload.
- **R5.4.7** "Used by" for every asset, and an unused-asset report. The embedded-resource half of this already exists in the panel; extend it to files.
- **R5.4.8** A sprite/atlas editor surface over the existing `texture_atlas.dart` and `sprite.dart`, sufficient for 2D UI and billboard work.

### 5.5 First run: download to a spinning cube, without a terminal

The F1 answer, and the requirement that decides whether anyone gets as far as the rest of
this document.

- **R5.5.1** **New Project scaffolds a project.** A wizard: name, location, organisation, template, platforms. It runs `flutter create`, adds `flutter_scene` (plus the chosen physics/audio backends), runs the equivalent of `dart run flutter_scene:init`, applies the §5.2.5 Flutter GPU patches for the chosen platforms, writes a `main.dart` that loads `SceneCatalog.boot`, writes the `.fproject` with `build.scenes`, and opens the template scene. All of it streamed into the Console, with a failure naming the step.
- **R5.5.2** Templates are the four existing scene templates plus a **project** template layer (Empty, Third-person, First-person, Mobile with on-screen controls, Splat viewer) — the showcase list already queued as roadmap item 12.
- **R5.5.3** A **toolchain doctor** on first launch: is there a Flutter installation, is it ≥3.47 stable, is `impellerc` reachable, does the GPU support what the engine needs. Each failure states the fix and offers to perform it where it can (the managed-checkout machinery already exists).
- **R5.5.4** Opening a directory that has a `pubspec.yaml` but no flutter_scene offers to add it, rather than refusing. Opening one with no `pubspec.yaml` offers to create a project there.
- **R5.5.5** A samples gallery in the launcher, installing from the `flutter_scene_examples` repository — the entry point for roadmap item 12, and the fastest path from "installed" to "something moving on screen".
- **R5.5.6 (budget)** From a fresh install of the editor with Flutter present: **under five minutes and zero terminal commands** to a running scene on the local desktop.

### 5.6 Diagnostics: the profiler, and the honest error

- **R5.6.1** A **Profiler panel**: frame time split by CPU/GPU/raster, draw calls, triangles, instance count, render-target memory, and the per-pass render-graph timings the engine already computes for `FLUTTER_SCENE_PROFILE`. Live during Play (§5.3) and attachable to a Launch session over the existing VM service link.
- **R5.6.2** A Stats overlay in the Scene and Game views (the Game view's readout, generalised and always available).
- **R5.6.3** Memory report surfaced from `memory_report.dart`: textures, geometry, render targets, with the biggest offenders sorted.
- **R5.6.4** Shader/material compile failures surface as a Console error with the `.fmat` path and the compiler's message, and mark the material in the inspector — today a failed `.fmat` compile is a mystery at the point it matters.
- **R5.6.5** The status bar's single line and the Console keep their current contract (an error outranks anything newer; click raises the Console); the profiler never posts to either.

### 5.7 Getting it out

- **R5.7.1** **Web publish**: Build ▸ Web produces `build/web/` and offers *Preview* (serve locally, open a browser) and *Reveal* (open the folder). No hosting, no accounts — the output is a directory the user can put anywhere.
- **R5.7.2** **glTF/GLB export** of a selection or a whole scene, with draco/meshopt compression options — the importer's extension support means the round trip is mostly write-side work, and it is the single most requested interop direction.
- **R5.7.3** **A viewer**: a small, shipped application (and a `--viewer` mode of the editor) that opens a `.glb`, `.fscene` or `.ply` passed on the command line or dropped on it, with the hierarchy tree, material/texture/geometry metadata, morph-target browsing, render-mode switching, and wireframe/normals/bounds/skeleton debug draw. The SceneView, picker and inspector already exist; this is an assembly, not a build.
- **R5.7.4** **Splat tooling**, scoped honestly against SuperSplat: the engine already renders and GPU-sorts gaussian splats. v1 is *selection and cleanup* — rect/lasso/sphere selection, delete, transform, and export to `.ply` — not a full splat studio.
- **R5.7.5** Asset sync from a git repository or the examples repo (roadmap item 12), which is also how §5.5's samples gallery is populated.

### 5.8 The interaction rules the whole editor obeys

These are already the house style in places; this makes them requirements so new surfaces
inherit them rather than re-deciding.

- **R5.8.1** Every disabled control explains itself on hover. No bare grey.
- **R5.8.2** Every destructive action is undoable through the existing history, or asks first. Nothing is cleaned up silently on save.
- **R5.8.3** Every empty state teaches: what this panel is for, and the one action that fills it.
- **R5.8.4** One selection model across Hierarchy, Scene, Project and Inspector; selecting in one selects in all.
- **R5.8.5** Every command reachable from the palette, and the palette lists the keybinding.
- **R5.8.6** A single keyboard map, user-editable, shown in a cheat sheet — and matched to the reference editors' defaults wherever there is a convention (Q/W/E/R tools, F to frame, Ctrl/Cmd+P palette).
- **R5.8.7** Progress for anything over 500 ms, cancellable where the underlying process can be killed.
- **R5.8.8** The UI editing surface (canvas + anchors, landed as #57) reaches parity with the reference "visual UI editing" claim: drag-resize with anchor handles, a UI-only view mode, and preview at a chosen resolution.

### 5.9 Automation surface

- **R5.9.1** MCP tool parity with every new surface in this document: build settings, play mode, asset import, profiler capture. The rule is that any button an agent might need is also a tool.
- **R5.9.2** A headless CLI (`flutter_scene_editor build --target=web`, `--scene=…`) sharing the §5.2 implementation, so CI builds what the editor builds.
- **R5.9.3** A documented editor extension point — a package can contribute an inspector section for its own components. `flutter_scene_rapier` and the audio backends are the first consumers and the test of whether the API is real.

---

## 6. Budgets

Numbers, so the requirements are checkable. A miss is a bug, not a preference.

| Metric | Budget |
| --- | --- |
| Fresh install → running scene, no terminal (R5.5.6) | **< 5 min** |
| Editor cold start to launcher | < 2 s |
| Open a project and render its scene | < 3 s |
| Enter Play (R5.3.1) | < 300 ms |
| Switch build target, already scaffolded (R5.2.9) | < 250 ms, no progress bar |
| Add Platform (`flutter create`) | Streamed, cancellable; no frozen UI |
| Import a 10 MB `.glb` from a drop to visible in the scene | < 3 s |
| Asset thumbnail grid, 1,000 assets, scroll | 60 fps |
| Undo/redo of any single edit | < 50 ms |
| Editor idle frame cost with the viewport visible | < 4 ms CPU |

---

## 7. Milestones

Each has a binary exit criterion. Ordered by how much they unblock, not by size.

**E0 — 🎯 The layout** *(R5.1.1–R5.1.35)*
The region map, the tool rail, the panel grammar, the inspector and hierarchy and assets
rewrites, the single top strip, the full-screen editors, and the deletion of the dock.
**Exit:** the editor at 1440 × 900 sits beside the reference screenshot with **every region
boundary within 8 px**, no tabs anywhere, no corner radius in docked chrome, the density audit
green in CI, and the golden tests for the six repeated shapes passing.

> The main goal, and the milestone every later one inherits: each new surface in E1–E7 is
> built on the grammar this establishes, so it lands here or it lands twice.

**E1 — Ship what you make** *(R5.2.1–R5.2.18)*
The Build Settings window, `.fproject` v3, the scene catalogue, Add Platform, the Flutter GPU
enablement rows, the editor-boundary checks. Web and macOS targets end to end.
**Exit:** from a clean checkout of a project, a person who has never used a terminal produces
a macOS `.app` and a `build/web/` directory that both **render the scene**, and a deliberately
introduced `import 'package:flutter_scene_editor/…'` in the game's `main.dart` **fails the
build** naming that import.

> Highest-value milestone in the document. It closes F3, which is the one failure that
> silently wastes a whole evening.

**E2 — Get in without a terminal** *(R5.5.1–R5.5.6)*
New Project wizard, toolchain doctor, project templates, samples gallery.
**Exit:** a stopwatch from launching the editor on a machine with Flutter installed to a
spinning cube on screen reads **under five minutes**, with no terminal window opened.

**E3 — Play** *(R5.3.1–R5.3.6)*
In-editor play mode, restore-on-stop, Error Pause, MCP transport.
**Exit:** press Play, a physics body falls and a blueprint ticks; press Stop and the document
is byte-identical to before Play.

**E4 — The asset library** *(R5.4.1–R5.4.8)*
OS drop, folder tree + thumbnail grid, filters, current folder, import presets, reimport,
file watch, used-by.
**Exit:** a `.glb` dragged from Finder into a chosen folder appears with a thumbnail, drops
into the scene correctly lit and textured, and reimports on an external edit — inside the
§6 budgets.

**E5 — Say why it's slow** *(R5.6.1–R5.6.5)*
Profiler panel, stats overlay, memory report, shader errors that name the file.
**Exit:** a scene deliberately made slow four different ways (draw calls, overdraw, shadow
resolution, texture memory) is correctly diagnosed from the panel alone.

**E6 — Get it out** *(R5.7.1–R5.7.5)*
Web preview, glTF export, the viewer, splat selection and cleanup, examples sync.
**Exit:** a scene exports to `.glb`, reopens in the viewer and in a third-party tool with
materials intact; a `build/web/` directory runs from a static server.

**E7 — Polish and parity** *(R5.8.x, R5.9.x, mobile/Windows/Linux targets)*
The interaction rules audited across every panel, keyboard map, extension point, CLI, and the
remaining four build targets.
**Exit:** the §3 table has no ❌ outside the §9 non-goals, and every §6 budget is green in CI.

---

## 8. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| **Play mode leaks into the document** | 🔴 High | R5.3.2 is a hard requirement with a test: play, edit, stop, byte-compare. Build it as copy-on-play from the start; retrofitting isolation is where every engine that got this wrong got it wrong |
| **The editor leaks into shipped games** | 🔴 High | R5.2.16 package-graph check + R5.2.17 size budget, both in CI, landing **with the first build target** |
| **Flutter GPU enablement drifts** as Flutter changes the mechanism | Medium | Keep the file/key table in one place shared with the README; the doctor reads and reports rather than assuming |
| **Windows/Linux release needs 3.47.1** | Medium | R5.2.13 refuses with a reason; the pin is already `flutter.version` |
| `flutter create` **overwrites a hand-edited runner** | Medium | Add Platform shows what it will write, never re-runs on an existing platform directory without confirmation |
| **Six targets, one machine** — you cannot test what you cannot build on | Medium | Codemagic already builds macOS; extend per target rather than claiming untested platforms |
| **The layout rewrite touches every panel at once** | 🔴 High | It is mostly deletion (R5.1.32) and one grammar applied repeatedly. Land the region scaffold and the six repeated shapes first, then move panels into them one per branch — the golden tests are what make that safe |
| **Deleting the dock removes something someone uses** | Medium | Named layouts and floating panels are per-user conveniences with no project state behind them; the full-screen editors (§5.1.8) cover the case they were actually serving |
| **Scope**: this document is eight milestones deep for a solo developer | 🔴 High | E0 is the main goal and stands alone. E1 and E2 are the product's difference. E3–E7 are separable and independently valuable |
| **`editor_shell.dart` is 2,104 lines and every branch touches it** | Medium | E0 is where that is paid down: the shell becomes a region scaffold and gives up the menu bar, the layout manager and the panel bookkeeping |
| **The launcher/wizard becomes a second source of truth for project layout** | Medium | The wizard shells the real tools (`flutter create`, `pub add`, `flutter_scene:init`) rather than reimplementing them |

---

## 9. Non-goals

- ❌ **Accounts, cloud projects, hosted storage** — the project is files on disk. This is the thesis.
- ❌ **Real-time multi-user collaboration and in-editor chat** — the collaboration story is git.
- ❌ **In-editor version control** — no checkpoint/branch/merge/diff UI. Bring your own.
- ❌ **A paid asset store** — a git-backed examples/asset sync (R5.7.5), not a marketplace.
- ❌ **A browser-based or mobile editor** — desktop only, and exploit it (real filesystem, real GPU, a keyboard).
- ❌ **CDN hosting** — the web build is a directory; where it goes is the user's choice.
- ❌ **FBX import** — glTF is the interchange format; FBX is a licensing and complexity problem out of proportion to its value here.
- ❌ **A full splat studio** — selection, cleanup and export only (R5.7.4).
- ❌ **Replacing the existing build configurations** — they remain the free-form escape hatch (R5.2.5).
- ❌ **WebXR** — no target platform needs it.

---

## 10. Open decisions

**Settled 2026-09-02, and recorded here because §5.1 is built on them:** the layout copies the
**complete working model** (fixed regions, no dock, no tabs); the **blue-violet palette and the
amber editable-value convention stay**, with the reference contributing structure, density and
flatness only; and the top chrome collapses to **one strip**, with File/Edit/Add/View retiring
into the rail, the panel headers and the command palette.

1. **Where the retired File menu's long tail goes.** New/open/save/import/project settings fit the project dropdown; scene settings, build configurations, shader toolchain and managed checkouts are more than a dropdown wants. Recommendation: one Project Settings screen (§5.1.8's pattern), reached from the dropdown and the palette.
2. **Boot model.** Does a shipped game get a generated `main.dart` that reads the scene catalogue (opinionated, and makes Scenes In Build meaningful immediately), or does the catalogue stay a library the user calls themselves? Recommendation: generate it for new projects, library-only for existing ones.
3. **Play mode fidelity.** Full simulation in the editor process, or is a subset (no audio, no networking) acceptable for v1? Recommendation: subset, stated in the UI, with the boundary written down rather than discovered.
4. **Viewer packaging** (R5.7.3): a separate small app, or a mode of the editor? A separate app is the shareable thing; a mode is a week of work instead of a month.
5. **Where the profiler reads from during Launch** — the existing VM service link, or a socket the engine opens in profile builds? The first is free and weaker; the second is a protocol to maintain.
6. **Does E1 ship all six targets or two?** This document assumes web + macOS at E1 and the rest at E7. Android is arguably the more motivating second target than macOS.
7. **Sequencing against the queue.** Roadmap items still open (Cinemachine live/solo indicators, the sequencer/NLA, terrain holes/trees/details, networking host-join UI, Commands/RPCs as graph nodes) are authoring depth; this document is reach. Recommendation: E1 and E2 first regardless, because they change who can use everything else.

---

## Appendix A — Evidence map

| Claim | Where to check |
| --- | --- |
| Ten panels, docking, layouts | [editor_shell.dart:56](packages/flutter_scene_editor/lib/src/shell/editor_shell.dart#L56), [dock_layout.dart](packages/flutter_scene_editor/lib/src/shell/dock_layout.dart) |
| Play launches a separate process | [app_session.dart](packages/flutter_scene_editor/lib/src/project/app_session.dart) |
| Game view is a preview, not the game | [game_view_panel.dart](packages/flutter_scene_editor/lib/src/panels/game_view_panel.dart) |
| Build target comes from the selected device | [device_catalog.dart](packages/flutter_scene_editor/lib/src/toolchains/device_catalog.dart), [fproject.dart:371](packages/flutter_scene_editor/lib/src/project/fproject.dart#L371) |
| New Project requires an existing `pubspec.yaml` | [fproject.dart:284](packages/flutter_scene_editor/lib/src/project/fproject.dart#L284), [main.dart:611](apps/flutter_scene_editor_app/lib/main.dart#L611) |
| Flutter GPU needs a per-platform file edit | `packages/flutter_scene/README.md` § Enable Flutter GPU |
| Asset panel is a first version | [asset_browser_panel.dart](packages/flutter_scene_editor/lib/src/panels/asset_browser_panel.dart) header |
| No OS drag-and-drop dependency | `packages/flutter_scene_editor/pubspec.yaml` |
| glTF extension coverage | `packages/flutter_scene/lib/src/importer/src/gltf/extensions.dart` |
| Engine profile counters exist | `--dart-define=FLUTTER_SCENE_PROFILE=true`, `packages/flutter_scene/README.md` |
| MCP tool surface | `packages/flutter_scene_mcp/lib/src/tool_surface.dart` |
