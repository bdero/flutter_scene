# Animation Panel — Tasklist

Working notes for the construction/performance review of the animation panel
(`lib/src/panels/animation_panel.dart` + `lib/src/panels/animation/*`). Items
are ordered by priority. Changes here are local and uncommitted.

## P0 — correctness

- [x] **1. Painter: scope drag-hide to the dragged channel** *(done)*
  `timeline_painter.dart`: the `dragFromTime` hide check now also matches the
  dragged channel's `target`/`property`, mirroring the drag-copy branch.
  Diamonds on other channels that happen to share the key's time stay visible
  during a drag.

- [x] **2. Timeline: vertical scrolling when lanes overflow the pane** *(done)*
  `_buildCanvas` now computes `verticalOverflow` and scrolls the content
  vertically via `Transform.translate` inside a viewport-sized, clipping
  Stack (no more overflow stripes; bottom rows reachable). Drivers:
  wheel when overflowing (horizontal delta still pans time), or dragging the
  label column. A proportional scrollbar thumb and the zoom pill are fixed
  to the viewport. Hit-testing uses `contentPos()` so lane lookups are
  content-space. Legend text updated.
  *Known trade-off:* the ruler scrolls with the content (it belongs to the
  time grid). Pinning it needs a separate viewport-fixed ruler paint —
  follow-up if it bothers anyone.

## P1 — performance

- [x] **3. Scope the playhead listener to the canvas paint** *(done)*
  `previewPlayhead`'s `ListenableBuilder` now wraps only the `CustomPaint`,
  so playback ticks repaint the canvas without rebuilding the header
  interpolation pills, lane ✕ buttons, or zoom pill.

- [x] **4. Cache the timeline payload decode** *(done)*
  `channelTimes` caches its decode in an `Expando` keyed on the payload's
  byte object. Verified safety: `flutter_scene_editor_core`'s animation
  commands build *new* `PayloadSpec` objects with fresh byte lists on every
  edit (`_floatsPayload`) and only ever read old bytes (`_payloadDiffers`);
  no in-place payload writes exist anywhere in the packages. The returned
  list is shared — documented as read-only for callers.

## P2 — deferred (needs support we shouldn't add as guests)

- [x] **8. Keyframe crystal visibility** *(done)*
  The diamonds filled with `scheme.secondary` directly on the lane line
  (`outlineVariant`) and band (`surfaceContainerLow`) — the same tonal
  family — so they all but disappeared. Every crystal now draws with a thin
  `scheme.onSurface` outline (theme-aware, works on any surface tone in
  light and dark), the body is slightly larger (5 → 5.5 half-diagonal, still
  inside the 12px hit radius), and the selected halo grew to match (7 → 8,
  0.2 → 0.25 alpha).

- [ ] **5. Batch keying/interpolation commands.** `_ensureEdgeKeys` runs up to
  6 awaited commands per selected node and `_groupInterpolationControl` runs
  one per channel; each triggers a full-editor `notifyListeners()`. Needs a
  batched command on the controller/MCP side — coordinate with upstream
  first.
- [ ] **6. `previewDuration` decodes all channel timelines every tick** in
  `_onTick`'s non-loop end check (`editor_controller.dart:751`). Fix belongs
  in the controller; deferred with 5.
- [ ] **7. Tighten `hitKey` row scoping.** The 12px radius exceeds half a row
  height (22px), so taps near a dense rig can select a key in the adjacent
  lane instead of scrubbing. Documented as intentional upstream — discuss
  before changing feel.

## Done

Tasks 1–4 completed in this working session (see checked items above).
Verification: `dart analyze lib/src/panels` clean; `animation_timeline_test`
and `animation_panel_editing_test` pass (one GPU-gated test skips, as before).

### Layout fixes (this session)

- **Interpolation pill no longer covers the first lane.** Measured the pill in
  a widget test: `SegmentedButton` renders 168×32 because its segments
  hard-code a 40px minimum height (`segmented_button.dart`,
  `textButtonMinHeight = 40.0`) that no `ButtonStyle` can override — so the
  14px-tall row budget was fiction, and the pill spilled ~14px below the
  header band onto the translation lane's t≈0 diamonds. Replaced it with a
  hand-rolled `_InterpPill` that honors its height exactly; the timeline
  header pill is now 14px inside the 22px band, and the keybar pill is 22px.
  `_InterpPill` is shared by the timeline headers and the key bar.
- **Key bar heights now agree** (26px Key button / 22px interp pill / 26px
  delete button — the delete `IconButton` previously enforced its 40px
  default minimum and inflated the whole row).
- **Lane labels can no longer run under the lane ✕ button** — the painter's
  lane title `maxWidth` now reserves the button's 20px instead of 18, ending
  the title at x=96 before the button at x=100.


Note: `tool/connector/telegram_connector.js` shows as modified in git status
but was **not** touched by this work — it appears to be the session connector
updating itself. Left as-is.

## Verification

After each change: `dart analyze lib/src/panels` and
`flutter test test/animation_timeline_test.dart test/animation_panel_editing_test.dart`
from `packages/flutter_scene_editor`.
