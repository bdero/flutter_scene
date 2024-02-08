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
    "SimpleVertex": {
        "type": "vertex",
        "file": "shaders/flutter_scene_simple.vert"
    },
    "SimpleFragment": {
        "type": "fragment",
        "file": "shaders/flutter_scene_simple.frag"
    },
    "UnskinnedVertex": {
        "type": "vertex",
        "file": "shaders/flutter_scene_unskinned.vert"
    },
    "SkinnedVertex": {
        "type": "vertex",
        "file": "shaders/flutter_scene_skinned.vert"
    },
    "UnlitFragment": {
        "type": "fragment",
        "file": "shaders/flutter_scene_unlit.frag"
    }
}'
build_shader "assets/base.shaderbundle" "$BASE_BUNDLE_JSON"
