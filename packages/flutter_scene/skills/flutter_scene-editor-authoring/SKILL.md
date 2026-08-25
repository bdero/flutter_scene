---
name: flutter_scene-editor-authoring
version: 1
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

## Connect

The editor app hosts the server automatically. Bridge it to your stdio
client:

```sh
dart run flutter_scene_mcp:flutter_scene_mcp_connect 7007
```

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
4. **Shape timing.** `shiftAnimationTime {offset}` (rejects pushing any key
   below t=0), `scaleAnimationTime {factor}` (> 1 slows), and retime single
   keys with `moveAnimationKeyframe`. `duplicateAnimation` copies a clip as
   the base for variations.

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

