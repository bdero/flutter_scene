#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

if [ -z "$IMPELLERC" ]; then
    echo "IMPELLERC environment variable is not set. Please set it to the path of the impellerc executable in order to build shader bundles."
    exit 1
fi

function build_shader {
    echo "Building shader bundle: $1"

    SHADER_BUNDLE_JSON=$(echo $2 | tr -d '\n')
    $IMPELLERC --sl="$1" --shader-bundle="$SHADER_BUNDLE_JSON"
}

BASE_BUNDLE_JSON='
{
    "UnlitVertex": {
        "type": "vertex",
        "file": "shaders/unlit.vert"
    },
    "UnlitFragment": {
        "type": "fragment",
        "file": "shaders/unlit.frag"
    }
}'
build_shader "lib/generated/base.shaderbundle" "$BASE_BUNDLE_JSON"
