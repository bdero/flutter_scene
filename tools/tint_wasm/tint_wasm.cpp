// Emscripten wrapper exposing Tint's SPIR-V reader and WGSL writer, so the web
// backend can translate the shader bundle's Vulkan SPIR-V at load time.
//
// Deliberately a plain C ABI rather than embind. Tint builds with -fno-rtti and
// embind requires RTTI, and mixing the two produces vtable dispatch failures at
// runtime rather than link errors. A C ABI also maps directly onto Dart's
// js_interop without an intermediate object model.
//
// Ownership: every returned string is owned by the module and stays valid until
// the next tw_translate call.

#include <cstddef>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include <emscripten/emscripten.h>

#include "src/tint/api/common/binding_point.h"
#include "src/tint/api/tint.h"
// reader.h and writer.h only forward-declare Module, but Result<Module> has to
// be complete here.
#include "src/tint/lang/core/ir/module.h"
#include "src/tint/lang/spirv/reader/reader.h"
#include "src/tint/lang/wgsl/writer/writer.h"

namespace {

std::string g_wgsl;
std::string g_error;

}  // namespace

extern "C" {

EMSCRIPTEN_KEEPALIVE void tw_init() {
    tint::Initialize();
}

// The Dawn revision this was cut from, so a loaded artifact can be identified.
EMSCRIPTEN_KEEPALIVE const char* tw_revision() {
#ifdef TINT_WASM_REVISION
    return TINT_WASM_REVISION;
#else
    return "unknown";
#endif
}

// Translates `word_count` SPIR-V words at `spirv`. Returns 1 on success and 0
// on failure; read the result with tw_wgsl() or tw_error().
//
// `sampler_mappings` is `mapping_count` quads of
// [fromGroup, fromBinding, toGroup, toBinding]. Supplying any mapping
// suppresses Tint's ResolveBindingConflictsPass, so the caller owns binding
// assignment outright and textures keep their original numbers. Pass a count of
// zero to let Tint assign them.
EMSCRIPTEN_KEEPALIVE int tw_translate(const uint32_t* spirv,
                                      size_t word_count,
                                      const uint32_t* sampler_mappings,
                                      size_t mapping_count,
                                      int allow_non_uniform_derivatives,
                                      int minify) {
    g_wgsl.clear();
    g_error.clear();

    if (spirv == nullptr || word_count == 0) {
        g_error = "SPIR-V payload is empty";
        return 0;
    }

    std::vector<uint32_t> words(spirv, spirv + word_count);

    tint::spirv::reader::Options reader_options;
    for (size_t i = 0; i < mapping_count; ++i) {
        const uint32_t* quad = sampler_mappings + (i * 4);
        reader_options.sampler_mappings.emplace(tint::BindingPoint{quad[0], quad[1]},
                                                tint::BindingPoint{quad[2], quad[3]});
    }

    auto ir = tint::spirv::reader::ReadIR(words, reader_options);
    if (ir != tint::Success) {
        g_error = "SPIR-V read failed: " + ir.Failure().reason;
        return 0;
    }

    tint::wgsl::writer::Options writer_options;
    // Impeller shaders sample textures inside conditional branches, which GLSL
    // permits and WGSL rejects. Suppressing matches what every other backend
    // already does.
    writer_options.allow_non_uniform_derivatives = allow_non_uniform_derivatives != 0;
    writer_options.minify = minify != 0;

    auto wgsl = tint::wgsl::writer::WgslFromIR(ir.Get(), writer_options);
    if (wgsl != tint::Success) {
        g_error = "WGSL write failed: " + wgsl.Failure().reason;
        return 0;
    }

    g_wgsl = wgsl.Get().wgsl;
    return 1;
}

EMSCRIPTEN_KEEPALIVE const char* tw_wgsl() {
    return g_wgsl.c_str();
}

EMSCRIPTEN_KEEPALIVE const char* tw_error() {
    return g_error.c_str();
}

}  // extern "C"
