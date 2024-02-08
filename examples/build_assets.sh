#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
IMPORTER_DIR="$SCRIPT_DIR/../importer"
IMPORTER_EXE="$IMPORTER_DIR/build/importer"

cd $SCRIPT_DIR

# Check if importer is built
if [ ! -f "$IMPORTER_EXE" ]; then
    echo "Importer is not built. Building importer..."
    pushd $IMPORTER_DIR
    ./build.sh
    popd
fi

mkdir -p assets_imported

function import_asset {
    echo "Importing $1..."
    $IMPORTER_EXE assets_src/$1.glb assets_imported/$1.model
}
import_asset two_triangles
import_asset flutter_logo_baked
