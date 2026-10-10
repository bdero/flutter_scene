// Translates shader-bundle SPIR-V to WGSL for flutter_scene's build hook.
//
//   flutter_scene_tint --version
//   flutter_scene_tint translate <manifest>
//
// The manifest has one shader per line, tab separated:
//
//   <input .spv>\t<output .wgsl>\t<mappings>
//
// where <mappings> is `fromGroup,fromBinding,toGroup,toBinding` quads joined
// by `;`, or empty to let Tint assign split-sampler bindings itself. Supplying
// any mapping suppresses Tint's ResolveBindingConflictsPass, so the caller owns
// binding assignment and textures keep their original numbers.
//
// Every shader is attempted; failures are reported on stderr as
// `FAILED\t<input>\t<reason>` and the exit status is 1 if any failed.

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>

#include "src/tint/api/common/binding_point.h"
#include "src/tint/api/tint.h"
// reader.h and writer.h only forward-declare Module, but Result<Module> has to
// be complete here.
#include "src/tint/lang/core/ir/module.h"
#include "src/tint/lang/spirv/reader/reader.h"
#include "src/tint/lang/wgsl/writer/writer.h"

#ifndef FLUTTER_SCENE_TINT_REVISION
#define FLUTTER_SCENE_TINT_REVISION "unknown"
#endif

namespace {

std::vector<std::string> Split(const std::string& s, char sep) {
    std::vector<std::string> out;
    std::string cur;
    std::istringstream in(s);
    while (std::getline(in, cur, sep)) {
        out.push_back(cur);
    }
    if (!s.empty() && s.back() == sep) {
        out.push_back("");
    }
    return out;
}

bool ReadWords(const std::string& path, std::vector<uint32_t>& words, std::string& error) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        error = "cannot open input";
        return false;
    }
    std::vector<char> bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (bytes.empty() || bytes.size() % 4 != 0) {
        error = "input is not a whole number of SPIR-V words";
        return false;
    }
    words.resize(bytes.size() / 4);
    std::memcpy(words.data(), bytes.data(), bytes.size());
    return true;
}

bool ParseMappings(const std::string& field,
                   tint::spirv::reader::Options& options,
                   std::string& error) {
    if (field.empty()) {
        return true;
    }
    for (const auto& quad : Split(field, ';')) {
        const auto parts = Split(quad, ',');
        if (parts.size() != 4) {
            error = "mapping '" + quad + "' is not four numbers";
            return false;
        }
        uint32_t v[4];
        for (int i = 0; i < 4; ++i) {
            char* end = nullptr;
            v[i] = static_cast<uint32_t>(std::strtoul(parts[i].c_str(), &end, 10));
            if (end == parts[i].c_str() || *end != '\0') {
                error = "mapping '" + quad + "' is not four numbers";
                return false;
            }
        }
        options.sampler_mappings.emplace(tint::BindingPoint{v[0], v[1]},
                                         tint::BindingPoint{v[2], v[3]});
    }
    return true;
}

bool Translate(const std::string& in_path,
               const std::string& out_path,
               const std::string& mappings,
               std::string& error) {
    std::vector<uint32_t> words;
    if (!ReadWords(in_path, words, error)) {
        return false;
    }
    tint::spirv::reader::Options reader_options;
    if (!ParseMappings(mappings, reader_options, error)) {
        return false;
    }
    auto ir = tint::spirv::reader::ReadIR(words, reader_options);
    if (ir != tint::Success) {
        error = "SPIR-V read failed: " + ir.Failure().reason;
        return false;
    }
    tint::wgsl::writer::Options writer_options;
    // Impeller shaders sample textures inside conditional branches, which GLSL
    // permits and WGSL rejects. Suppressing matches every other backend.
    writer_options.allow_non_uniform_derivatives = true;
    auto wgsl = tint::wgsl::writer::WgslFromIR(ir.Get(), writer_options);
    if (wgsl != tint::Success) {
        error = "WGSL write failed: " + wgsl.Failure().reason;
        return false;
    }
    std::ofstream out(out_path, std::ios::binary | std::ios::trunc);
    if (!out) {
        error = "cannot write output " + out_path;
        return false;
    }
    out << wgsl.Get().wgsl;
    return static_cast<bool>(out);
}

int Usage() {
    std::cerr << "usage: flutter_scene_tint --version\n"
                 "       flutter_scene_tint translate <manifest>\n";
    return 2;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
        std::cout << "flutter_scene_tint dawn " << FLUTTER_SCENE_TINT_REVISION << "\n";
        return 0;
    }
    if (argc != 3 || std::strcmp(argv[1], "translate") != 0) {
        return Usage();
    }
    std::ifstream manifest(argv[2]);
    if (!manifest) {
        std::cerr << "cannot open manifest " << argv[2] << "\n";
        return 2;
    }
    tint::Initialize();
    int failures = 0;
    int count = 0;
    std::string line;
    while (std::getline(manifest, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line.empty()) {
            continue;
        }
        const auto fields = Split(line, '\t');
        if (fields.size() < 2 || fields.size() > 3) {
            std::cerr << "FAILED\t" << line << "\tmanifest line needs 2 or 3 fields\n";
            ++failures;
            continue;
        }
        std::string error;
        ++count;
        if (!Translate(fields[0], fields[1], fields.size() == 3 ? fields[2] : "", error)) {
            std::cerr << "FAILED\t" << fields[0] << "\t" << error << "\n";
            ++failures;
        }
    }
    std::cout << "translated " << (count - failures) << " of " << count << "\n";
    return failures == 0 ? 0 : 1;
}
