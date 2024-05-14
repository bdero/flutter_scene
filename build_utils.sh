#!/usr/bin/env bash
################################################################################
##
##   This script is intended to be sourced by other scripts, not executed
##   directly.
##
################################################################################

FLUTTER_SCENE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
IMPORTER_DIR="${FLUTTER_SCENE_DIR}/importer"

# Reset ANSI color code
COLOR_RESET='\033[0m'
# Normal ANSI color codes
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
# Bold ANSI color codes
BBLACK='\033[1;30m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BPURPLE='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

function PrintInfo {
    >&2 echo
    >&2 echo -e "${BCYAN}[INFO] ${CYAN}$1${COLOR_RESET}"
}

function PrintInfoSub {
    >&2 echo -e "${CYAN}       $1${COLOR_RESET} $2"
}

function PrintFatal {
    >&2 echo -e "${BRED}[FATAL] ${RED}$1${COLOR_RESET}"
    exit 1
}

FLUTTER_CMD="$(which flutter 2>/dev/null)"
if [ -z "$FLUTTER_CMD" ]; then
    PrintFatal "Flutter command not found in the path! Make sure to add the 'flutter/bin' directory to your PATH."
fi
FLUTTER_SDK_DIR="$(dirname ${FLUTTER_CMD})/.."
ENGINE_ARTIFACTS_DIR="${FLUTTER_SDK_DIR}/bin/cache/artifacts/engine"

function GetFlutterGpuArtifactsDirectory {
    LOCATIONS=(
        darwin-x64/flutter_gpu
        linux-x64/flutter_gpu
        windows-x64/flutter_gpu
    )
    FOUND=""
    for LOCATION in ${LOCATIONS[@]}; do
        FULL_PATH="${ENGINE_ARTIFACTS_DIR}/${LOCATION}"
        # >&2 echo "  Checking ${FULL_PATH}..."
        if test -d "$FULL_PATH"; then
            FOUND="$FULL_PATH"
            break
        fi
    done
    if [ -z "$FOUND" ]; then
        PrintFatal "Failed to find the Flutter GPU artifacts directory."
    fi
    PrintInfoSub "Flutter GPU artifacts directory found:" "$FOUND"
    echo "$FOUND"
}

function GetImpellercExecutable {
    if [ ! -z "$IMPELLERC" ]; then
        PrintInfo "Using impellerc environment variable: $IMPELLERC"
        echo "$IMPELLERC"
        return
    fi
    LOCATIONS=(
        darwin-x64/impellerc
        linux-x64/impellerc
        windows-x64/impellerc.exe
    )
    FOUND=""
    for LOCATION in ${LOCATIONS[@]}; do
        FULL_PATH="${ENGINE_ARTIFACTS_DIR}/${LOCATION}"
        # >&2 echo "  Checking ${FULL_PATH}..."
        if test -f "$FULL_PATH"; then
            FOUND="$FULL_PATH"
            break
        fi
    done
    if [ -z "$FOUND" ]; then
        PrintFatal "Failed to find impellerc in the engine artifacts."
    fi
    PrintInfoSub "impellerc executable found:" "$FOUND"
    echo "$FOUND"
}

function GetImporterExecutable {
    LOCATIONS=(
        Release/importer
        Release/importer.exe
        Debug/importer
        Debug/importer.exe
        importer
        importer.exe
    )
    FOUND=""
    for LOCATION in ${LOCATIONS[@]}; do
        FULL_PATH="${IMPORTER_DIR}/build/${LOCATION}"
        # >&2 echo "  Checking ${FULL_PATH}..."
        if test -f "$FULL_PATH"; then
            FOUND="$FULL_PATH"
            break
        fi
    done
    if [ -z "$FOUND" ]; then
        PrintFatal "Failed to find importer! Has the importer been built?"
    fi
    PrintInfoSub "importer executable found:" "$FOUND"
    echo "$FOUND"
}

function GetFlatcExecutable {
    LOCATIONS=(
        Release/flatc
        Release/flatc.exe
        Debug/flatc
        Debug/flatc.exe
        flatc
        flatc.exe
    )
    FOUND=""
    for LOCATION in ${LOCATIONS[@]}; do
        FULL_PATH="${IMPORTER_DIR}/build/_deps/flatbuffers-build/${LOCATION}"
        # >&2 echo "  Checking ${FULL_PATH}..."
        if test -f "$FULL_PATH"; then
            FOUND="$FULL_PATH"
            break
        fi
    done
    if [ -z "$FOUND" ]; then
        PrintFatal "Failed to find flatc! Has the importer been built?"
    fi
    PrintInfoSub "flatc executable found:" "$FOUND"
    echo "$FOUND"
}
