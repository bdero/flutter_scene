// GPU half of the FastNoiseLite port in package:flutter_scene/noise.dart (the
// Dart module at lib/src/noise/fast_noise_lite.dart is the source of truth).
// The two implementations must stay in lockstep, edit them together. Parity
// contract, the integer hashes are bit-exact and the float outputs stay within
// a small tolerance of the Dart implementation.
//
// This module relies on wrapping two's-complement int32 overflow in the hash
// and prime mixing, matching the Dart port's `_i32` wrappers. GLSL leaves
// signed integer overflow undefined on paper, but every GPU wraps in practice.
//
// Public functions are prefixed `Noise`; file-internal helpers, constants, and
// tables are prefixed `noise_` so they cannot collide with user code.
//
// ---------------------------------------------------------------------------
// FastNoiseLite is distributed under the MIT License:
//
// MIT License
//
// Copyright(c) 2023 Jordan Peck (jordan.me2@gmail.com)
// Copyright(c) 2023 Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// ---------------------------------------------------------------------------

// --- Hashing -----------------------------------------------------------------

const int noise_primeX = 501125321;
const int noise_primeY = 1136930381;
const int noise_primeZ = 1720413743;

int noise_hash2(int seed, int xPrimed, int yPrimed) {
  int hash = seed ^ xPrimed ^ yPrimed;
  hash *= 0x27d4eb2d;
  return hash;
}

int noise_hash3(int seed, int xPrimed, int yPrimed, int zPrimed) {
  int hash = seed ^ xPrimed ^ yPrimed ^ zPrimed;
  hash *= 0x27d4eb2d;
  return hash;
}

// Hashes an unprimed integer lattice cell. The prime multiplies happen here,
// so pass raw cell coordinates. Bit-exact with the Dart _hash2/_hash3.
int NoiseHash2(ivec2 cell, int seed) {
  return noise_hash2(seed, cell.x * noise_primeX, cell.y * noise_primeY);
}

int NoiseHash3(ivec3 cell, int seed) {
  return noise_hash3(seed, cell.x * noise_primeX, cell.y * noise_primeY,
                     cell.z * noise_primeZ);
}

// --- Math helpers --------------------------------------------------------------

int noise_fastFloor(float f) {
  return f >= 0.0 ? int(f) : int(f) - 1;
}

int noise_fastRound(float f) {
  return f >= 0.0 ? int(f + 0.5) : int(f - 0.5);
}

float noise_lerp(float a, float b, float t) {
  return a + t * (b - a);
}

float noise_pingPong(float t) {
  t -= float(int(t * 0.5) * 2);
  return t < 1.0 ? t : 2.0 - t;
}

// --- Gradient lookup tables ----------------------------------------------------
// Transcribed verbatim from the Dart port (which transcribes the canonical C#
// reference). 128 unit vectors at stride 2, then 64 vectors at stride 4.

