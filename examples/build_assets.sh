#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"
source ../build_utils.sh

IMPORTER_EXE="$(GetImporterExecutable)"
if [ ! -f "$IMPORTER_EXE" ]; then
    echo "Importer not found. Can't build example assets!"
    exit 1
fi

mkdir -p flutter_app/assets_imported

function import_asset {
    echo "Importing $1..."
    $IMPORTER_EXE assets_src/$1.glb flutter_app/assets_imported/$1.model
}
import_asset two_triangles
import_asset flutter_logo_baked
