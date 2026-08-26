---
name: flutter_scene-editor-authoring
version: 2
description: Drive the Flutter Scene Editor through its MCP server to create and modify nodes, import models, and author keyframe animations end to end. Use whenever an agent may edit a scene via the editor MCP tools (describe_scene, run_command, control_animation_preview, get_animation, screenshot_viewport) or is asked to build, animate, or verify scene content in a running editor.
---

# Authoring scenes and animations through the editor MCP

The running editor hosts an MCP server on `127.0.0.1:7007`. Through it you
can do everything the human editor can — build node trees, place models,
author keyframe animation, shape curves, and watch the result — without
touching the UI. This skill is the working loop plus the rules that keep
edits predictable.

**The one thing to internalize: every mutation goes through `run_command`
and is exactly one undoable edit, identical to the same action in the UI.
There is no side channel, so nothing you do can drift from what the user
sees or what saves to disk.**

## Prerequisite and connect

A human starts the editor app and opens a scene; the server is hosted by
that running app — you cannot launch the GUI or create the port yourself.

**How you connect depends on your MCP host.** The editor speaks MCP over
`127.0.0.1:7007`. Most agent hosts reach it by launching the bundled stdio
bridge as their server command — register it once in your client's MCP
config (the `mcpServers` shape Claude Code and most hosts use):

```json
{
  "mcpServers": {
    "flutter-scene-editor": {
      "command": "dart",
      "args": ["run", "flutter_scene_mcp:flutter_scene_mcp_connect", "7007"]
    }
  }
}
```

The bridge is a transparent pipe: your host launches it, talks MCP over its
stdio, and it forwards to the editor. After editing the config, restart or
reload your host's MCP connections; the editor's tools then appear through
your normal `tools/list`.

If your host dials TCP directly instead of spawning commands, open
newline-delimited MCP to `127.0.0.1:7007` yourself — same protocol, no
bridge.

Invocation notes:

- Tools arrive through the standard flow (`tools/list`, then `tools/call`);
  nothing here uses custom protocol extensions.
- Screenshots come back as **image content blocks**, not text.
- Command failures are ordinary tool results with `isError: true` and a
  human-readable message — read the message; it names the bad parameter.
- One registered connection survives New/Open document swaps in the editor.

One connection survives New/Open document swaps. The server is localhost
and unauthenticated by design — never forward the port beyond the machine.

## Tool tiers

- **Perceive:** `describe_scene`, `get_node`, `list_animations`,
  `get_animation`, `get_keyframes`, `list_resources`, `screenshot_viewport`,
  `screenshot_window`.
- **Mutate:** `search_commands` + `run_command`. Discover first; every match
  returns its argument schema ready to pass.
- **Host-only extras** (appear when the editor supplies them):
  `control_animation_preview`, `frame_node`, camera tools, project
  build/run tools.

Address nodes by slash path (`Root/Body`) or id token; animations accept an
exact name or id token.

## The animations tab and the preview

The Animation panel edits **exactly one clip at a time** on a shared
playhead. That playhead is what `control_animation_preview` drives: loading
a clip with `control_animation_preview {ref: <clip>}` selects it on the tab
(and resets its time), so subsequent key authoring, scrubbing, and playback
all act on the clip the panel is showing. `get_selection` does **not** select
a clip — clip selection is the preview's `ref`, node selection is a separate
concept.

Make the clip you intend to edit the loaded one first:

- No clip loaded, or the tab is showing the wrong one →
  `control_animation_preview {ref: <animationId or exact name>}`.
- The panel falls back to editing the document's first animation when
  nothing is explicitly loaded — never assume which clip that is.

The transport mirrors the panel's controls exactly:

| Panel control | MCP |
| --- | --- |
| Load clip / playhead | `control_animation_preview {ref}` |
| Scrub | `control_animation_preview {seek: <seconds>}` |
| Play / pause | `control_animation_preview {playing: true/false}` |
| Loop toggle | `control_animation_preview {loop: true/false}` |
| Speed | `control_animation_preview {speed: <multiplier>}` |
| Stop (restore posed nodes) | `control_animation_preview {stop: true}` |

One call may set any subset — they apply in the order select → stop → loop →
speed → seek → play, so a single request can load, reset, and start a clip.
`stop` also restores every previewed (including member) node to its rest
pose, so seek-then-stop is the way to clear a provisional pose.

## Node and model loop

1. **Create or import.** `createNode {name, parentId?}` for empties;
   `import_model {path}` pulls a `.glb/.gltf` in as a linked prefab
   (returns a scene-relative asset path; place more copies with
   `instantiatePrefab`). The scene must have been saved once before imports.
2. **Place.** `setNodeTransform {nodeId, translation?, rotation?,
   rotationEuler?, scale?}` — omitted components keep their current values.
   Give rotation as **either** a `rotation` quaternion `{x,y,z,w}` **or**
   `rotationEuler {yaw,pitch,roll}` in degrees (yaw=Y, pitch=X, roll=Z);
   passing both is an error.
3. **Shape the tree.** `reparentNode`, `duplicateNodes`, `deleteNode`,
   `setNodeName`, `setNodeVisible`.