const float noise_gradients2D[256] = float[256](
    0.130526192220052, 0.99144486137381, 0.38268343236509, 0.923879532511287,
    0.608761429008721, 0.793353340291235, 0.793353340291235, 0.608761429008721,
    0.923879532511287, 0.38268343236509, 0.99144486137381, 0.130526192220051,
    0.99144486137381, -0.130526192220051, 0.923879532511287, -0.38268343236509,
    0.793353340291235, -0.60876142900872, 0.608761429008721, -0.793353340291235,
    0.38268343236509, -0.923879532511287, 0.130526192220052, -0.99144486137381,
    -0.130526192220052, -0.99144486137381, -0.38268343236509, -0.923879532511287,
    -0.608761429008721, -0.793353340291235, -0.793353340291235, -0.608761429008721,
    -0.923879532511287, -0.38268343236509, -0.99144486137381, -0.130526192220052,
    -0.99144486137381, 0.130526192220051, -0.923879532511287, 0.38268343236509,
    -0.793353340291235, 0.608761429008721, -0.608761429008721, 0.793353340291235,
    -0.38268343236509, 0.923879532511287, -0.130526192220052, 0.99144486137381,
    0.130526192220052, 0.99144486137381, 0.38268343236509, 0.923879532511287,
    0.608761429008721, 0.793353340291235, 0.793353340291235, 0.608761429008721,
    0.923879532511287, 0.38268343236509, 0.99144486137381, 0.130526192220051,
    0.99144486137381, -0.130526192220051, 0.923879532511287, -0.38268343236509,
    0.793353340291235, -0.60876142900872, 0.608761429008721, -0.793353340291235,
    0.38268343236509, -0.923879532511287, 0.130526192220052, -0.99144486137381,
    -0.130526192220052, -0.99144486137381, -0.38268343236509, -0.923879532511287,
    -0.608761429008721, -0.793353340291235, -0.793353340291235, -0.608761429008721,
    -0.923879532511287, -0.38268343236509, -0.99144486137381, -0.130526192220052,
    -0.99144486137381, 0.130526192220051, -0.923879532511287, 0.38268343236509,
    -0.793353340291235, 0.608761429008721, -0.608761429008721, 0.793353340291235,
    -0.38268343236509, 0.923879532511287, -0.130526192220052, 0.99144486137381,
    0.130526192220052, 0.99144486137381, 0.38268343236509, 0.923879532511287,
    0.608761429008721, 0.793353340291235, 0.793353340291235, 0.608761429008721,
    0.923879532511287, 0.38268343236509, 0.99144486137381, 0.130526192220051,
    0.99144486137381, -0.130526192220051, 0.923879532511287, -0.38268343236509,
    0.793353340291235, -0.60876142900872, 0.608761429008721, -0.793353340291235,
    0.38268343236509, -0.923879532511287, 0.130526192220052, -0.99144486137381,
    -0.130526192220052, -0.99144486137381, -0.38268343236509, -0.923879532511287,
    -0.608761429008721, -0.793353340291235, -0.793353340291235, -0.608761429008721,
    -0.923879532511287, -0.38268343236509, -0.99144486137381, -0.130526192220052,
    -0.99144486137381, 0.130526192220051, -0.923879532511287, 0.38268343236509,
    -0.793353340291235, 0.608761429008721, -0.608761429008721, 0.793353340291235,
    -0.38268343236509, 0.923879532511287, -0.130526192220052, 0.99144486137381,
    0.130526192220052, 0.99144486137381, 0.38268343236509, 0.923879532511287,
    0.608761429008721, 0.793353340291235, 0.793353340291235, 0.608761429008721,
    0.923879532511287, 0.38268343236509, 0.99144486137381, 0.130526192220051,
    0.99144486137381, -0.130526192220051, 0.923879532511287, -0.38268343236509,
    0.793353340291235, -0.60876142900872, 0.608761429008721, -0.793353340291235,
    0.38268343236509, -0.923879532511287, 0.130526192220052, -0.99144486137381,
    -0.130526192220052, -0.99144486137381, -0.38268343236509, -0.923879532511287,
    -0.608761429008721, -0.793353340291235, -0.793353340291235, -0.608761429008721,
    -0.923879532511287, -0.38268343236509, -0.99144486137381, -0.130526192220052,
    -0.99144486137381, 0.130526192220051, -0.923879532511287, 0.38268343236509,
    -0.793353340291235, 0.608761429008721, -0.608761429008721, 0.793353340291235,
    -0.38268343236509, 0.923879532511287, -0.130526192220052, 0.99144486137381,
    0.130526192220052, 0.99144486137381, 0.38268343236509, 0.923879532511287,
    0.608761429008721, 0.793353340291235, 0.793353340291235, 0.608761429008721,
    0.923879532511287, 0.38268343236509, 0.99144486137381, 0.130526192220051,
    0.99144486137381, -0.130526192220051, 0.923879532511287, -0.38268343236509,
    0.793353340291235, -0.60876142900872, 0.608761429008721, -0.793353340291235,
    0.38268343236509, -0.923879532511287, 0.130526192220052, -0.99144486137381,
    -0.130526192220052, -0.99144486137381, -0.38268343236509, -0.923879532511287,
    -0.608761429008721, -0.793353340291235, -0.793353340291235, -0.608761429008721,
    -0.923879532511287, -0.38268343236509, -0.99144486137381, -0.130526192220052,
    -0.99144486137381, 0.130526192220051, -0.923879532511287, 0.38268343236509,
    -0.793353340291235, 0.608761429008721, -0.608761429008721, 0.793353340291235,
    -0.38268343236509, 0.923879532511287, -0.130526192220052, 0.99144486137381,
    0.38268343236509, 0.923879532511287, 0.923879532511287, 0.38268343236509,
    0.923879532511287, -0.38268343236509, 0.38268343236509, -0.923879532511287,
    -0.38268343236509, -0.923879532511287, -0.923879532511287, -0.38268343236509,
    -0.923879532511287, 0.38268343236509, -0.38268343236509, 0.923879532511287
);

