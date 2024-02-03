#!/usr/bin/env bash
set -e

echo "Building importer..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

mkdir -p build
cmake -Bbuild
cmake --build build --target=importer -j 4
