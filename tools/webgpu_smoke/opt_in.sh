#!/usr/bin/env bash
#
# Opts the workspace into WGSL sidecars for flutter_scene and the smoke app,
# translated by the flutter_scene_tint at TINT. CI only: it edits the
# workspace pubspec in place.
#
#   tools/webgpu_smoke/opt_in.sh TINT
set -euo pipefail

TINT="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if grep -q '^hooks:' "$ROOT/pubspec.yaml"; then
  echo "opt_in.sh: the workspace pubspec already has a hooks: section" >&2
  exit 2
fi
cat >> "$ROOT/pubspec.yaml" <<YAML

hooks:
  user_defines:
    flutter_scene:
      flutter_scene_webgpu: true
      flutter_scene_tint: $TINT
    smoke_render:
      flutter_scene_webgpu: true
      flutter_scene_tint: $TINT
YAML
