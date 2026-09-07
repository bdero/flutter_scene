/// The Gerstner wave field over a fixed grid of points.
///
/// Pulled out of the water component because it is the part that runs on
/// every vertex on every frame, and because none of it needs a GPU: typed
/// arrays in, typed arrays out. So it can be measured, tested against the
/// analytic field, and handed to a caller that has no mesh at all.
///
/// What makes it affordable is that a wave's phase splits in two. The term
/// `k * dot(direction, point)` depends only on where a point is, and the grid
/// does not move; the term for time is one value per wave per frame. So the
/// spatial half is tabulated once and each frame recombines it with the angle
/// addition identity. Six trig calls per point per wave become four
/// multiplies and two adds, and the loop that runs sixty times a second has
/// no trig in it at all.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/kit/environment/water_surface_component.dart'
    show GerstnerWave;

/// Displaces a fixed grid by a wave spectrum, frame after frame.
///
/// Hold one per grid: the tables behind it are what make repeated calls
/// cheap, and they are rebuilt only when the grid moves or a wave's
/// wavelength or direction changes.
/// {@category Gameplay kit}
class GerstnerField {
  Float32List? _rest;
  Float32List? _spatialSin;
  Float32List? _spatialCos;
  List<GerstnerWave>? _tabulatedFor;

  /// Points the field is set up for.
  int get pointCount => (_rest?.length ?? 0) ~/ 3;

  /// Floats currently held in the phase tables, for a caller counting bytes.
  /// Two per point per wave.
  int get tableLength => (_spatialSin?.length ?? 0) * 2;

  /// Sets the grid to displace, three floats per point.
  ///
  /// Retained rather than copied. Passing the same array again is free and
  /// keeps the tables; a caller that mutates it in place must
  /// [invalidate] instead.
  void setRest(Float32List rest) {
    if (identical(_rest, rest)) return;
    _rest = rest;
    invalidate();
  }

  /// Drops the tables, so the next [displace] rebuilds them.
  void invalidate() {
    _spatialSin = null;
    _spatialCos = null;
    _tabulatedFor = null;
  }

