#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source ../build_utils.sh

PrintInfo "Building examples..."

# Prepare example projects

function prepare_example {
    PrintInfo "Preparing example app $1..."
    pushd $1 > /dev/null
    set +e
    flutter create . --platforms macos,ios,android
    flutter pub get
    set -e
    popd > /dev/null
}
prepare_example flutter_app
