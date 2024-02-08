#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
IMPORTER_DIR="$SCRIPT_DIR/../importer"
IMPORTER_EXE="$IMPORTER_DIR/build/importer"

cd $SCRIPT_DIR

echo "Building examples..."

bash build_assets.sh

# Prepare example projects

function prepare_example {
    echo "Preparing $1..."
    pushd $1
    flutter create .
    flutter pub get
    popd
}
prepare_example flutter_app
