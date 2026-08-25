# Editor MCP reference

Verified against `flutter_scene_editor_core` and `flutter_scene_mcp`.
Discover anything not listed here with `search_commands {query}`.

## Perception tools

| Tool | Returns |
| --- | --- |
| `describe_scene` | Node tree (ids, slash paths, components) + animation summary |
| `get_node {ref}` | One node's transform, components, children |
| `list_animations` | Every clip: id token, name, duration, channels' targets |
| `get_animation {ref, maxKeys?}` | Full keyframes per channel; caps at 200 keys/channel, reports `totalKeys` + `keysTruncated` |
| `get_keyframes {ref, node, property, fromTime?, toTime?, maxKeys?}` | Page one channel by time range |
| `list_resources` | Geometries, materials, textures, environments |
| `get_selection` / `select_node {ref}` / `clear_selection` | Selection state |
| `screenshot_viewport` / `screenshot_window` | PNG of viewport / whole window |
| `undo`, `redo` | Walk the history |

## Host tools (live editor only)

| Tool | Effect |
| --- | --- |
| `control_animation_preview` | Drive the playhead: `{ref?, seek?, playing?, loop?, speed?, stop?}` in order select → stop → loop → speed → seek → play. Returns transport state |
| `frame_node {ref}` | Aim camera at a node's bounds |
| `set_viewport_camera` / `get_viewport_camera` | Orbit pose compose for screenshots |
| `import_model {path, parentId?, scale?}` | `.glb/.gltf` as linked prefab instance |
| `import_environment {path}` | Panorama as environment lighting/sky |
| `new_document` / `open_document {path}` / `save_document {path?}` | Document lifecycle |
| Project tools | `open_project`, `build_project`, `run_project`, `hot_reload`, `list_devices`, `get_console`, render-graph inspection |

## Node commands (`run_command`)

| Command | Params |
| --- | --- |
| `createNode` | `name?`, `parentId?` → returns created id |
| `deleteNode` | `nodeId` |
| `setNodeName` | `nodeId`, `name` |
| `setNodeTransform` | `nodeId`, `translation? {x,y,z}`, `rotation? {x,y,z,w}` XOR `rotationEuler? {yaw,pitch,roll}` degrees, `scale? {x,y,z}` |
| `setNodeVisible` | `nodeId`, `visible` |
| `reparentNode` | `nodeId`, `newParentId`, `index?`, `keepWorldTransform?` |
| `duplicateNodes` | `nodeIds[]` |
| `addComponent` / `removeComponent` / `setComponentProperties` | Per component type; discover with `search_commands` |

## Animation commands

| Command | Params |
| --- | --- |
| `createAnimation` | `name?` (default "Animation") |
| `deleteAnimation` | `animationId` |
| `renameAnimation` | `animationId`, `name` |
| `keyPose` | `animationId`, `time`, `nodeIds[]` — full TRS of every node, one transaction |
| `setAnimationKeyframe` | `animationId`, `nodeId`, `property` (`translation`\|`rotation`\|`scale`), `time`, value components optional: `translation` / `rotation` XOR `rotationEuler` / `scale`; on cubic also `inTangent`/`outTangent` |
| `setAnimationKeyframes` | Same channel targeting, plus `keys: [{time, ...value}, ...]` — many keys, one transaction |
| `removeAnimationKeyframe` | `animationId`, `nodeId`, `property`, `time` (last key removed deletes the channel) |
| `moveAnimationKeyframe` | `animationId`, `nodeId`, `property`, `fromTime`, `toTime` |
| `setChannelInterpolation` | `animationId`, `nodeId`, `property`, `interpolation: linear\|step\|cubic` — converts payload layout on cubic switches |
| `shiftAnimationTime` | `animationId`, `offset` — rejects pre-zero results |
| `scaleAnimationTime` | `animationId`, `factor > 0` |
| `mirrorAnimationX` | `animationId` — flips translation x, remaps rotations across YZ |
| `duplicateAnimation` | `animationId`, `name?` — fresh ids, same targets |

## Value shapes

- Vector: `{x, y, z}`. Quaternion: `{x, y, z, w}`. Euler degrees:
  `{yaw, pitch, roll}` (yaw around Y, pitch X, roll Z, right-handed).
- Omitted keyframe components capture the target node's current pose.
- Cubic rows store `[inTangent, value, outTangent]` per keyframe; tangents
  are value-per-second. Converting linear→cubic fills zeros (smooth ease);
  converting back drops tangents.
- Rotation readback includes `eulerDeg` next to quaternions.

## Error behavior

Invalid arguments fail with a named-parameter message before any mutation;
ambiguous names tell you to use the id token; missing nodes/channels name
what was not found. A failed call leaves the document untouched.
