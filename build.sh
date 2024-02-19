#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source build_utils.sh

pushd importer
bash build.sh
popd

echo "Building flatbuffer Dart runtime..."
FLATC_EXE="$(GetFlatcExecutable)"
if [ ! -f "$FLATC_EXE" ]; then
    echo "FlatC not found. Can't build the flatbuffer Dart runtime!"
    exit 1
fi
$FLATC_EXE \
  -o lib/generated \
  --warnings-as-errors \
  --gen-object-api \
  --filename-suffix _flatbuffers \
  --dart importer/scene.fbs

bash build_shaders.sh

pushd examples
bash build.sh
popd
