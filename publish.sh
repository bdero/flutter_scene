#!/usr/bin/env bash

FLUTTER_SCENE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "${FLUTTER_SCENE_DIR}" || exit 1

# Copy .pubignore file.
# We do this to prevent issues when publishing the importer package (which
# exists in a child directory).
cp flutter_scene_pubignore .pubignore

# Publish
flutter pub publish

# Remove .pubignore file
rm .pubignore
