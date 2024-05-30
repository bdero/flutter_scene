#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source build_utils.sh

################################################################################
##
##   Finds and copies the 'flutter_gpu' directory from the host artifacts into
##   the Flutter SDK's package cache directory, effectively making it a part of
##   the Flutter SDK.
##
##   This enables libraries and apps to include `flutter_gpu` as a Flutter SDK
##   package like so:
##   ```
##   # pubspec.yaml
##   dependencies:
##     flutter_gpu:
##       sdk: flutter
##   ```
##
################################################################################

FLUTTER_PACKAGES_DIR="$FLUTTER_SDK_DIR/bin/cache/pkg"
if [ ! -z "$ENGINE_SRC_DIR" ]; then
    FLUTTER_GPU_SOURCE_DIR="$ENGINE_SRC_DIR/flutter/lib/gpu"
else
    >&2 echo
    FLUTTER_GPU_SOURCE_DIR="$(GetFlutterGpuArtifactsDirectory)"
fi

PrintInfo "Copying 'flutter_gpu' into the packages dir..."
PrintInfoSub "from" "${COLOR_RESET}$FLUTTER_GPU_SOURCE_DIR"
PrintInfoSub "  to" "${COLOR_RESET}$FLUTTER_PACKAGES_DIR/flutter_gpu"

mkdir -p "$FLUTTER_PACKAGES_DIR/flutter_gpu"
# Note: macOS doesn't support the -T flag for cp, unfortunately. So we have to
#       carefully end the source path with a slash and the destination path
#       without a slash.
cp -R "$FLUTTER_GPU_SOURCE_DIR/" "$FLUTTER_PACKAGES_DIR/flutter_gpu"
