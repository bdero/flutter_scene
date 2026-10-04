#!/usr/bin/env bash
#
# Opts the workspace into WGSL sidecars for flutter_scene and the smoke app.
# The hook downloads the released flutter_scene_tint; pass TINT to use a
# local build instead. CI only: it edits the workspace pubspec in place.
#
#   tools/webgpu_smoke/opt_in.sh [TINT]
set -euo pipefail

TINT="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if grep -q '^hooks:' "$ROOT/pubspec.yaml"; then
  echo "opt_in.sh: the workspace pubspec already has a hooks: section" >&2
  exit 2
fi
{
  echo
  echo "hooks:"
  echo "  user_defines:"
  for package in flutter_scene smoke_render; do
    echo "    $package:"
    echo "      flutter_scene_webgpu: true"
    if [ -n "$TINT" ]; then echo "      flutter_scene_tint: $TINT"; fi
  done
} >> "$ROOT/pubspec.yaml"