const float noise_gradients3D[256] = float[256](
    0.0, 1.0, 1.0, 0.0,
    0.0, -1.0, 1.0, 0.0,
    0.0, 1.0, -1.0, 0.0,
    0.0, -1.0, -1.0, 0.0,
    1.0, 0.0, 1.0, 0.0,
    -1.0, 0.0, 1.0, 0.0,
    1.0, 0.0, -1.0, 0.0,
    -1.0, 0.0, -1.0, 0.0,
    1.0, 1.0, 0.0, 0.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, -1.0, 0.0, 0.0,
    -1.0, -1.0, 0.0, 0.0,
    0.0, 1.0, 1.0, 0.0,
    0.0, -1.0, 1.0, 0.0,
    0.0, 1.0, -1.0, 0.0,
    0.0, -1.0, -1.0, 0.0,
    1.0, 0.0, 1.0, 0.0,
    -1.0, 0.0, 1.0, 0.0,
    1.0, 0.0, -1.0, 0.0,
    -1.0, 0.0, -1.0, 0.0,
    1.0, 1.0, 0.0, 0.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, -1.0, 0.0, 0.0,
    -1.0, -1.0, 0.0, 0.0,
    0.0, 1.0, 1.0, 0.0,
    0.0, -1.0, 1.0, 0.0,
    0.0, 1.0, -1.0, 0.0,
    0.0, -1.0, -1.0, 0.0,
    1.0, 0.0, 1.0, 0.0,
    -1.0, 0.0, 1.0, 0.0,
    1.0, 0.0, -1.0, 0.0,
    -1.0, 0.0, -1.0, 0.0,
    1.0, 1.0, 0.0, 0.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, -1.0, 0.0, 0.0,
    -1.0, -1.0, 0.0, 0.0,
    0.0, 1.0, 1.0, 0.0,
    0.0, -1.0, 1.0, 0.0,
    0.0, 1.0, -1.0, 0.0,
    0.0, -1.0, -1.0, 0.0,
    1.0, 0.0, 1.0, 0.0,
    -1.0, 0.0, 1.0, 0.0,
    1.0, 0.0, -1.0, 0.0,
    -1.0, 0.0, -1.0, 0.0,
    1.0, 1.0, 0.0, 0.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, -1.0, 0.0, 0.0,
    -1.0, -1.0, 0.0, 0.0,
    0.0, 1.0, 1.0, 0.0,
    0.0, -1.0, 1.0, 0.0,
    0.0, 1.0, -1.0, 0.0,
    0.0, -1.0, -1.0, 0.0,
    1.0, 0.0, 1.0, 0.0,
    -1.0, 0.0, 1.0, 0.0,
    1.0, 0.0, -1.0, 0.0,
    -1.0, 0.0, -1.0, 0.0,
    1.0, 1.0, 0.0, 0.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, -1.0, 0.0, 0.0,
    -1.0, -1.0, 0.0, 0.0,
    1.0, 1.0, 0.0, 0.0,
    0.0, -1.0, 1.0, 0.0,
    -1.0, 1.0, 0.0, 0.0,
    0.0, -1.0, -1.0, 0.0
);

float noise_gradCoord2(int seed, int xPrimed, int yPrimed, float xd, float yd) {
  int hash = noise_hash2(seed, xPrimed, yPrimed);
  hash ^= hash >> 15;
  hash &= 127 << 1;

  float xg = noise_gradients2D[hash];
  float yg = noise_gradients2D[hash | 1];

  return xd * xg + yd * yg;
}

float noise_gradCoord3(int seed, int xPrimed, int yPrimed, int zPrimed,
                       float xd, float yd, float zd) {
  int hash = noise_hash3(seed, xPrimed, yPrimed, zPrimed);
  hash ^= hash >> 15;
  hash &= 63 << 2;

  float xg = noise_gradients3D[hash];
  float yg = noise_gradients3D[hash | 1];
  float zg = noise_gradients3D[hash | 2];

  return xd * xg + yd * yg + zd * zg;
}

// --- Input skew/rotation ---------------------------------------------------------
// Constants kept in the same expression form as the Dart module.

const float noise_sqrt3 = 1.7320508075688772935274463415059;
const float noise_f2 = 0.5 * (noise_sqrt3 - 1.0);
const float noise_g2 = (3.0 - noise_sqrt3) / 6.0;
const float noise_r3 = 2.0 / 3.0;

// The f2 skew getNoise2 applies before OpenSimplex2/OpenSimplex2S evaluation.
vec2 noise_skew2(vec2 p) {
  float t = (p.x + p.y) * noise_f2;
  return p + t;
}

// The r3 rotation getNoise3 applies (a rotation, not a skew).
vec3 noise_rotate3(vec3 p) {
  float r = (p.x + p.y + p.z) * noise_r3;
  return r - p;
}

// --- 2D OpenSimplex2 (ordinary simplex) ------------------------------------------

