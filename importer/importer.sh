#!/usr/bin/env bash
## Invoke the importer.
##   usage: importer.sh <input> <output>
set -e

WORKING_DIR="$(pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

pushd $SCRIPT_DIR >/dev/null
source ../build_utils.sh
popd >/dev/null

IMPORTER_EXE="$(GetImporterExecutable)"
if [ ! -f "$IMPORTER_EXE" ]; then
    PrintFatal "Importer not found. Can't build example assets!"
fi

PrintInfo "Invoking importer..."

PrintInfoSub " input:" "$1"
PrintInfoSub "output:" "$2"
$IMPORTER_EXE $1 $2
