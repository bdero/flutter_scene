#!/usr/bin/env bash
################################################################################
##
##        ______ _       _   _              _____
##        |  ___| |     | | | |            /  ___|
##        | |_  | |_   _| |_| |_ ___ _ __  \ `--.  ___ ___ _ __   ___
##        |  _| | | | | | __| __/ _ \ '__|  `--. \/ __/ _ \ '_ \ / _ \
##        | |   | | |_| | |_| ||  __/ |    /\__/ / (_|  __/ | | |  __/
##        \_|   |_|\__,_|\__|\__\___|_|    \____/ \___\___|_| |_|\___|
##        -----------------[ Universal build script ]-----------------
##
##
##
##  Optional environment variables
##  ==============================
##
##    IMPELLERC:      Path to the impellerc executable.
##                    If not set, the script will use the impellerc executable
##                    in the Flutter SDK.
##
##    ENGINE_SRC_DIR: Path to the Flutter engine source directory. Only needed
##                    if using a custom engine build.
##                    If not set,the script will attempt to find and copy the
##                    'flutter_gpu' package from the Flutter SDK engine
##                    artifacts.
##
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR

source build_utils.sh


################################################################################
##
##  1. Copy the Flutter GPU package source into the Flutter SDK.
##
##     By default, the script will copy the 'flutter_gpu' package from the
##     Flutter SDK engine artifacts.
##
##  BIG HACK to hold us over until https://github.com/flutter/flutter/issues/131711
##  is resolved.
##  If using a local engine build, override `ENGINE_SRC_DIR` in order to copy in
##  `flutter_gpu` package from the engine source directory.
##
bash copy_flutter_gpu.sh

################################################################################
##
##  2. Build the importer.
##
pushd importer >/dev/null
bash build.sh
popd >/dev/null

################################################################################
##
##  3. Build the shaders.
##
bash build_shaders.sh

################################################################################
##
##  4. Build the example app along with its assets.
##
pushd examples >/dev/null
bash build.sh
popd >/dev/null