float noise_singleSimplex2(int seed, float x, float y) {
  int i = noise_fastFloor(x);
  int j = noise_fastFloor(y);
  float xi = x - float(i);
  float yi = y - float(j);

  float t = (xi + yi) * noise_g2;
  float x0 = xi - t;
  float y0 = yi - t;

  i *= noise_primeX;
  j *= noise_primeY;

  float n0, n1, n2;

  float a = 0.5 - x0 * x0 - y0 * y0;
  if (a <= 0.0) {
    n0 = 0.0;
  } else {
    n0 = (a * a) * (a * a) * noise_gradCoord2(seed, i, j, x0, y0);
  }

  float c = (2.0 * (1.0 - 2.0 * noise_g2) * (1.0 / noise_g2 - 2.0)) * t +
            ((-2.0 * (1.0 - 2.0 * noise_g2) * (1.0 - 2.0 * noise_g2)) + a);
  if (c <= 0.0) {
    n2 = 0.0;
  } else {
    float x2 = x0 + (2.0 * noise_g2 - 1.0);
    float y2 = y0 + (2.0 * noise_g2 - 1.0);
    n2 = (c * c) * (c * c) *
         noise_gradCoord2(seed, i + noise_primeX, j + noise_primeY, x2, y2);
  }

  if (y0 > x0) {
    float x1 = x0 + noise_g2;
    float y1 = y0 + (noise_g2 - 1.0);
    float b = 0.5 - x1 * x1 - y1 * y1;
    if (b <= 0.0) {
      n1 = 0.0;
    } else {
      n1 = (b * b) * (b * b) *
           noise_gradCoord2(seed, i, j + noise_primeY, x1, y1);
    }
  } else {
    float x1 = x0 + (noise_g2 - 1.0);
    float y1 = y0 + noise_g2;
    float b = 0.5 - x1 * x1 - y1 * y1;
    if (b <= 0.0) {
      n1 = 0.0;
    } else {
      n1 = (b * b) * (b * b) *
           noise_gradCoord2(seed, i + noise_primeX, j, x1, y1);
    }
  }

  return (n0 + n1 + n2) * 99.83685446303647;
}

// --- 3D OpenSimplex2 --------------------------------------------------------------

float noise_singleOpenSimplex2_3(int seed, float x, float y, float z) {
  int i = noise_fastRound(x);
  int j = noise_fastRound(y);
  int k = noise_fastRound(z);
  float x0 = x - float(i);
  float y0 = y - float(j);
  float z0 = z - float(k);

  int xNSign = int(-1.0 - x0) | 1;
  int yNSign = int(-1.0 - y0) | 1;
  int zNSign = int(-1.0 - z0) | 1;

  float ax0 = float(xNSign) * -x0;
  float ay0 = float(yNSign) * -y0;
  float az0 = float(zNSign) * -z0;

  i *= noise_primeX;
  j *= noise_primeY;
  k *= noise_primeZ;

  float value = 0.0;
  float a = (0.6 - x0 * x0) - (y0 * y0 + z0 * z0);

  // The Dart loop is unconditional with an `if (l == 1) break;` in the middle;
  // the l < 2 bound is equivalent (the break always fires first) and keeps the
  // loop statically bounded for GLSL.
  for (int l = 0; l < 2; l++) {
    if (a > 0.0) {
      value += (a * a) * (a * a) * noise_gradCoord3(seed, i, j, k, x0, y0, z0);
    }

    if (ax0 >= ay0 && ax0 >= az0) {
      float b = a + ax0 + ax0;
      if (b > 1.0) {
        b -= 1.0;
        value += (b * b) * (b * b) *
                 noise_gradCoord3(seed, i - xNSign * noise_primeX, j, k,
                                  x0 + float(xNSign), y0, z0);
      }
    } else if (ay0 > ax0 && ay0 >= az0) {
      float b = a + ay0 + ay0;
      if (b > 1.0) {
        b -= 1.0;
        value += (b * b) * (b * b) *
                 noise_gradCoord3(seed, i, j - yNSign * noise_primeY, k,
                                  x0, y0 + float(yNSign), z0);
      }
    } else {
      float b = a + az0 + az0;
      if (b > 1.0) {
        b -= 1.0;
        value += (b * b) * (b * b) *
                 noise_gradCoord3(seed, i, j, k - zNSign * noise_primeZ,
                                  x0, y0, z0 + float(zNSign));
      }
    }

    if (l == 1) break;

    ax0 = 0.5 - ax0;
    ay0 = 0.5 - ay0;
    az0 = 0.5 - az0;

    x0 = float(xNSign) * ax0;
    y0 = float(yNSign) * ay0;
    z0 = float(zNSign) * az0;

    a += (0.75 - ax0) - (ay0 + az0);

    i += (xNSign >> 1) & noise_primeX;
    j += (yNSign >> 1) & noise_primeY;
    k += (zNSign >> 1) & noise_primeZ;

    xNSign = -xNSign;
    yNSign = -yNSign;
    zNSign = -zNSign;

    seed = ~seed;
  }

  return value * 32.69428253173828125;
}

