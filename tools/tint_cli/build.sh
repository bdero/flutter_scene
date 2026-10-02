#!/usr/bin/env bash
#
# Builds flutter_scene_tint, the native SPIR-V to WGSL translator the build
# hook downloads, for the host it runs on.
#
#   DAWN_SRC=/path/to/dawn ./build.sh [outDir]
#
# Requires cmake, ninja, and a C++20 compiler (MSVC on Windows, from a
# developer shell). Dawn must be checked out at DAWN_REVISION below; its
# third-party dependencies are fetched by the configure step. Extra CMake
# arguments come from CMAKE_EXTRA_ARGS (the macOS release passes a universal
# CMAKE_OSX_ARCHITECTURES).
#
# Google's prebuilt tint ships with the SPIR-V reader off, which is why we
# build our own.
set -euo pipefail

# The Dawn commit every published flutter_scene_tint is cut from.
DAWN_REVISION=cd2d5a667d1140af6e89f4c4c24f6545e1d5d2d7

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$HERE/out}"
DAWN_SRC="${DAWN_SRC:-}"
[ -n "$DAWN_SRC" ] || { echo "build.sh: set DAWN_SRC to a Dawn checkout" >&2; exit 2; }

REV="$(git -C "$DAWN_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$REV" != "$DAWN_REVISION" ]; then
  echo "build.sh: Dawn is at $REV, expected $DAWN_REVISION" >&2
  exit 2
fi

WRAPPER_DIR="$DAWN_SRC/flutter_scene_tint_wrapper"
mkdir -p "$WRAPPER_DIR"
cp "$HERE/flutter_scene_tint.cpp" "$HERE/CMakeLists.txt" "$WRAPPER_DIR/"
if ! grep -q "add_subdirectory(flutter_scene_tint_wrapper)" "$DAWN_SRC/CMakeLists.txt"; then
  printf '\n# Added by flutter_scene tools/tint_cli/build.sh\nadd_subdirectory(flutter_scene_tint_wrapper)\n' \
    >> "$DAWN_SRC/CMakeLists.txt"
fi

# shellcheck disable=SC2086
cmake -S "$DAWN_SRC" -B "$OUT" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DFLUTTER_SCENE_TINT_REVISION="$REV" \
  -DDAWN_FETCH_DEPENDENCIES=ON \
  -DDAWN_BUILD_SAMPLES=OFF \
  -DDAWN_BUILD_TESTS=OFF \
  -DDAWN_BUILD_BENCHMARKS=OFF \
  -DDAWN_BUILD_PROTOBUF=OFF \
  -DTINT_BUILD_TESTS=OFF \
  -DTINT_BUILD_BENCHMARKS=OFF \
  -DTINT_BUILD_CMD_TOOLS=OFF \
  -DTINT_BUILD_IR_BINARY=OFF \
  -DTINT_BUILD_SPV_READER=ON \
  -DTINT_BUILD_WGSL_WRITER=ON \
  -DTINT_BUILD_SPV_WRITER=OFF \
  -DTINT_BUILD_WGSL_READER=OFF \
  -DTINT_BUILD_GLSL_WRITER=OFF \
  -DTINT_BUILD_GLSL_VALIDATOR=OFF \
  -DTINT_BUILD_HLSL_WRITER=OFF \
  -DTINT_BUILD_MSL_WRITER=OFF \
  -DDAWN_ENABLE_D3D11=OFF \
  -DDAWN_ENABLE_D3D12=OFF \
  -DDAWN_ENABLE_METAL=OFF \
  -DDAWN_ENABLE_NULL=OFF \
  -DDAWN_ENABLE_DESKTOP_GL=OFF \
  -DDAWN_ENABLE_OPENGLES=OFF \
  -DDAWN_ENABLE_VULKAN=OFF \
  -DDAWN_USE_GLFW=OFF \
  -DDAWN_USE_X11=OFF \
  -DDAWN_USE_WAYLAND=OFF \
  -DDAWN_SUPPORTS_CXX_MODULES=OFF \
  ${CMAKE_EXTRA_ARGS:-}

cmake --build "$OUT" --target flutter_scene_tint

BIN="$OUT/flutter_scene_tint"
[ -f "$BIN.exe" ] && BIN="$BIN.exe"
"$BIN" --version
ls -la "$BIN"
