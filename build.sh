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
##  0. Warn the user if they're not using the latest version of Flutter Scene.
##
CURRENT_COMMIT=$(git rev-parse HEAD)

# Fetch the JSON line containing the latest commit SHA from the 'flutter-gpu' branch.
LATEST_COMMIT=$(curl https://api.github.com/repos/bdero/flutter_scene/commits/flutter-gpu 2>/dev/null | grep sha | head -n 1)
# Remove the JSON key.
LATEST_COMMIT="${LATEST_COMMIT#*:}"
# Remove any remaining non-alphanumeric junk (quotes, commas, whitespace).
LATEST_COMMIT=$(echo $LATEST_COMMIT | sed "s/[^[:alnum:]-]//g")

if [ -z "$LATEST_COMMIT" ]; then
    PrintWarning "Failed to fetch the latest commit of the 'flutter_scene' repository."
    LATEST_COMMIT="unknown"
fi
if [ "$LATEST_COMMIT" == "$CURRENT_COMMIT" ]; then
    PrintInfo "${GREEN}You are using the latest commit of ${BGREEN}Flutter Scene${GREEN}!"
else
    PrintWarning "${BYELLOW}You are not using the latest commit of Flutter Scene!"
    PrintWarningSub "Current commit:" "$CURRENT_COMMIT"
    PrintWarningSub "Latest commit:" "$LATEST_COMMIT"
fi

################################################################################
##
##  3. Build the example app along with its assets.
##
pushd examples >/dev/null
bash build.sh
popd >/dev/null

################################################################################
##
##  4. \o/
##
PrintInfo "${GREEN}Successfully built ${BGREEN}Flutter Scene${GREEN}!${COLOR_RESET}"
