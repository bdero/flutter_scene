#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source build_utils.sh

if [ -z "$(which flutter)" ]; then
    echo >&2 "ERROR: Failed to find the 'flutter' executable! Make sure to add the 'flutter/bin' directory to your PATH."
    exit 1
fi

FLUTTER_PACKAGES_DIR="$FLUTTER_SDK_DIR/packages"
if [ ! -z "$ENGINE_SRC_DIR" ]; then
    FLUTTER_GPU_SOURCE_DIR="$ENGINE_SRC_DIR/flutter/lib/gpu"
else
    FLUTTER_GPU_SOURCE_DIR="$(GetFlutterGpuArtifactsDirectory)"
fi

echo "Copying 'flutter_gpu' into the packages dir..."
echo "  from: $FLUTTER_GPU_SOURCE_DIR"
echo "  to:   $FLUTTER_PACKAGES_DIR/flutter_gpu"
cp -TR "$FLUTTER_GPU_SOURCE_DIR" "$FLUTTER_PACKAGES_DIR/flutter_gpu"
