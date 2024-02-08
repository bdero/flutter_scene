#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
IMPORTER_DIR="$SCRIPT_DIR/../importer"
IMPORTER_EXE="$IMPORTER_DIR/build/importer"

cd $SCRIPT_DIR

echo "Building examples..."

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

# Prepare example projects

function prepare_example {
    echo "Preparing $1..."
    pushd $1
    flutter create .
    flutter pub get
    popd
}
prepare_example flutter_app
