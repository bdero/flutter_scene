#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <vector>

#include "generated/scene_flatbuffers.h"
#include "importer.h"
#include "types.h"

#include "flatbuffers/flatbuffer_builder.h"

namespace impeller {
namespace scene {
namespace importer {

[[nodiscard]] std::optional<std::vector<char>> ReadFileToBuffer(
    const std::string file_path) {
  std::ifstream in(file_path, std::ios_base::binary | std::ios::ate);
  if (!in.is_open()) {
    std::cerr << "Failed to open input file: " << file_path << std::endl;
    return std::nullopt;
  }
  size_t length = in.tellg();
  in.seekg(0, std::ios::beg);

  std::vector<char> bytes(length);
  in.read(bytes.data(), bytes.size());
  return bytes;
}

[[nodiscard]] bool WriteBufferToFile(const std::string file_path,
                                     const char* buffer,
                                     size_t size) {
  std::ofstream out(file_path, std::ios_base::binary);
  if (!out.is_open()) {
    std::cerr << "Failed to open output file: " << file_path << std::endl;
    return false;
  }
  out.write(buffer, size);
  return true;
}

bool Main(const std::string& input_file, const std::string& output_file) {
  auto input_buffer = impeller::scene::importer::ReadFileToBuffer(input_file);
  if (!input_buffer.has_value()) {
    return false;
  }

  fb::SceneT scene;
  if (!ParseGLTF(input_buffer.value(), scene)) {
    std::cerr << "Failed to parse input GLB file." << std::endl;
    return false;
  }

  flatbuffers::FlatBufferBuilder builder;
  builder.Finish(fb::Scene::Pack(builder, &scene), fb::SceneIdentifier());

  if (!WriteBufferToFile(
          output_file,
          reinterpret_cast<const char*>(builder.GetBufferPointer()),
          builder.GetSize())) {
    return false;
  }

  return true;
}

}  // namespace importer
}  // namespace scene
}  // namespace impeller

void PrintHelp(std::ostream& stream) {
  stream << std::endl;
  stream << "SceneC is an offline 3D geometry importer." << std::endl;
  stream << "---------------------------------------------------------------"
         << std::endl;
  stream << "Valid usage: importer [input_file] [output_file]" << std::endl;
  stream << "Note: Only GLB (glTF binary) input files are currently supported."
         << std::endl;
}

int main(int argc, char const* argv[]) {
  if (argc != 3) {
    PrintHelp(std::cerr);
    return EXIT_FAILURE;
  }

  std::string input_file = argv[1];
  std::string output_file = argv[2];

  return impeller::scene::importer::Main(input_file, output_file)
             ? EXIT_SUCCESS
             : EXIT_FAILURE;
}
