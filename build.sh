#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source build_utils.sh

bash copy_flutter_gpu.sh

pushd importer >/dev/null
bash build.sh
popd >/dev/null

bash build_shaders.sh

pushd examples >/dev/null
bash build.sh
popd >/dev/null
