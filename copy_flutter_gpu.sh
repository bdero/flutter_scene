#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source build_utils.sh

if [ -z "$(which flutter)" ]; then
    PrintFatal "Flutter command not found in the path! Make sure to add the 'flutter/bin' directory to your PATH."
fi

FLUTTER_PACKAGES_DIR="$FLUTTER_SDK_DIR/packages"
if [ ! -z "$ENGINE_SRC_DIR" ]; then
    FLUTTER_GPU_SOURCE_DIR="$ENGINE_SRC_DIR/flutter/lib/gpu"
else
    FLUTTER_GPU_SOURCE_DIR="$(GetFlutterGpuArtifactsDirectory)"
fi

PrintInfo "Copying 'flutter_gpu' into the packages dir..."
PrintInfoSub "from" "${COLOR_RESET}$FLUTTER_GPU_SOURCE_DIR"
PrintInfoSub "  to" "${COLOR_RESET}$FLUTTER_PACKAGES_DIR/flutter_gpu"

mkdir -p "$FLUTTER_PACKAGES_DIR/flutter_gpu"
# Note: macOS doesn't support the -T flag for cp, unfortunately. So we have to
# be carefully end the source path with a slash.
cp -R "$FLUTTER_GPU_SOURCE_DIR/" "$FLUTTER_PACKAGES_DIR/flutter_gpu"
