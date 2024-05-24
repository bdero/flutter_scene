#pragma once

#include <cstddef>
#include <map>
#include <vector>

#include "generated/scene_flatbuffers.h"
#include "types.h"

namespace impeller {
namespace scene {
namespace importer {

Matrix ToMatrix(const std::vector<double>& m);

//-----------------------------------------------------------------------------
/// Flatbuffers -> Impeller
///

Matrix ToMatrix(const fb::Matrix& m);

Vector2 ToVector2(const fb::Vec2& c);

Vector3 ToVector3(const fb::Vec3& c);

Vector4 ToVector4(const fb::Vec4& c);

Color ToColor(const fb::Color& c);

//-----------------------------------------------------------------------------
/// Impeller -> Flatbuffers
///

fb::Matrix ToFBMatrix(const Matrix& m);

std::unique_ptr<fb::Matrix> ToFBMatrixUniquePtr(const Matrix& m);

fb::Vec2 ToFBVec2(const Vector2 v);

fb::Vec3 ToFBVec3(const Vector3 v);

fb::Vec4 ToFBVec4(const Vector4 v);

fb::Color ToFBColor(const Color c);

std::unique_ptr<fb::Color> ToFBColor(const std::vector<double>& c);

std::unique_ptr<fb::Vec3> ToFBColor3(const std::vector<double>& c);

}  // namespace importer
}  // namespace scene
}  // namespace impeller
