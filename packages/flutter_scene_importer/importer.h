#pragma once

#include <array>
#include <memory>

#include "generated/scene_flatbuffers.h"

namespace impeller {
namespace scene {
namespace importer {

bool ParseGLTF(const std::vector<char>& input_bytes, fb::SceneT& out_scene);

}
}  // namespace scene
}  // namespace impeller