// --- 2D OpenSimplex2S -------------------------------------------------------------

float noise_singleOpenSimplex2S2(int seed, float x, float y) {
  int i = noise_fastFloor(x);
  int j = noise_fastFloor(y);
  float xi = x - float(i);
  float yi = y - float(j);

  i *= noise_primeX;
  j *= noise_primeY;
  int i1 = i + noise_primeX;
  int j1 = j + noise_primeY;

  float t = (xi + yi) * noise_g2;
  float x0 = xi - t;
  float y0 = yi - t;

  float a0 = (2.0 / 3.0) - x0 * x0 - y0 * y0;
  float value = (a0 * a0) * (a0 * a0) * noise_gradCoord2(seed, i, j, x0, y0);

  float a1 = (2.0 * (1.0 - 2.0 * noise_g2) * (1.0 / noise_g2 - 2.0)) * t +
             ((-2.0 * (1.0 - 2.0 * noise_g2) * (1.0 - 2.0 * noise_g2)) + a0);
  float x1 = x0 - (1.0 - 2.0 * noise_g2);
  float y1 = y0 - (1.0 - 2.0 * noise_g2);
  value += (a1 * a1) * (a1 * a1) * noise_gradCoord2(seed, i1, j1, x1, y1);

  float xmyi = xi - yi;
  if (t > noise_g2) {
    if (xi + xmyi > 1.0) {
      float x2 = x0 + (3.0 * noise_g2 - 2.0);
      float y2 = y0 + (3.0 * noise_g2 - 1.0);
      float a2 = (2.0 / 3.0) - x2 * x2 - y2 * y2;
      if (a2 > 0.0) {
        value += (a2 * a2) * (a2 * a2) *
                 noise_gradCoord2(seed, i + (noise_primeX << 1),
                                  j + noise_primeY, x2, y2);
      }
    } else {
      float x2 = x0 + noise_g2;
      float y2 = y0 + (noise_g2 - 1.0);
      float a2 = (2.0 / 3.0) - x2 * x2 - y2 * y2;
      if (a2 > 0.0) {
        value += (a2 * a2) * (a2 * a2) *
                 noise_gradCoord2(seed, i, j + noise_primeY, x2, y2);
      }
    }

    if (yi - xmyi > 1.0) {
      float x3 = x0 + (3.0 * noise_g2 - 1.0);
      float y3 = y0 + (3.0 * noise_g2 - 2.0);
      float a3 = (2.0 / 3.0) - x3 * x3 - y3 * y3;
      if (a3 > 0.0) {
        value += (a3 * a3) * (a3 * a3) *
                 noise_gradCoord2(seed, i + noise_primeX,
                                  j + (noise_primeY << 1), x3, y3);
      }
    } else {
      float x3 = x0 + (noise_g2 - 1.0);
      float y3 = y0 + noise_g2;
      float a3 = (2.0 / 3.0) - x3 * x3 - y3 * y3;
      if (a3 > 0.0) {
        value += (a3 * a3) * (a3 * a3) *
                 noise_gradCoord2(seed, i + noise_primeX, j, x3, y3);
      }
    }
  } else {
    if (xi + xmyi < 0.0) {
      float x2 = x0 + (1.0 - noise_g2);
      float y2 = y0 - noise_g2;
      float a2 = (2.0 / 3.0) - x2 * x2 - y2 * y2;
      if (a2 > 0.0) {
        value += (a2 * a2) * (a2 * a2) *
                 noise_gradCoord2(seed, i - noise_primeX, j, x2, y2);
      }
    } else {
      float x2 = x0 + (noise_g2 - 1.0);
      float y2 = y0 + noise_g2;
      float a2 = (2.0 / 3.0) - x2 * x2 - y2 * y2;
      if (a2 > 0.0) {
        value += (a2 * a2) * (a2 * a2) *
                 noise_gradCoord2(seed, i + noise_primeX, j, x2, y2);
      }
    }

    if (yi < xmyi) {
      float x2 = x0 - noise_g2;
      float y2 = y0 - (noise_g2 - 1.0);
      float a2 = (2.0 / 3.0) - x2 * x2 - y2 * y2;
      if (a2 > 0.0) {
        value += (a2 * a2) * (a2 * a2) *
                 noise_gradCoord2(seed, i, j - noise_primeY, x2, y2);
      }
    } else {
      float x2 = x0 + noise_g2;
      float y2 = y0 + (noise_g2 - 1.0);
      float a2 = (2.0 / 3.0) - x2 * x2 - y2 * y2;
      if (a2 > 0.0) {
        value += (a2 * a2) * (a2 * a2) *
                 noise_gradCoord2(seed, i, j + noise_primeY, x2, y2);
      }
    }
  }

  return value * 18.24196194486065;
}

