#!/usr/bin/env bash
#
# Builds flutter_scene_tint into OUT_DIR unless it is already there (a CI
# cache hit), for the WebGPU smoke lane.
#
#   tools/webgpu_smoke/ensure_tint.sh OUT_DIR
#
# TODO(tint-release): download the released binary instead, once
# flutter_scene_tint-1 is published.
set -euo pipefail

OUT="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -x "$OUT/flutter_scene_tint" ]; then
  "$OUT/flutter_scene_tint" --version
  exit 0
fi
rev=$(grep -E '^DAWN_REVISION=' "$ROOT/tools/tint_cli/build.sh" | cut -d= -f2)
dawn="${RUNNER_TEMP:-/tmp}/dawn"
rm -rf "$dawn"
git init -q "$dawn"
git -C "$dawn" fetch -q --depth 1 https://dawn.googlesource.com/dawn "$rev"
git -C "$dawn" checkout -q FETCH_HEAD
build="${RUNNER_TEMP:-/tmp}/tint_build"
DAWN_SRC="$dawn" "$ROOT/tools/tint_cli/build.sh" "$build"
# Only the binary, so a cache of OUT stays small.
mkdir -p "$OUT"
cp "$build/flutter_scene_tint" "$OUT/"
"$OUT/flutter_scene_tint" --version
