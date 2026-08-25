# flutter_scene_mcp

The MCP (Model Context Protocol) surface for the Flutter Scene Editor: it
lets an AI agent read a scene, author animations and other content through
the editor's command registry, preview the result on the Animation panel's
playhead, and capture viewport screenshots.

## Connecting to a running editor

The editor app hosts the server for its whole life on
`127.0.0.1:7007`. Bridge it to a stdio-based MCP client with:

```sh
dart run flutter_scene_mcp:flutter_scene_mcp_connect 7007
```

The tool set is tiered: a small curated set of perception tools
(`describe_scene`, `list_animations`, `get_animation`, `get_keyframes`,
`screenshot_viewport`, ...), plus `search_commands` and `run_command` as a
gateway into the editor's full command registry. Every `run_command` call is
a single undoable edit, identical to the same action in the editor UI.

## Security model

The server listens on **localhost, unauthenticated**. Any process running as
the same user can connect and drive the editor: read the open scene, run any
registered command, and save files through the document tools.

This is deliberate for the intended use — a developer's own agent working on
their own machine. Do not expose the port beyond localhost (no port
forwarding, no containers sharing the network namespace with untrusted
workloads) unless you add authentication first.

## Layout

- `lib/src/tool_surface.dart` — the transport-free, GPU-free tool surface
  over an [EditorSession]; fully unit-testable headlessly.
- `lib/src/mcp_server.dart` — the thin `dart_mcp` protocol adapter.
- `lib/socket_host.dart` — TCP hosting used by the editor app; the connect
  script bridges it to stdio.

Host-provided capabilities (screenshots, camera control, animation preview,
render-graph inspection) appear only when the running editor supplies them;
headless sessions omit those tools rather than failing.