// --- 3D OpenSimplex2S -------------------------------------------------------------

float noise_singleOpenSimplex2S3(int seed, float x, float y, float z) {
  int i = noise_fastFloor(x);
  int j = noise_fastFloor(y);
  int k = noise_fastFloor(z);
  float xi = x - float(i);
  float yi = y - float(j);
  float zi = z - float(k);

  i *= noise_primeX;
  j *= noise_primeY;
  k *= noise_primeZ;
  int seed2 = seed + 1293373;

  int xNMask = int(-0.5 - xi);
  int yNMask = int(-0.5 - yi);
  int zNMask = int(-0.5 - zi);

  float x0 = xi + float(xNMask);
  float y0 = yi + float(yNMask);
  float z0 = zi + float(zNMask);
  float a0 = 0.75 - x0 * x0 - y0 * y0 - z0 * z0;
  float value = (a0 * a0) * (a0 * a0) *
                noise_gradCoord3(seed, i + (xNMask & noise_primeX),
                                 j + (yNMask & noise_primeY),
                                 k + (zNMask & noise_primeZ), x0, y0, z0);

  float x1 = xi - 0.5;
  float y1 = yi - 0.5;
  float z1 = zi - 0.5;
  float a1 = 0.75 - x1 * x1 - y1 * y1 - z1 * z1;
  value += (a1 * a1) * (a1 * a1) *
           noise_gradCoord3(seed2, i + noise_primeX, j + noise_primeY,
                            k + noise_primeZ, x1, y1, z1);

  float xAFlipMask0 = float((xNMask | 1) << 1) * x1;
  float yAFlipMask0 = float((yNMask | 1) << 1) * y1;
  float zAFlipMask0 = float((zNMask | 1) << 1) * z1;
  float xAFlipMask1 = float(-2 - (xNMask << 2)) * x1 - 1.0;
  float yAFlipMask1 = float(-2 - (yNMask << 2)) * y1 - 1.0;
  float zAFlipMask1 = float(-2 - (zNMask << 2)) * z1 - 1.0;

  bool skip5 = false;
  float a2 = xAFlipMask0 + a0;
  if (a2 > 0.0) {
    float x2 = x0 - float(xNMask | 1);
    float y2 = y0;
    float z2 = z0;
    value += (a2 * a2) * (a2 * a2) *
             noise_gradCoord3(seed, i + (~xNMask & noise_primeX),
                              j + (yNMask & noise_primeY),
                              k + (zNMask & noise_primeZ), x2, y2, z2);
  } else {
    float a3 = yAFlipMask0 + zAFlipMask0 + a0;
    if (a3 > 0.0) {
      float x3 = x0;
      float y3 = y0 - float(yNMask | 1);
      float z3 = z0 - float(zNMask | 1);
      value += (a3 * a3) * (a3 * a3) *
               noise_gradCoord3(seed, i + (xNMask & noise_primeX),
                                j + (~yNMask & noise_primeY),
                                k + (~zNMask & noise_primeZ), x3, y3, z3);
    }

    float a4 = xAFlipMask1 + a1;
    if (a4 > 0.0) {
      float x4 = float(xNMask | 1) + x1;
      float y4 = y1;
      float z4 = z1;
      value += (a4 * a4) * (a4 * a4) *
               noise_gradCoord3(seed2, i + (xNMask & (noise_primeX * 2)),
                                j + noise_primeY, k + noise_primeZ,
                                x4, y4, z4);
      skip5 = true;
    }
  }

  bool skip9 = false;
  float a6 = yAFlipMask0 + a0;
  if (a6 > 0.0) {
    float x6 = x0;
    float y6 = y0 - float(yNMask | 1);
    float z6 = z0;
    value += (a6 * a6) * (a6 * a6) *
             noise_gradCoord3(seed, i + (xNMask & noise_primeX),
                              j + (~yNMask & noise_primeY),
                              k + (zNMask & noise_primeZ), x6, y6, z6);
  } else {
    float a7 = xAFlipMask0 + zAFlipMask0 + a0;
    if (a7 > 0.0) {
      float x7 = x0 - float(xNMask | 1);
      float y7 = y0;
      float z7 = z0 - float(zNMask | 1);
      value += (a7 * a7) * (a7 * a7) *
               noise_gradCoord3(seed, i + (~xNMask & noise_primeX),
                                j + (yNMask & noise_primeY),
                                k + (~zNMask & noise_primeZ), x7, y7, z7);
    }

    float a8 = yAFlipMask1 + a1;
    if (a8 > 0.0) {
      float x8 = x1;
      float y8 = float(yNMask | 1) + y1;
      float z8 = z1;
      value += (a8 * a8) * (a8 * a8) *
               noise_gradCoord3(seed2, i + noise_primeX,
                                j + (yNMask & (noise_primeY << 1)),
                                k + noise_primeZ, x8, y8, z8);
      skip9 = true;
    }
  }

  bool skipD = false;
  float aA = zAFlipMask0 + a0;
  if (aA > 0.0) {
    float xA = x0;
    float yA = y0;
    float zA = z0 - float(zNMask | 1);
    value += (aA * aA) * (aA * aA) *
             noise_gradCoord3(seed, i + (xNMask & noise_primeX),
                              j + (yNMask & noise_primeY),
                              k + (~zNMask & noise_primeZ), xA, yA, zA);
  } else {
    float aB = xAFlipMask0 + yAFlipMask0 + a0;
    if (aB > 0.0) {
      float xB = x0 - float(xNMask | 1);
      float yB = y0 - float(yNMask | 1);
      float zB = z0;
      value += (aB * aB) * (aB * aB) *
               noise_gradCoord3(seed, i + (~xNMask & noise_primeX),
                                j + (~yNMask & noise_primeY),
                                k + (zNMask & noise_primeZ), xB, yB, zB);
    }

    float aC = zAFlipMask1 + a1;
    if (aC > 0.0) {
      float xC = x1;
      float yC = y1;
      float zC = float(zNMask | 1) + z1;
      value += (aC * aC) * (aC * aC) *
               noise_gradCoord3(seed2, i + noise_primeX, j + noise_primeY,
                                k + (zNMask & (noise_primeZ << 1)),
                                xC, yC, zC);
      skipD = true;
    }
  }

  if (!skip5) {
    float a5 = yAFlipMask1 + zAFlipMask1 + a1;
    if (a5 > 0.0) {
      float x5 = x1;
      float y5 = float(yNMask | 1) + y1;
      float z5 = float(zNMask | 1) + z1;
      value += (a5 * a5) * (a5 * a5) *
               noise_gradCoord3(seed2, i + noise_primeX,
                                j + (yNMask & (noise_primeY << 1)),
                                k + (zNMask & (noise_primeZ << 1)),
                                x5, y5, z5);
    }
  }

  if (!skip9) {
    float a9 = xAFlipMask1 + zAFlipMask1 + a1;
    if (a9 > 0.0) {
      float x9 = float(xNMask | 1) + x1;
      float y9 = y1;
      float z9 = float(zNMask | 1) + z1;
      value += (a9 * a9) * (a9 * a9) *
               noise_gradCoord3(seed2, i + (xNMask & (noise_primeX * 2)),
                                j + noise_primeY,
                                k + (zNMask & (noise_primeZ << 1)),
                                x9, y9, z9);
    }
  }

  if (!skipD) {
    float aD = xAFlipMask1 + yAFlipMask1 + a1;
    if (aD > 0.0) {
      float xD = float(xNMask | 1) + x1;
      float yD = float(yNMask | 1) + y1;
      float zD = z1;
      value += (aD * aD) * (aD * aD) *
               noise_gradCoord3(seed2, i + (xNMask & (noise_primeX << 1)),
                                j + (yNMask & (noise_primeY << 1)),
                                k + noise_primeZ, xD, yD, zD);
    }
  }

  return value * 9.046026385208288;
}

