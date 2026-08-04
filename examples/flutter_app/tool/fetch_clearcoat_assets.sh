#!/usr/bin/env bash
#
# Fetches the textures and environment used by the Clearcoat example. The
# binary files stay local and are excluded from version control.
#
# Run from any directory. Set CLEARCOAT_ASSET_DIR to write elsewhere.
# Requires curl and shasum on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT_DIR=${CLEARCOAT_ASSET_DIR:-assets/clearcoat}
TEXTURE_REVISION=7cda7e710d884827fc73ff1a3aa63270846513d7
ENVIRONMENT_REVISION=83d50e3aa24052872569c33568809c08bec1bcba
TEXTURE_ROOT="https://raw.githubusercontent.com/mrdoob/three.js/$TEXTURE_REVISION/examples/textures"
ENVIRONMENT_ROOT="https://media.githubusercontent.com/media/KhronosGroup/glTF-Sample-Environments/$ENVIRONMENT_REVISION"

mkdir -p "$OUTPUT_DIR"

fetch() {
  local relative_url="$1" output_name="$2" expected_sha256="$3" root="$4"
  local output="$OUTPUT_DIR/$output_name"
  if [ -f "$output" ] && [ "$(shasum -a 256 "$output" | awk '{print $1}')" = "$expected_sha256" ]; then
    echo "$output already exists, skipping"
    return
  fi

  local partial="$output.partial"
  echo "Fetching $output_name"
  curl -fL --retry 3 --retry-delay 1 -o "$partial" "$root/$relative_url"
  local actual_sha256
  actual_sha256=$(shasum -a 256 "$partial" | awk '{print $1}')
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "Checksum mismatch for $output_name" >&2
    echo "Expected $expected_sha256" >&2
    echo "Received $actual_sha256" >&2
    exit 1
  fi
  mv "$partial" "$output"
}

fetch carbon/Carbon.png carbon.png \
  f5d4dd14c4b6f7548f50921e2bc75a77e2867fd93916928f60551f4857a96e06 \
  "$TEXTURE_ROOT"
fetch carbon/Carbon_Normal.png carbon_normal.png \
  15fe5cbeb3db8e85d8663ee1f67ffd5f0bfa457d01e1209c3011222ba08bb4fd \
  "$TEXTURE_ROOT"
fetch golfball.jpg golf_ball_normal.jpg \
  7d5f075891eac89ee55620cd8753efe8a969d89cdd73b54fe0ee444ee5da0b15 \
  "$TEXTURE_ROOT"
fetch pbr/Scratched_gold/Scratched_gold_01_1K_Normal.png scratched_normal.png \
  f6cbad89a8d43188007532a2545f382e225e6def85778fc530681588fb9f6f9c \
  "$TEXTURE_ROOT"
fetch water/Water_1_M_Normal.jpg water_normal.jpg \
  6d7825469a374ff84700b4fb1a2890bd1fce0ca1f777bdd4d5ecdaf15833a804 \
  "$TEXTURE_ROOT"
fetch pisa.hdr pisa.hdr \
  826890f7e7e34976b52e2d63f62d8e3b20414e5e2e15ac70d3f72073320a91b6 \
  "$ENVIRONMENT_ROOT"

echo "Clearcoat assets are ready in $OUTPUT_DIR"