4. **Look.** `createMaterial`, `setMaterialProperties`, `addComponent`,
   `setComponentProperties` — discover exact schemas with
   `search_commands`.
5. **Frame and look.** `frame_node {ref}`, then `screenshot_viewport`.

## Animation loop

Author poses, then key them. One clip drives many channels; channels are
created on demand the first time a key lands on them.

1. **Create the clip:** `run_command createAnimation {name}` — take its id
   from `list_animations`.
2. **Pose at the playhead, then key everything at once.** Pose each node
   with `setNodeTransform`, then
   `run_command keyPose {animationId, time, nodeIds:[...]}` captures every
   listed node's full transform (translation + rotation + scale) as keys at
   that time in **one undoable transaction**. This is the editor's Key
   button; prefer it over per-property keys for rigs.
3. **Or write keys directly.** `setAnimationKeyframes` batches many keys of
   one channel into one transaction:

   ```
   setAnimationKeyframes {
     animationId, nodeId, property: 'translation',
     keys: [ {time: 0, translation:{x:0,y:0,z:0}},
             {time: 0.5, translation:{x:0,y:2,z:0}},
             {time: 1, translation:{x:0,y:0,z:0}} ]
   }
   ```

   Omitted value components capture the node's current pose. Rotation keys
   accept `rotation` quaternions, `rotationEuler` degrees, or tangent slots
   on cubic channels (see below).
4. **Animate imported rigs (bones).** Linked models keep their bones
   inside the prefab; target a bone by pairing `nodeId` (the instance) with
   `targetName` (the member's name, e.g. `Bone_012`) on any key command:

   ```
   setAnimationKeyframe {
     animationId, nodeId: <instance>, targetName: 'Bone_012',
     property: 'rotation', time: 0.5,
     rotationEuler: {yaw: 20, pitch: 0, roll: 0}
   }
   ```

   Channels bind by name inside the instance's subtree at runtime, so head
   look-around, ear twitches, and limb motion all work. `get_animation`
   reports each channel's `member` name. Cubic channels also accept
   `inTangent`/`outTangent` per key.
5. **Shape timing.** `shiftAnimationTime {offset}` (rejects pushing any key
   below t=0), `scaleAnimationTime {factor}` (> 1 slows), and retime single
   keys with `moveAnimationKeyframe`. `duplicateAnimation` copies a clip as
   the base for variations.
6. **Remove and prune.** `removeAnimationKeyframe {animationId, nodeId,
   property, time}` deletes one key — removing a channel's **last** key
   deletes that channel (the tab's delete-key behavior). For members add
   `targetName`. `deleteAnimation {animationId}` removes a clip and all its
   keyframe payloads. Undo is one transaction per command, so a mistaken
   removal is one `undo` away.

## Curve shaping

`setChannelInterpolation {animationId, nodeId, property, interpolation}`:

- `linear` — default blend between neighbors (slerp for rotation).
- `step` — hold each key's value until the next one.
- `cubic` — Hermite through per-key tangents. Rows store
  `[inTangent, value, outTangent]`; converting expands with zero tangents
  (a smooth ease) and back-converting keeps keyed values but drops
  tangents.

Tangent slots are authored on the key commands themselves:
`inTangent`/`outTangent` take `{x,y,z}` vectors (rotation: `{x,y,z,w}`
quaternions), in units of value per second. They are cubic-only — providing
them elsewhere fails loudly instead of being ignored. Re-keying a cubic
key *without* tangent params preserves the existing tangents.

Read curves back with `get_animation {ref}` (capped at 200 keys/channel;
watch `totalKeys`/`keysTruncated`) or page ranges with
`get_keyframes {ref, node, property, fromTime, toTime}` — the safe path for
large imported clips. Rotation keys carry `eulerDeg` so you never have to
decode quaternions to check a heading; cubic keys also report their
`inTangent`/`outTangent`.

## Verify before you claim done

1. `control_animation_preview {ref, seek: <keyTime>}` parks the playhead on
   a key; `screenshot_viewport` shows the posed frame. Exact hits land on
   the key's own value in both preview and runtime.
2. **The playhead is shared with the human.** What you scrub or play is
   what the Animation tab shows in the editor — the user can see your keys,
   your curve mode, and the posed frame live. Load the clip you intend
   (`control_animation_preview {ref}`) before authoring so the panel
   reflects your work, not a stale clip.
2. Step mode holds the previous key until the next — seek just past a key,
   not onto it, when checking hold behavior.
3. `get_animation` confirms times, values, tangents, and duration survived.
4. Compare frames pairwise ("is this frame closer to the target than the
   last?") rather than scoring; see the verification-loop skill.

## Pitfalls

- **Every `run_command` is one undo step** — batch keys where you can, and
  use `undo` deliberately.
- **Quaternion XOR euler**, never both, on any rotation input.
- **Keyframe times cannot be negative.** Shifts that would push below zero
  are rejected; author at t≥0 or shift right first.
- **Morph-weight channels are imported-model data**: readable via
  `get_animation`, not authorable here.
- **`mirrorAnimationX` flips translation x and remaps rotations** across
  the YZ plane; it does not swap left/right bones — retarget after if the
  rig is sided.
- A failed call changes nothing: validation happens before any mutation.
  Fix the arguments and retry rather than compensating.