  /// Writes the displaced grid into [positions] and its exact normals into
  /// [normals], for [waves] at [time].
  ///
  /// Both outputs are three floats per point and must be as long as the rest
  /// grid. Waves with no amplitude or no wavelength contribute nothing and
  /// are skipped, but still count toward [normalization].
  ///
  /// [normalization] divides each wave's steepness and defaults to the length
  /// of [waves]. It is a parameter so a mesh and an analytic query of the
  /// same water can be made to agree: they have to divide by the same number
  /// or they describe two different surfaces.
  void displace(
    List<GerstnerWave> waves,
    double time,
    Float32List positions,
    Float32List normals, {
    int? normalization,
  }) {
    final rest = _rest;
    if (rest == null) return;
    final count = rest.length ~/ 3;
    final spread = normalization ?? waves.length;

    final active = <GerstnerWave>[
      for (final wave in waves)
        if (wave.amplitude > 0 && wave.wavelength > 0) wave,
    ];
    if (active.isEmpty) {
      positions.setAll(0, rest);
      for (var i = 0; i < count; i++) {
        normals[i * 3] = 0;
        normals[i * 3 + 1] = 1;
        normals[i * 3 + 2] = 0;
      }
      return;
    }

    final waveCount = active.length;
    final k = Float64List(waveCount);
    final dx = Float64List(waveCount);
    final dz = Float64List(waveCount);
    final amplitude = Float64List(waveCount);
    final q = Float64List(waveCount);
    // The time half of the phase, as its own sine and cosine: one pair per
    // wave per frame, rather than one per point per wave.
    final offsetSin = Float64List(waveCount);
    final offsetCos = Float64List(waveCount);
    for (var w = 0; w < waveCount; w++) {
      final wave = active[w];
      final wavenumber = 2 * math.pi / wave.wavelength;
      k[w] = wavenumber;
      dx[w] = wave.direction.x;
      dz[w] = wave.direction.y;
      amplitude[w] = wave.amplitude;
      q[w] = wave.steepness / (wavenumber * wave.amplitude * spread);
      final offset =
          -(wave.speed * math.sqrt(9.81 / wavenumber) * wavenumber) * time;
      offsetSin[w] = math.sin(offset);
      offsetCos[w] = math.cos(offset);
    }

    _tabulate(active, rest, count, k, dx, dz);
    final spatialSin = _spatialSin!;
    final spatialCos = _spatialCos!;

    var table = 0;
    for (var i = 0; i < count; i++) {
      final x = rest[i * 3];
      final z = rest[i * 3 + 2];
      var px = x, py = 0.0, pz = z;
      // The tangent and binormal accumulate the derivative of the
      // displacement, and their cross product is the exact surface normal:
      // finite differences over neighbours would be a second pass and would
      // still be wrong at the seams of an unwelded grid.
      var tx = 1.0, ty = 0.0, tz = 0.0;
      var bx = 0.0, by = 0.0, bz = 1.0;

      for (var w = 0; w < waveCount; w++) {
        // sin(s + o) and cos(s + o), from the tabulated sin s and cos s and
        // this frame's sin o and cos o. The same numbers the trig would have
        // produced, without calling it.
        final ss = spatialSin[table];
        final sc = spatialCos[table];
        table++;
        final sinP = ss * offsetCos[w] + sc * offsetSin[w];
        final cosP = sc * offsetCos[w] - ss * offsetSin[w];
        final a = amplitude[w];
        final qa = q[w] * a;
        final ka = k[w] * a;

        px += qa * dx[w] * cosP;
        py += a * sinP;
        pz += qa * dz[w] * cosP;

        tx += -q[w] * dx[w] * dx[w] * ka * sinP;
        ty += dx[w] * ka * cosP;
        tz += -q[w] * dx[w] * dz[w] * ka * sinP;

        bx += -q[w] * dx[w] * dz[w] * ka * sinP;
        by += dz[w] * ka * cosP;
        bz += -q[w] * dz[w] * dz[w] * ka * sinP;
      }

      positions[i * 3] = px;
      positions[i * 3 + 1] = py;
      positions[i * 3 + 2] = pz;

      var nx = by * tz - bz * ty;
      var ny = bz * tx - bx * tz;
      var nz = bx * ty - by * tx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length > 1e-9) {
        final inverse = 1 / length;
        nx *= inverse;
        ny *= inverse;
        nz *= inverse;
      } else {
        nx = 0;
        ny = 1;
        nz = 0;
      }
      normals[i * 3] = nx;
      normals[i * 3 + 1] = ny;
      normals[i * 3 + 2] = nz;
    }
  }

  /// How many doubles [sampleInto] writes: displacement xyz then normal xyz.
  static const int sampleStride = 6;

  /// Samples the spectrum at one point, writing the displacement and the
  /// surface normal into [out] as six doubles.
  ///
  /// The single-point counterpart to [displace], for the callers that have no
  /// grid: floating a boat, placing a buoy, deciding whether a swimmer's head
  /// is under. Allocation-free by design -- a scene full of floating crates
  /// samples several points each, every frame, and a vector per sample is the
  /// whole cost at that point.
  ///
  /// [x] and [z] are in the water's own frame, the same frame [displace]
  /// works in.
  static void sampleInto(
    List<GerstnerWave> waves,
    double time,
    double x,
    double z,
    Float64List out, {
    int? normalization,
  }) {
    final spread = normalization ?? waves.length;
    var dispX = 0.0, dispY = 0.0, dispZ = 0.0;
    var tx = 1.0, ty = 0.0, tz = 0.0;
    var bx = 0.0, by = 0.0, bz = 1.0;

    for (final wave in waves) {
      if (wave.amplitude <= 0 || wave.wavelength <= 0) continue;
      final k = 2 * math.pi / wave.wavelength;
      final dx = wave.direction.x;
      final dz = wave.direction.y;
      final a = wave.amplitude;
      final q = wave.steepness / (k * a * spread);
      final phase =
          k * (dx * x + dz * z) - (wave.speed * math.sqrt(9.81 / k) * k) * time;
      final cosP = math.cos(phase);
      final sinP = math.sin(phase);
      final qa = q * a;
      final ka = k * a;

      dispX += qa * dx * cosP;
      dispY += a * sinP;
      dispZ += qa * dz * cosP;

      tx += -q * dx * dx * ka * sinP;
      ty += dx * ka * cosP;
      tz += -q * dx * dz * ka * sinP;

      bx += -q * dx * dz * ka * sinP;
      by += dz * ka * cosP;
      bz += -q * dz * dz * ka * sinP;
    }

    out[0] = dispX;
    out[1] = dispY;
    out[2] = dispZ;

    var nx = by * tz - bz * ty;
    var ny = bz * tx - bx * tz;
    var nz = bx * ty - by * tx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (length > 1e-9) {
      final inverse = 1 / length;
      nx *= inverse;
      ny *= inverse;
      nz *= inverse;
    } else {
      nx = 0;
      ny = 1;
      nz = 0;
    }
    out[3] = nx;
    out[4] = ny;
    out[5] = nz;
  }

  /// Fills the phase tables for [active], unless they already hold exactly
  /// these waves over this grid.
  ///
  /// Two floats per point per wave: a 96x96 smooth grid with three waves is
  /// about 220 KB, against six trig calls per point per wave sixty times a
  /// second for as long as the water is on screen.
  void _tabulate(
    List<GerstnerWave> active,
    Float32List rest,
    int count,
    Float64List k,
    Float64List dx,
    Float64List dz,
  ) {
    final waveCount = active.length;
    final needed = count * waveCount;
    final existing = _spatialSin;
    if (existing != null &&
        existing.length == needed &&
        _sameWaves(_tabulatedFor, active)) {
      return;
    }

    final sin = Float32List(needed);
    final cos = Float32List(needed);
    var write = 0;
    for (var i = 0; i < count; i++) {
      final x = rest[i * 3];
      final z = rest[i * 3 + 2];
      for (var w = 0; w < waveCount; w++) {
        final phase = k[w] * (dx[w] * x + dz[w] * z);
        sin[write] = math.sin(phase);
        cos[write] = math.cos(phase);
        write++;
      }
    }
    _spatialSin = sin;
    _spatialCos = cos;
    // Copied, because the caller rebuilds its list every call and holding it
    // would compare a list against itself.
    _tabulatedFor = List<GerstnerWave>.of(active);
  }

  /// Whether the tables were built for these waves, on the only terms that
  /// move the spatial phase: wavelength and direction. Amplitude, steepness
  /// and speed are applied per frame and change nothing tabulated.
  static bool _sameWaves(
    List<GerstnerWave>? tabulated,
    List<GerstnerWave> now,
  ) {
    if (tabulated == null || tabulated.length != now.length) return false;
    for (var i = 0; i < now.length; i++) {
      final a = tabulated[i];
      final b = now[i];
      if (a.wavelength != b.wavelength ||
          a.direction.x != b.direction.x ||
          a.direction.y != b.direction.y) {
        return false;
      }
    }
    return true;
  }
}
