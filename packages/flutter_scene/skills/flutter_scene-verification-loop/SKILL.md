---
name: flutter_scene-verification-loop
version: 1
description: Close the visual-iteration loop when building or debugging a flutter_scene 3D app so you see your own output and self-correct. Use whenever a change affects what renders (geometry, materials, lighting, shaders, post-processing) or a frame looks wrong (black, washed-out, see-through, missing geometry).
---

# Verifying flutter_scene visually

flutter_scene renders 3D. A rendering change you cannot see is a guess, and guessing at pixels is the single biggest waste of iterations. The highest-value habit is a closed visual loop plus judgment that does not drift. This skill is that loop.

**The one thing to internalize: run it, let it settle, look at the frame AND the console, localize before you edit, repeat.** Do not change code off a hypothesis you did not confirm from the actual output.

## The loop

1. **Run.** Launch the app with `flutter run --enable-flutter-gpu` (native; the flag is mandatory and it is the only run flag, see the idioms skill). Where the editor MCP is connected, `run_project` launches the managed session instead.
2. **Settle.** A live frame is a moving target. Auto-exposure is still ramping, particles have a random phase, an animation is mid-clip, IBL re-bakes after the first present. Let the scene reach steady state (a few frames, or until the image stops changing) before you trust a capture. Do not screenshot the first frame and reason from it.
3. **Capture the frame AND read the console.** A screenshot alone hides errors that print; the console alone hides wrong pixels. Take both every time. Baseline path is a screenshot plus the run log; with the editor MCP it is `screenshot_viewport` plus `get_console`.
4. **Localize before editing.** When something is wrong, find where it goes wrong before you touch code. Read an intermediate buffer, read a single pixel's exact value, or scan for non-finite values. A NaN or Inf propagates silently into black or garbage downstream, so the first pass that produced it is the culprit, not the pass where you see the black. `references/loop.md` has the tool table and a symptom to action map.
5. **Correct, repeat.** Make one change, run the loop again. One change per iteration keeps cause and effect legible.

## The readiness gate (do not debug through it)

Rendering is gated on `Scene.initializeStaticResources()`. Until that Future completes, every frame is skipped and the engine prints exactly:

```
Flutter Scene is not ready to render. Skipping frame.
```

If you see that line, the scene is not broken, it is not ready. Wait for readiness (build geometry and materials inside `initializeStaticResources().then(...)`, gate the widget on `Scene.isReadyToRender`) before you diagnose anything else. A black frame while that line prints is the gate, not your code.

## Judge blind, never self-score (the load-bearing rule)

When deciding whether a change improved the look, **do not assign the frame a quality score.** Self-assigned scores drift upward, because the model is grading its own trajectory and wants to have made progress. That drift is how a session convinces itself a regression is an improvement.

Instead, **compare two frames and return a binary pick.** Put the new frame next to a reference (a known-good target) or the previous frame, and answer only "which of these two is better", A or B. No number, no "8/10", no "looks pretty good now". A blind pairwise pick does not inflate the way a solo score does. This applies to every visual review, including the ones that feel obvious.

If you have no reference at all, say so and describe the concrete difference between the two frames (this one is brighter here, that one has an artifact there) rather than inventing a score.

## Be honest about tooling

The richest observation tooling lives behind the editor MCP (`flutter_scene_mcp`): screenshots, console, NaN scans, render-graph capture, per-pass and per-pixel readback, viewport debug modes. A general-purpose observation server for an arbitrary running game is still being built, so do not assume those tools exist for every project. When the MCP is not connected, the baseline loop is still fully usable: `flutter run --enable-flutter-gpu`, read the console, take a screenshot. Do not claim a capability you cannot reach in the current project.

## More depth

- `references/loop.md` for the full editor-MCP tool table, the symptom to action map (black frame, washed-out, see-through, missing geometry), and the settle details.
- The `flutter_scene-idioms` skill (`references/traps.md`) for the underlying mistakes each symptom points back to (wrong vertex layout, hand-rolled winding flip, transform-in-place, the blank-frame causes).