// --- Single-noise public API ------------------------------------------------------
// Output of every Noise* float function is roughly in [-1, 1].

// 2D OpenSimplex2 noise.
float NoiseSimplex2(vec2 p, int seed) {
  p = noise_skew2(p);
  return noise_singleSimplex2(seed, p.x, p.y);
}

// 3D OpenSimplex2 noise.
float NoiseSimplex3(vec3 p, int seed) {
  p = noise_rotate3(p);
  return noise_singleOpenSimplex2_3(seed, p.x, p.y, p.z);
}

// 2D OpenSimplex2S noise.
float NoiseSimplex2S(vec2 p, int seed) {
  p = noise_skew2(p);
  return noise_singleOpenSimplex2S2(seed, p.x, p.y);
}

// 3D OpenSimplex2S noise.
float NoiseSimplex3S(vec3 p, int seed) {
  p = noise_rotate3(p);
  return noise_singleOpenSimplex2S3(seed, p.x, p.y, p.z);
}

// --- Fractal public API -----------------------------------------------------------
// Octave loops transcribed from the Dart _genFractalFBm2 and friends, with two
// deviations. The fractal bounding is computed inline at the top of each
// wrapper (a transcription of _calculateFractalBounding), and the
// weightedStrength amp term is dropped entirely, which is exact for the Dart
// default weightedStrength = 0 because lerp(1.0, x, 0.0) == 1.0.
//
// The skew/rotation is applied once before the octave loop, matching the Dart
// order (getNoise2 skews, then the fractal scales the skewed coords by
// lacunarity). Seed increments by 1 per octave exactly as in Dart.

