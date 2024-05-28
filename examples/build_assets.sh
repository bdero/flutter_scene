#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

source ../build_utils.sh

IMPORTER_EXE="$(GetImporterExecutable)"
if [ ! -f "$IMPORTER_EXE" ]; then
    PrintFatal "Importer not found. Can't build example assets!"
fi

mkdir -p flutter_app/assets_imported

function import_asset {
    PrintInfo "Importing $1..."
    IMPORT_COMMAND="$IMPORTER_EXE $SCRIPT_DIR/assets_src/$1.glb $SCRIPT_DIR/flutter_app/assets_imported/$1.model"
    PrintInfoSub "Command:" "$IMPORT_COMMAND"
    $IMPORT_COMMAND
}
import_asset two_triangles
import_asset flutter_logo_baked
#import_asset white_car
#import_asset wheel_minimal
#import_asset DamagedHelmet
