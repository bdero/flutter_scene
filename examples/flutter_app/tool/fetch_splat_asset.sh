#!/usr/bin/env bash
#
# Fetches the Gaussian splat captures the Gaussian Splats example uses and
# converts them to bundleable .splat files under assets_src/. The example
# hides whichever asset is absent, so running this is optional.
#
#   strawberry  "Strawberry" by danylyon, https://superspl.at/scene/84df8849
#               CC BY 4.0 (the author notes attribution is appreciated
#               rather than required). 1.5M splats.
#   classroom   "Classroom of Class 6 Grade 9, China" by hite404,
#               https://superspl.at/scene/712d5b78, CC BY 4.0. 1.2M splats
#               (the streamed hosting's full-detail level, two chunks).
#
# The hosted format is SOG (webp-image-backed); @playcanvas/splat-transform
# unpacks (and for chunked scenes, merges) it to PLY, and
# tool/ply_to_splat.dart compacts that to the 32-byte .splat layout (drops
# rest SH, quantizes color/rotation to 8 bits) so each bundled asset stays
# under ~50MB instead of several hundred.
#
# Requires curl, python3, node (npx), and dart on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

CDN=https://d28zzqy0iyovbz.cloudfront.net
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Downloads one SOG directory (a meta.json plus the webp payloads it
# references) into $2.
fetch_sog() {
  local url_dir="$1" out_dir="$2"
  mkdir -p "$out_dir"
  curl -fsS -o "$out_dir/meta.json" "$url_dir/meta.json"
  python3 - "$out_dir/meta.json" <<'EOF' | while read -r f; do
import json, sys
meta = json.load(open(sys.argv[1]))
files = set()
for value in meta.values():
    if isinstance(value, dict) and 'files' in value:
        files.update(value['files'])
print('\n'.join(sorted(files)))
EOF
    # Windows Python writes CRLF; read removes only the trailing LF.
    f=${f%$'\r'}
    curl -fsS -o "$out_dir/$f" "$url_dir/$f"
  done
}

# fetch_asset <name> <scene id> <sog subdirs...>; "." means the scene is a
# single flat SOG at the scene root.
fetch_asset() {
  local name="$1" id="$2"
  shift 2
  local out="assets_src/$name.splat"
  if [ -e "$out" ]; then
    echo "$out already exists, skipping (delete it to refetch)"
    return
  fi
  local metas=()
  for dir in "$@"; do
    local sub=""
    [ "$dir" != "." ] && sub="/$dir"
    echo "Fetching $name$sub"
    fetch_sog "$CDN/$id/v1$sub" "$TMP/$name$sub"
    metas+=("$TMP/$name$sub/meta.json")
  done
  npx -y @playcanvas/splat-transform "${metas[@]}" "$TMP/$name.ply"
  # Avoid running unrelated native build hooks while retaining package imports.
  dart --packages=../../.dart_tool/package_config.json tool/ply_to_splat.dart "$TMP/$name.ply" "$out"
  echo "Wrote $out"
}

fetch_asset strawberry 84df8849 .
fetch_asset classroom 712d5b78 0_0 0_1
