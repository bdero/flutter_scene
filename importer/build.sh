#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

echo "Building importer..."

mkdir -p build
cmake -Bbuild
cmake --build build --target=importer -j 4
