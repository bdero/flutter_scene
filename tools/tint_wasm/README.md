# tint_wasm

Tint's SPIR-V reader and WGSL writer compiled to WebAssembly, so the web
backend can translate the shader bundle's Vulkan SPIR-V at load time.

## Building

Requires an activated emsdk plus cmake and ninja.

```sh
source ~/emsdk/emsdk_env.sh
DAWN_SRC=/path/to/dawn ./build.sh
```

Artifacts land in `out/` as `tint_wasm.mjs` (glue) and `tint_wasm.wasm`
(~4 MB). Only rebuild when the pinned Dawn revision changes; the artifacts are
published rather than built per consumer.

## C ABI

Deliberately a plain C ABI rather than embind, because Tint builds with
`-fno-rtti` and embind requires RTTI. Every returned string is owned by the
module and valid until the next `tw_translate`.

| Export | Purpose |
| --- | --- |
| `tw_init()` | Must be called once before translating |
| `tw_revision()` | Dawn revision the artifact was cut from |
| `tw_translate(spirv, wordCount, mappings, mappingCount, allowNonUniformDerivatives, minify)` | Returns 1 on success, 0 on failure |
| `tw_wgsl()` | Translated WGSL after a successful call |
| `tw_error()` | Failure reason after an unsuccessful call |

`mappings` is `mappingCount` quads of `[fromGroup, fromBinding, toGroup,
toBinding]`. Supplying any mapping suppresses Tint's
`ResolveBindingConflictsPass`, so the caller owns binding assignment outright
and textures keep their original numbers. Pass a count of zero to let Tint
assign them.

## Notes that cost time to find

- Dawn's `third_party/CMakeLists.txt` opens with `if (EMSCRIPTEN) return()`, so
  SPIRV-Tools is never added and Tint's SPIR-V reader cannot build. Supplied by
  `emscripten_deps.cmake` through `CMAKE_PROJECT_Dawn_INCLUDE`.
- Dawn must stay the top-level CMake project. Adding it as a subdirectory
  breaks SPIRV-Tools' generated-header include path, which is derived from
  Dawn's binary directory.
- `dawncpp_module` uses C++20 modules and needs Ninja 1.11+, which depot_tools
  does not ship. `DAWN_SUPPORTS_CXX_MODULES=OFF` avoids it.
- Tint's IR validator recurses deeply enough to overflow Emscripten's 64 KB
  default stack. `-sSTACK_SIZE=8MB`.
- `-sFILESYSTEM=0` fails to link against a transitive `poll` reference.
- Passing SPIR-V through an embind `std::string` corrupts it, since embind runs
  JS strings through UTF-8 conversion.

## Verification

`tw_translate` output is byte-identical to the native `tint` CLI across all 48
shaders of the base bundle, and the binding layout matches
`WgslBindingMap.predict` for all 82 shaders across the base, materials, and
example bundles.
