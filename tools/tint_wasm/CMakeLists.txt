# Target definition for tint_wasm, the SPIR-V to WGSL translator the web
# backend loads at runtime.
#
# build.sh copies this plus tint_wasm.cpp into the Dawn checkout and appends an
# add_subdirectory for it, so Dawn stays the top-level CMake project. Adding
# Dawn as a subdirectory instead breaks SPIRV-Tools' generated-header include
# path, which is derived from Dawn's own binary directory.

if(NOT DEFINED TINT_WASM_REVISION)
  set(TINT_WASM_REVISION "unknown")
endif()

add_executable(tint_wasm tint_wasm.cpp)
target_compile_definitions(tint_wasm PRIVATE TINT_WASM_REVISION="${TINT_WASM_REVISION}")
target_include_directories(tint_wasm PRIVATE ${Dawn_SOURCE_DIR})
target_link_libraries(tint_wasm PRIVATE
  tint_api
  tint_api_common
  tint_lang_spirv_reader
  tint_lang_spirv_reader_common
  tint_lang_wgsl_writer
  tint_lang_wgsl_writer_common
  tint_lang_core_ir
)

# MODULARIZE keeps the glue out of globals, which matters because the host page
# is a Flutter app we do not control. DYNAMIC_EXECUTION is off to stay clear of
# strict CSP.
# Match Tint's own flags. Mismatched RTTI across TUs produces vtable dispatch
# failures at runtime rather than link errors.
target_compile_options(tint_wasm PRIVATE "-fno-rtti" "-fno-exceptions")

target_link_options(tint_wasm PRIVATE
  "-sMODULARIZE=1"
  "-sEXPORT_NAME=createTintWasm"
  "-sEXPORT_ES6=1"
  # A fixed heap rather than ALLOW_MEMORY_GROWTH. A growable heap is backed by
  # a resizable ArrayBuffer in current Chrome, and TextDecoder refuses those,
  # which breaks every string the module returns. Translation is bounded work,
  # so a fixed heap costs nothing.
  "-sINITIAL_MEMORY=512MB"
  "-sENVIRONMENT=web,worker,node"
  "-sDYNAMIC_EXECUTION=0"
  # Tint's IR validator recurses deeply; the 64KB default overflows on real
  # shaders.
  "-sSTACK_SIZE=8MB"
  "-sEXPORTED_FUNCTIONS=['_tw_init','_tw_revision','_tw_translate','_tw_wgsl','_tw_error','_malloc','_free']"
  "-sEXPORTED_RUNTIME_METHODS=['HEAPU32','UTF8ToString']"
  "-O3"
)
set_target_properties(tint_wasm PROPERTIES OUTPUT_NAME "tint_wasm" SUFFIX ".mjs")
