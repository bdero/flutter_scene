#!/usr/bin/env bash
################################################################################
##
##   This script is intended to be sourced by other scripts, not executed
##   directly.
##
################################################################################

FLUTTER_SCENE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
IMPORTER_DIR="${FLUTTER_SCENE_DIR}/importer"

FLUTTER_CMD="$(which flutter 2>/dev/null)"
if [ -z "$FLUTTER_CMD" ]; then
    >&2 echo "ERROR: Flutter command not found in the path! Make sure to add the 'flutter/bin' directory to your PATH."
    exit 1
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
        >&2 echo "ERROR: Failed to find the Flutter GPU artifacts directory."
        exit 1
    fi
    >&2 echo "  Flutter GPU artifacts directory found: $FOUND"
    echo "$FOUND"
}

function GetImpellercExecutable {
    if [ ! -z "$IMPELLERC" ]; then
        >&2 echo "Using impellerc environment variable: $IMPELLERC"
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
        >&2 echo "ERROR: Failed to find impellerc in the engine artifacts."
        exit 1
    fi
    >&2 echo "  impellerc executable found: $FOUND"
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
        >&2 echo "ERROR: Failed to find importer! Has the importer been built?"
        exit 1
    fi
    >&2 echo "  importer executable found: $FOUND"
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
        >&2 echo "ERROR: Failed to find flatc! Has the importer been built?"
        exit 1
    fi
    >&2 echo "  flatc executable found: $FOUND"
    echo "$FOUND"
}
