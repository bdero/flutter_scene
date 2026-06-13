# Phase 2 notes

Status: active. Implementation of the editor shell and interactive viewport on
top of the Phase 1 headless core.

## What works

- **Viewport panel** (`lib/src/viewport/viewport_panel.dart`): SceneView with
  OrbitCamera (orbit/pan/zoom), tap-to-select via `Scene.raycast` + `nodeFsceneId`,
  translate gizmo (X/Y/Z axis handles). Gizmo drag previews via
  `controller.previewLocalTransform` and commits one `setNodeTransform` command
  on pointer-up (whole drag = one undo step). Camera locked during gizmo drag
  via `isLocked` callback. Rebuild isolation preserved from spike 0.1 contract:
  viewport repaints only on `_viewEpoch` bump, never via whole-app setState.

- **Docking shell** (`lib/src/shell/docking_shell.dart`): 4-panel in-house
  layout on `multi_split_view ^3.x`. Panels: viewport (left 75%), outliner
  (top-right), inspector (bottom-right), history (bottom strip). Each panel
  behind `RepaintBoundary`.

- **Editor shell** (`lib/src/shell/editor_shell.dart`): menu bar (File with
  New/Open/Save/Save As, Edit with Undo/Redo, Add with Cube/Sphere, Commands
  button), keyboard shortcuts (Cmd+Z undo, Cmd+Shift+Z redo, Delete/Backspace
  deletes selection, Cmd+S save, Cmd+P command palette), command palette
  overlay.

- **Outliner panel** (`lib/src/panels/outliner_panel.dart`): recursive tree
  from `controller.query`, selection highlighted, tap to select, visibility
  toggle per node, drag-to-reparent via `reparentNode` command (with cycle
  guard), add-node button in header.

- **Inspector panel** (`lib/src/panels/inspector_panel.dart`): name (text
  field, submits `setNodeName`), visible (toggle, submits `setNodeVisible`),
  transform TRS (Vec3 fields for translation/scale, commits `setNodeTransform`),
  per-component property sections with typed editors (`_PropertyValueRow`
  switching on `PropertyValue` subtypes). Rotation displayed read-only (see
  TODO below).

- **Property editors** (`lib/src/inspector/property_editors.dart`): string,
  bool (Switch), int, double, Vec3Field (3 axis fields inline).

- **History panel** (`lib/src/panels/history_panel.dart`): scrollable chip
  list of transactions, cursor marked bold/highlighted, undo/redo buttons.

- **Scene IO** (`lib/src/io/scene_io.dart`): save to `.fscene` via dart:io,
  open `.fscene` and return fresh controller, in-app path dialog (no
  file_picker dep).

- **Add Cube / Add Sphere**: 4-command sequence (createCuboidGeometry/
  createSphereGeometry, createMaterial type physicallyBased, createNode,
  addComponent mesh with both resource refs). Reads new resource/node ids
  by diffing the document's key sets before/after each run.

- **Barrel**: `lib/flutter_scene_editor.dart` exports `EditorController` and
  `EditorShell`.

- **Tests**: 5 headless tests in
  `packages/flutter_scene_editor/test/inspector_descriptor_test.dart` covering
  `uiDescriptors` shape and `builtinCommands` completeness. All pass under
  `flutter test`.

- **Example app**: `examples/editor_example/` with macOS scaffolding.
  `flutter build macos` succeeds (45 MB app bundle).

## What is stubbed or deferred

- **Rotation editor**: the rotation quaternion is displayed as read-only text.
  TODO(rotation-editor): add Euler-angle fields using a Vec4Field variant.

- **Outliner virtualization**: the outliner is a custom recursive widget.
  TODO(virtualize-outliner): replace with `two_dimensional_scrollables`
  `TreeView` for 1000+ node scenes.

- **Drag-to-redock panels**: panel sizes persist during the session; drag-to-
  redock to other slots is not implemented.
  TODO(docking-tabs): add `tabbed_view ^3.x` tab layer for detachable panels.

- **External hot-reload** (`watcher`): file watching on open path was not
  added. TODO(diff-reload): watch the open file and reload on change using
  `diffScene`/`reloadScene` for in-place patching, not a full re-realize.

- **Component property `setComponentProperties` map coercion**: the inspector
  passes raw Dart values to the command; complex property types (resource refs,
  color maps) need a coercion pass before the command can accept them.
  TODO(component-property-coercion): wire PropertyValue -> command param
  coercion for resource refs and colors in the component property section.

- **Stage-level properties** (environment, exposure, tone mapping): not
  exposed in Phase 2.

## Launch command

From the example directory:

```sh
flutter run -d macos --enable-flutter-gpu --enable-impeller
```

Both flags are needed for flutter_scene's GPU renderer (flutter_gpu / Impeller).
The app opens an empty scene. Use Add > Cube or Add > Sphere to add primitives.

## Verification checklist (for the maintainer)

Run the app with `flutter run -d macos --enable-flutter-gpu --enable-impeller`
from `examples/editor_example/`.

- [ ] App launches, shows the 4-panel shell with an empty viewport.
- [ ] FPS counter in the viewport top-right ticks at 120fps (ProMotion) or 60fps
      with no stutter while the other panels are visible.
- [ ] Add > Cube adds a white cube to the viewport and outliner.
- [ ] Add > Sphere adds a sphere similarly.
- [ ] Clicking a node in the viewport selects it (gizmo appears, outliner row
      highlights, inspector shows its properties).
- [ ] Clicking empty space clears the selection.
- [ ] Dragging a gizmo axis moves the node live; releasing commits one undo step.
- [ ] Cmd+Z undoes the move; the node snaps back.
- [ ] Cmd+Shift+Z redoes the move.
- [ ] Outliner row tap selects the node.
- [ ] Visibility toggle (eye icon) in outliner hides/shows the node.
- [ ] Inspector name field: type a new name, press Enter, node name updates in
      outliner.
- [ ] Inspector translation fields: edit X/Y/Z, press Enter, node moves in
      viewport.
- [ ] History panel shows all transactions; the most-recently applied one is
      highlighted.
- [ ] Drag an outliner row onto another node to reparent it (child appears
      indented under the new parent).
- [ ] Commands > (button or Cmd+P): palette opens, type to filter, press Enter
      to run.
- [ ] File > Save As: enter a path ending in `.fscene`, saves without error.
- [ ] File > Open: enter the same path, reloads the scene preserving nodes.
- [ ] Camera orbit (left-drag), pan (Shift+left-drag or middle-drag), zoom
      (scroll) all work while a gizmo is not active.
- [ ] Camera does NOT orbit while a gizmo drag is in progress.
- [ ] Delete key with a node selected removes it and it disappears from
      outliner and viewport.
