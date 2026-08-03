# Adds SPIRV-Headers and SPIRV-Tools before Dawn's own third_party handling.
#
# Dawn's third_party/CMakeLists.txt opens with `if (EMSCRIPTEN) return()`,
# because its Emscripten path is emdawnwebgpu, which maps webgpu.h onto the
# browser's WebGPU and needs no SPIR-V tooling. Tint's SPIR-V reader does need
# it, so building the reader for wasm requires supplying these ourselves.
#
# Injected through CMAKE_PROJECT_Dawn_INCLUDE, which runs immediately after
# Dawn's project() and before it descends into third_party. Dawn's own blocks
# are guarded by `if (NOT TARGET SPIRV-Tools ...)`, so defining the targets
# first is enough on platforms where that guard is reached.

if(NOT EMSCRIPTEN)
  return()
endif()

set(_tw_third_party "${Dawn_SOURCE_DIR}/third_party")

if(NOT TARGET SPIRV-Headers)
  set(SPIRV_HEADERS_SKIP_EXAMPLES ON CACHE BOOL "" FORCE)
  set(SPIRV_HEADERS_SKIP_INSTALL ON CACHE BOOL "" FORCE)
  add_subdirectory("${_tw_third_party}/spirv-headers/src"
                   "${CMAKE_BINARY_DIR}/third_party/spirv-headers")
endif()

if(NOT TARGET SPIRV-Tools)
  set(ENABLE_RTTI ON CACHE BOOL "" FORCE)
  set(SPIRV_SKIP_TESTS ON CACHE BOOL "" FORCE)
  set(SPIRV_SKIP_EXECUTABLES ON CACHE BOOL "" FORCE)
  set(SKIP_SPIRV_TOOLS_INSTALL ON CACHE BOOL "" FORCE)
  set(SPIRV_WERROR OFF CACHE BOOL "" FORCE)
  # Must land at ${CMAKE_BINARY_DIR}/third_party/spirv-tools, since that is
  # where the generated core_tables_*.inc are looked up from.
  add_subdirectory("${_tw_third_party}/spirv-tools/src"
                   "${CMAKE_BINARY_DIR}/third_party/spirv-tools" EXCLUDE_FROM_ALL)
endif()
