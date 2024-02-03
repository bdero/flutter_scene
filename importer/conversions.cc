#include "conversions.h"

#include <cstring>

#include "generated/scene_flatbuffers.h"

namespace impeller {
namespace scene {
namespace importer {

Matrix ToMatrix(const std::vector<double>& m) {
  return Matrix{
      static_cast<float>(m[0]),  static_cast<float>(m[1]),
      static_cast<float>(m[2]),  static_cast<float>(m[3]),
      static_cast<float>(m[4]),  static_cast<float>(m[5]),
      static_cast<float>(m[6]),  static_cast<float>(m[7]),
      static_cast<float>(m[8]),  static_cast<float>(m[9]),
      static_cast<float>(m[10]), static_cast<float>(m[11]),
      static_cast<float>(m[12]), static_cast<float>(m[13]),
      static_cast<float>(m[14]), static_cast<float>(m[15]),
  };
}

//-----------------------------------------------------------------------------
/// Flatbuffers -> Impeller
///

Matrix ToMatrix(const fb::Matrix& m) {
  return Matrix{m.m0(),  m.m1(),  m.m2(),  m.m3(),   //
                m.m4(),  m.m5(),  m.m6(),  m.m7(),   //
                m.m8(),  m.m9(),  m.m10(), m.m11(),  //
                m.m12(), m.m13(), m.m14(), m.m15()};
}

Vector2 ToVector2(const fb::Vec2& v) {
  return Vector2{v.x(), v.y()};
}

Vector3 ToVector3(const fb::Vec3& v) {
  return Vector3{v.x(), v.y(), v.z()};
}

Vector4 ToVector4(const fb::Vec4& v) {
  return Vector4({v.x(), v.y(), v.z(), v.w()});
}

Color ToColor(const fb::Color& c) {
  return Color({c.r(), c.g(), c.b(), c.a()});
}

//-----------------------------------------------------------------------------
/// Impeller -> Flatbuffers
///

fb::Matrix ToFBMatrix(const Matrix& m) {
  return fb::Matrix(m.m[0], m.m[1], m.m[2], m.m[3],    //
                    m.m[4], m.m[5], m.m[6], m.m[7],    //
                    m.m[8], m.m[9], m.m[10], m.m[11],  //
                    m.m[12], m.m[13], m.m[14], m.m[15]);
}

std::unique_ptr<fb::Matrix> ToFBMatrixUniquePtr(const Matrix& m) {
  return std::make_unique<fb::Matrix>(m.m[0], m.m[1], m.m[2], m.m[3],    //
                                      m.m[4], m.m[5], m.m[6], m.m[7],    //
                                      m.m[8], m.m[9], m.m[10], m.m[11],  //
                                      m.m[12], m.m[13], m.m[14], m.m[15]);
}

fb::Vec2 ToFBVec2(const Vector2 v) {
  return fb::Vec2(v.x, v.y);
}

fb::Vec3 ToFBVec3(const Vector3 v) {
  return fb::Vec3(v.x, v.y, v.z);
}

fb::Vec4 ToFBVec4(const Vector4 v) {
  return fb::Vec4(v.x, v.y, v.z, v.w);
}

fb::Color ToFBColor(const Color c) {
  return fb::Color(c.red, c.green, c.blue, c.alpha);
}

std::unique_ptr<fb::Color> ToFBColor(const std::vector<double>& c) {
  auto* color = new fb::Color(c.size() > 0 ? c[0] : 1,  //
                              c.size() > 1 ? c[1] : 1,  //
                              c.size() > 2 ? c[2] : 1,  //
                              c.size() > 3 ? c[3] : 1);
  return std::unique_ptr<fb::Color>(color);
}

}  // namespace importer
}  // namespace scene
}  // namespace impeller
