#!/usr/bin/env bash
#
# Builds tint_wasm.{mjs,wasm}, the SPIR-V to WGSL translator the web backend
# loads at runtime.
#
#   DAWN_SRC=/path/to/dawn ./build.sh [outDir]
#
# Requires an activated emsdk (source emsdk_env.sh) plus cmake and ninja. Only
# run when the pinned Dawn revision changes; the artifacts are published rather
# than built per consumer.
#
# The wrapper is copied into the Dawn checkout and Dawn is configured as the
# top-level project. Adding Dawn as a subdirectory instead breaks SPIRV-Tools'
# generated-header include path, which is derived from Dawn's binary directory.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$HERE/out}"
DAWN_SRC="${DAWN_SRC:-}"

[ -n "$DAWN_SRC" ] || { echo "build.sh: set DAWN_SRC to a Dawn checkout" >&2; exit 2; }
command -v emcmake >/dev/null || { echo "build.sh: emsdk not activated" >&2; exit 2; }

REV="$(git -C "$DAWN_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "building tint_wasm against Dawn $REV"

WRAPPER_DIR="$DAWN_SRC/tint_wasm_wrapper"
mkdir -p "$WRAPPER_DIR"
cp "$HERE/tint_wasm.cpp" "$HERE/CMakeLists.txt" "$WRAPPER_DIR/"

# Hook the wrapper into Dawn's build once. Idempotent so repeat runs are safe.
if ! grep -q "tint_wasm_wrapper" "$DAWN_SRC/CMakeLists.txt"; then
  printf '\n# Added by flutter_scene tools/tint_wasm/build.sh\nadd_subdirectory(tint_wasm_wrapper)\n' \
    >> "$DAWN_SRC/CMakeLists.txt"
fi

emcmake cmake -S "$DAWN_SRC" -B "$OUT" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PROJECT_Dawn_INCLUDE="$HERE/emscripten_deps.cmake" \
  -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DTINT_WASM_REVISION="$REV" \
  -DDAWN_FETCH_DEPENDENCIES=ON \
  -DDAWN_BUILD_SAMPLES=OFF \
  -DDAWN_BUILD_TESTS=OFF \
  -DTINT_BUILD_TESTS=OFF \
  -DTINT_BUILD_CMD_TOOLS=OFF \
  -DTINT_BUILD_IR_BINARY=OFF \
  -DTINT_BUILD_SPV_READER=ON \
  -DTINT_BUILD_WGSL_WRITER=ON \
  -DTINT_BUILD_SPV_WRITER=OFF \
  -DTINT_BUILD_WGSL_READER=OFF \
  -DTINT_BUILD_GLSL_WRITER=OFF \
  -DTINT_BUILD_HLSL_WRITER=OFF \
  -DTINT_BUILD_MSL_WRITER=OFF \
  -DDAWN_ENABLE_D3D11=OFF \
  -DDAWN_ENABLE_D3D12=OFF \
  -DDAWN_ENABLE_METAL=OFF \
  -DDAWN_ENABLE_NULL=OFF \
  -DDAWN_ENABLE_DESKTOP_GL=OFF \
  -DDAWN_ENABLE_OPENGLES=OFF \
  -DDAWN_ENABLE_VULKAN=OFF \
  -DDAWN_SUPPORTS_CXX_MODULES=OFF

cmake --build "$OUT" --target tint_wasm

echo
ls -la "$OUT"/tint_wasm.mjs "$OUT"/tint_wasm.wasm
echo "sha256:"
shasum -a 256 "$OUT"/tint_wasm.wasm
