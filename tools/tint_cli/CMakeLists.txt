# Target definition for flutter_scene_tint, the native SPIR-V to WGSL
# translator flutter_scene's build hook runs.
#
# build.sh copies this plus flutter_scene_tint.cpp into the Dawn checkout and
# appends an add_subdirectory for it, so Dawn stays the top-level CMake project.
# Adding Dawn as a subdirectory instead breaks SPIRV-Tools' generated-header
# include path, which is derived from Dawn's own binary directory.

if(NOT DEFINED FLUTTER_SCENE_TINT_REVISION)
  set(FLUTTER_SCENE_TINT_REVISION "unknown")
endif()

add_executable(flutter_scene_tint flutter_scene_tint.cpp)
target_compile_definitions(flutter_scene_tint PRIVATE
  FLUTTER_SCENE_TINT_REVISION="${FLUTTER_SCENE_TINT_REVISION}")
target_include_directories(flutter_scene_tint PRIVATE ${Dawn_SOURCE_DIR})
target_link_libraries(flutter_scene_tint PRIVATE
  tint_api
  tint_api_common
  tint_lang_spirv_reader
  tint_lang_spirv_reader_common
  tint_lang_wgsl_writer
  tint_lang_wgsl_writer_common
  tint_lang_core_ir
)
# Match Tint's own flags; mismatched RTTI across TUs fails at runtime.
if(MSVC)
  target_compile_options(flutter_scene_tint PRIVATE "/GR-")
else()
  target_compile_options(flutter_scene_tint PRIVATE "-fno-rtti")
endif()
