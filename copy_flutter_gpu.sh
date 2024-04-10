#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

if [ -z "$(which flutter)" ]; then
    echo >&2 "ERROR: Failed to find the 'flutter' executable! Make sure to add the 'flutter/bin' directory to your PATH."
    exit 1
fi

FLUTTER_DIR="$(dirname $(dirname $(which flutter))/..)"
FLUTTER_PACKAGES_DIR="$FLUTTER_DIR/packages"
FLUTTER_MACOS_ARTIFACTS="$FLUTTER_DIR/bin/cache/artifacts/engine/darwin-x64"

echo "Copying 'flutter_gpu' into the packages dir..."
echo "  from: $FLUTTER_MACOS_ARTIFACTS/flutter_gpu"
echo "  to:   $FLUTTER_PACKAGES_DIR/flutter_gpu"
cp -R "$FLUTTER_MACOS_ARTIFACTS/flutter_gpu" "$FLUTTER_PACKAGES_DIR"
