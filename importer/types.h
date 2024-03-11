#pragma once

#include <cmath>

namespace impeller {
namespace scene {
namespace importer {

using Scalar = float;

struct Vector4 {
  float x, y, z, w;

  Vector4 Normalize() const {
    const Scalar inverse = 1.0f / sqrt(x * x + y * y + z * z + w * w);
    return Vector4{x * inverse, y * inverse, z * inverse, w * inverse};
  }
};

struct Vector3 {
  float x = 0, y = 0, z = 0;
};

struct Vector2 {
  float x = 0, y = 0;
};

struct Quaternion {
  float x = 0, y = 0, z = 0, w = 1;
};

struct Matrix {
  union {
    float m[16];
    float e[4][4];
    Vector4 vec[4];
  };

  constexpr Matrix() {
    vec[0] = {1.0, 0.0, 0.0, 0.0};
    vec[1] = {0.0, 1.0, 0.0, 0.0};
    vec[2] = {0.0, 0.0, 1.0, 0.0};
    vec[3] = {0.0, 0.0, 0.0, 1.0};
  };

  constexpr Matrix(Scalar m0,
                   Scalar m1,
                   Scalar m2,
                   Scalar m3,
                   Scalar m4,
                   Scalar m5,
                   Scalar m6,
                   Scalar m7,
                   Scalar m8,
                   Scalar m9,
                   Scalar m10,
                   Scalar m11,
                   Scalar m12,
                   Scalar m13,
                   Scalar m14,
                   Scalar m15) {
    vec[0] = {m0, m1, m2, m3};
    vec[1] = {m4, m5, m6, m7};
    vec[2] = {m8, m9, m10, m11};
    vec[3] = {m12, m13, m14, m15};
  }

  static constexpr Matrix MakeTranslation(const Vector3& t) {
    // clang-format off
    return Matrix{1.0f, 0.0f, 0.0f, 0.0f,
                  0.0f, 1.0f, 0.0f, 0.0f,
                  0.0f, 0.0f, 1.0f, 0.0f,
                  t.x, t.y, t.z, 1.0f};
    // clang-format on
  }

  static constexpr Matrix MakeScale(const Vector3& s) {
    // clang-format off
    return Matrix{s.x, 0.0f, 0.0f, 0.0f,
                  0.0f, s.y, 0.0f, 0.0f,
                  0.0f, 0.0f, s.z, 0.0f,
                  0.0f, 0.0f, 0.0f, 1.0f};
    // clang-format on
  }

  static Matrix MakeRotation(Quaternion q) {
    // clang-format off
    return Matrix{
      1.0f - 2.0f * q.y * q.y  - 2.0f * q.z * q.z,
      2.0f * q.x  * q.y + 2.0f * q.z  * q.w,
      2.0f * q.x  * q.z - 2.0f * q.y  * q.w,
      0.0f,

      2.0f * q.x  * q.y - 2.0f * q.z  * q.w,
      1.0f - 2.0f * q.x * q.x  - 2.0f * q.z * q.z,
      2.0f * q.y  * q.z + 2.0f * q.x  * q.w,
      0.0f,

      2.0f * q.x  * q.z + 2.0f * q.y * q.w,
      2.0f * q.y  * q.z - 2.0f * q.x * q.w,
      1.0f - 2.0f * q.x * q.x  - 2.0f * q.y * q.y,
      0.0f,

      0.0f,
      0.0f,
      0.0f,
      1.0f};
    // clang-format on
  }

  static Matrix MakeRotation(Scalar radians, const Vector4& r) {
    const Vector4 v = r.Normalize();

    const Scalar cosine = cos(radians);
    const Scalar cosp = 1.0f - cosine;
    const Scalar sine = sin(radians);

    // clang-format off
    return Matrix{
      cosine + cosp * v.x * v.x,
      cosp * v.x * v.y + v.z * sine,
      cosp * v.x * v.z - v.y * sine,
      0.0f,

      cosp * v.x * v.y - v.z * sine,
      cosine + cosp * v.y * v.y,
      cosp * v.y * v.z + v.x * sine,
      0.0f,

      cosp * v.x * v.z + v.y * sine,
      cosp * v.y * v.z - v.x * sine,
      cosine + cosp * v.z * v.z,
      0.0f,

      0.0f,
      0.0f,
      0.0f,
      1.0f};
    // clang-format on
  }

  constexpr bool IsIdentity() const {
    return (
        // clang-format off
        m[0]  == 1.0f && m[1]  == 0.0f && m[2]  == 0.0f && m[3]  == 0.0f &&
        m[4]  == 0.0f && m[5]  == 1.0f && m[6]  == 0.0f && m[7]  == 0.0f &&
        m[8]  == 0.0f && m[9]  == 0.0f && m[10] == 1.0f && m[11] == 0.0f &&
        m[12] == 0.0f && m[13] == 0.0f && m[14] == 0.0f && m[15] == 1.0f
        // clang-format on
    );
  }

  constexpr Matrix Multiply(const Matrix& o) const {
    // clang-format off
    return Matrix{
        m[0] * o.m[0]  + m[4] * o.m[1]  + m[8]  * o.m[2]  + m[12] * o.m[3],
        m[1] * o.m[0]  + m[5] * o.m[1]  + m[9]  * o.m[2]  + m[13] * o.m[3],
        m[2] * o.m[0]  + m[6] * o.m[1]  + m[10] * o.m[2]  + m[14] * o.m[3],
        m[3] * o.m[0]  + m[7] * o.m[1]  + m[11] * o.m[2]  + m[15] * o.m[3],
        m[0] * o.m[4]  + m[4] * o.m[5]  + m[8]  * o.m[6]  + m[12] * o.m[7],
        m[1] * o.m[4]  + m[5] * o.m[5]  + m[9]  * o.m[6]  + m[13] * o.m[7],
        m[2] * o.m[4]  + m[6] * o.m[5]  + m[10] * o.m[6]  + m[14] * o.m[7],
        m[3] * o.m[4]  + m[7] * o.m[5]  + m[11] * o.m[6]  + m[15] * o.m[7],
        m[0] * o.m[8]  + m[4] * o.m[9]  + m[8]  * o.m[10] + m[12] * o.m[11],
        m[1] * o.m[8]  + m[5] * o.m[9]  + m[9]  * o.m[10] + m[13] * o.m[11],
        m[2] * o.m[8]  + m[6] * o.m[9]  + m[10] * o.m[10] + m[14] * o.m[11],
        m[3] * o.m[8]  + m[7] * o.m[9]  + m[11] * o.m[10] + m[15] * o.m[11],
        m[0] * o.m[12] + m[4] * o.m[13] + m[8]  * o.m[14] + m[12] * o.m[15],
        m[1] * o.m[12] + m[5] * o.m[13] + m[9]  * o.m[14] + m[13] * o.m[15],
        m[2] * o.m[12] + m[6] * o.m[13] + m[10] * o.m[14] + m[14] * o.m[15],
        m[3] * o.m[12] + m[7] * o.m[13] + m[11] * o.m[14] + m[15] * o.m[15]};
    // clang-format on
  }

  Matrix operator*(const Matrix& m) const { return Multiply(m); }
};

struct Color {
  float red = 0, green = 0, blue = 0, alpha = 0;
};

enum class SourceType {
  kUnknown,
  kGLTF,
};

}  // namespace importer
}  // namespace scene
}  // namespace impeller
