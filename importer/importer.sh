#!/usr/bin/env bash
## Invoke the importer.
##   usage: importer.sh <input> <output>
set -e

WORKING_DIR="$(pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

pushd $SCRIPT_DIR >/dev/null
source ../build_utils.sh
popd > /dev/null

IMPORTER_EXE="$(GetImporterExecutable)"
if [ ! -f "$IMPORTER_EXE" ]; then
    echo "Importer not found. Unable to build!"
    exit 1
fi

echo "Invoking importer..."
    echo "  input: $1"
    echo "  output: $2"
$IMPORTER_EXE $1 $2
