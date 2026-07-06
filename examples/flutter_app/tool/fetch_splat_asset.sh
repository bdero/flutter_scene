#!/usr/bin/env bash
#
# Fetches the "Strawberry" Gaussian splat capture by danylyon
# (https://superspl.at/scene/84df8849, CC BY 4.0; the author notes
# attribution is appreciated but not required) and converts it to
# assets_src/strawberry.splat for the Gaussian Splats example. The example
# falls back to a procedural scene when the file is absent, so running this
# is optional.
#
# The hosted format is SOG (webp-image-backed); @playcanvas/splat-transform
# unpacks it to PLY, and tool/ply_to_splat.dart compacts that to the
# 32-byte .splat layout (drops rest SH, quantizes color/rotation to 8 bits)
# so the bundled asset stays ~48MB instead of ~340MB.
#
# Requires curl, node (npx), and dart on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=https://d28zzqy0iyovbz.cloudfront.net/84df8849/v1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The file list matches the pinned /v1/ upload of the scene.
for f in meta.json means_l.webp means_u.webp quats.webp scales.webp \
         sh0.webp shN_centroids.webp shN_labels.webp; do
  echo "Fetching $f"
  curl -fsS -o "$TMP/$f" "$BASE/$f"
done

npx -y @playcanvas/splat-transform "$TMP/meta.json" "$TMP/strawberry.ply"
dart run tool/ply_to_splat.dart "$TMP/strawberry.ply" \
  assets_src/strawberry.splat
echo "Wrote assets_src/strawberry.splat"
