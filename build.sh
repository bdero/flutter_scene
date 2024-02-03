#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

pushd importer
bash build.sh
popd

echo "Building Dart flatbuffer..."
FLATC_EXE="$SCRIPT_DIR/importer/build/_deps/flatbuffers-build/flatc"
$FLATC_EXE -o lib/generated --warnings-as-errors --gen-object-api --filename-suffix _flatbuffers --dart importer/scene.fbs

bash build_shaders.sh

pushd examples
bash build.sh
popd