float NoiseFbm2(vec2 p, int seed, int octaves, float lacunarity, float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_skew2(p);
  float x = p.x;
  float y = p.y;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_singleSimplex2(seed++, x, y);
    sum += n * amp;
    x *= lacunarity;
    y *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseFbm2S(vec2 p, int seed, int octaves, float lacunarity, float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_skew2(p);
  float x = p.x;
  float y = p.y;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_singleOpenSimplex2S2(seed++, x, y);
    sum += n * amp;
    x *= lacunarity;
    y *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseFbm3(vec3 p, int seed, int octaves, float lacunarity, float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_rotate3(p);
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_singleOpenSimplex2_3(seed++, x, y, z);
    sum += n * amp;
    x *= lacunarity;
    y *= lacunarity;
    z *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseFbm3S(vec3 p, int seed, int octaves, float lacunarity, float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_rotate3(p);
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_singleOpenSimplex2S3(seed++, x, y, z);
    sum += n * amp;
    x *= lacunarity;
    y *= lacunarity;
    z *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseRidged2(vec2 p, int seed, int octaves, float lacunarity,
                   float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_skew2(p);
  float x = p.x;
  float y = p.y;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = abs(noise_singleSimplex2(seed++, x, y));
    sum += (n * -2.0 + 1.0) * amp;
    x *= lacunarity;
    y *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseRidged2S(vec2 p, int seed, int octaves, float lacunarity,
                    float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_skew2(p);
  float x = p.x;
  float y = p.y;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = abs(noise_singleOpenSimplex2S2(seed++, x, y));
    sum += (n * -2.0 + 1.0) * amp;
    x *= lacunarity;
    y *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseRidged3(vec3 p, int seed, int octaves, float lacunarity,
                   float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_rotate3(p);
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = abs(noise_singleOpenSimplex2_3(seed++, x, y, z));
    sum += (n * -2.0 + 1.0) * amp;
    x *= lacunarity;
    y *= lacunarity;
    z *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoiseRidged3S(vec3 p, int seed, int octaves, float lacunarity,
                    float gain) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_rotate3(p);
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = abs(noise_singleOpenSimplex2S3(seed++, x, y, z));
    sum += (n * -2.0 + 1.0) * amp;
    x *= lacunarity;
    y *= lacunarity;
    z *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoisePingPong2(vec2 p, int seed, int octaves, float lacunarity,
                     float gain, float strength) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_skew2(p);
  float x = p.x;
  float y = p.y;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n =
        noise_pingPong((noise_singleSimplex2(seed++, x, y) + 1.0) * strength);
    sum += (n - 0.5) * 2.0 * amp;
    x *= lacunarity;
    y *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoisePingPong2S(vec2 p, int seed, int octaves, float lacunarity,
                      float gain, float strength) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_skew2(p);
  float x = p.x;
  float y = p.y;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_pingPong(
        (noise_singleOpenSimplex2S2(seed++, x, y) + 1.0) * strength);
    sum += (n - 0.5) * 2.0 * amp;
    x *= lacunarity;
    y *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoisePingPong3(vec3 p, int seed, int octaves, float lacunarity,
                     float gain, float strength) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_rotate3(p);
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_pingPong(
        (noise_singleOpenSimplex2_3(seed++, x, y, z) + 1.0) * strength);
    sum += (n - 0.5) * 2.0 * amp;
    x *= lacunarity;
    y *= lacunarity;
    z *= lacunarity;
    amp *= gain;
  }
  return sum;
}

float NoisePingPong3S(vec3 p, int seed, int octaves, float lacunarity,
                      float gain, float strength) {
  float bGain = abs(gain);
  float amp = bGain;
  float ampFractal = 1.0;
  for (int i = 1; i < octaves; i++) {
    ampFractal += amp;
    amp *= bGain;
  }
  float fractalBounding = 1.0 / ampFractal;

  p = noise_rotate3(p);
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float sum = 0.0;
  amp = fractalBounding;
  for (int i = 0; i < octaves; i++) {
    float n = noise_pingPong(
        (noise_singleOpenSimplex2S3(seed++, x, y, z) + 1.0) * strength);
    sum += (n - 0.5) * 2.0 * amp;
    x *= lacunarity;
    y *= lacunarity;
    z *= lacunarity;
    amp *= gain;
  }
  return sum;
}
