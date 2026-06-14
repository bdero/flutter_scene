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

---

## Prefab authoring (Phase 4.3)

### What was built

**`flutter_scene` (compose.dart)**: `applyPrefabOverride(SceneDocument, PropertyOverride)` is now a public API. It resolves the target node by its prefab-local id and calls the existing `_setProperty` path. Exported from `lib/fscene.dart`.

**`flutter_scene_editor_core` (builtin_commands.dart)**: `clearPrefabOverrides` command (params: nodeId). Clears the entire overrides list on a prefab instance in one undoable transaction. An already-empty instance produces no transaction (silently dropped by history). Two unit tests cover the happy path and the no-op case.

**`flutter_scene_editor` (editor_controller.dart)**:
- `loadPrefabDocument(AssetRef)`: public async method that reads and returns the prefab document, caching results in `_prefabCache` keyed by `source.key`. Shares the private `_loadPrefab` path resolution logic.
- `clearPrefabCache(String key)`: evicts one entry from the cache. Called by the inspector after Apply bakes the file.

**`flutter_scene_editor` (scene_io.dart)**: `applyOverridesToSource({sourcePath, overrides})` reads the source `.fscene`, applies each override via `applyPrefabOverride`, writes the updated JSON back.

**`flutter_scene_editor` (inspector_panel.dart)**: `_PrefabInstanceSection` renders below the component sections when `node.instance != null`. Layout:
- Source path displayed.
- "Apply to source" and "Revert all" buttons.
- A `FutureBuilder` on `controller.loadPrefabDocument` populates a flat list of `_OverrideRow` widgets, one per overridable property of each prefab node.
- Overridable properties: `name` (string field), `layers` (int field), `transform.trs.t/s` (Vec3Field), `transform.trs.r` (read-only quaternion text), and each `components.<type>.<prop>` value using the existing `_PropertyValueRow` switch.
- Overridden properties show a filled blue accent circle dot to the left.
- Each overridden property has a Revert button (runs `removePrefabOverride`).
- Editing a property runs `setPrefabOverride` with the new value, making the change undoable.

### What is stubbed or deferred

- **Rotation override editing**: `transform.trs.r` (quaternion) is shown as read-only text. TODO(rotation-editor): same gap as the instance transform rotation; needs a Vec4/quaternion field before it can be edited.
- **`visible` override**: `visible` is not in the `_setProperty` grammar in `compose.dart`, so it is not offered here to avoid creating overrides that silently no-op during composition. TODO(visible-override): add visible to `_setProperty` in compose.dart, then expose it in `_collectProps`.
- **Prefab cache invalidation on external file change**: the `_prefabCache` is not invalidated when the prefab source file changes on disk (e.g., after another Apply from a different instance). TODO(diff-reload): wire a file watcher that calls `clearPrefabCache` when a watched .fscene changes.
- **Godot-style editable children**: added/removed nodes on the instance (`addedNodes`/`removedNodes`) are not surfaced in the inspector yet. That needs source-to-composed id mapping for instance-internal nodes.

### Verification checklist (prefab authoring)

Open `examples/scenes/prefab_demo.fscene` (File > Open from the editor). The scene has two tree prefab instances ("Tree A" and "Tree B") and a ground plane.

Run the app with `flutter run -d macos --enable-flutter-gpu --enable-impeller` from `examples/editor_example/`.

- [ ] Both trees render in the viewport (same as before; regression check).
- [ ] Clicking "Tree A" or "Tree B" in the outliner selects it.
- [ ] The inspector shows a "Prefab Instance" section below the Transform section.
- [ ] The source path `tree_prefab.fscene` is displayed.
- [ ] After a moment the flat property list loads: Tree.name, Tree.layers,
      Tree.transform.trs.t, Tree.transform.trs.s, Trunk.name, Trunk.layers,
      Trunk.t, Trunk.s, Trunk.mesh.geometry, Trunk.mesh.material, etc.
- [ ] No blue dot appears next to any property (no overrides yet).
- [ ] Edit "Tree.name" (submit a new string): a blue dot appears next to the
      row and the history panel shows "Set prefab override".
- [ ] The Revert button next to that row removes the override (dot disappears,
      value reverts to the prefab default).
- [ ] Edit "Trunk.transform.trs.t" (change X/Y/Z): the dot appears on that
      row. Undo reverses the edit.
- [ ] With at least one override active, click "Revert all": all dots disappear
      and the history panel shows "Clear prefab overrides". Undo restores them.
- [ ] With at least one override active, click "Apply to source":
      - A snackbar confirms success.
      - The overrides clear (blue dots gone).
      - Open `examples/scenes/tree_prefab.fscene` in a text editor and confirm
        that the applied property value is now in the source file.
      - Reopen prefab_demo.fscene; the tree now reflects the applied value
        (baked into the source).
- [ ] Applying without a base directory (e.g. on an unsaved scene) shows a
      snackbar with a clear error message rather than crashing.
