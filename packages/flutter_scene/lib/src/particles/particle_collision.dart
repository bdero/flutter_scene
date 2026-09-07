/// Particles that hit things.
///
/// Sparks that bounce off the floor and skitter, rain that stops at a roof,
/// smoke that piles against a wall instead of pouring through it. Without
/// this every effect has to be placed where nothing will intersect it, which
/// is the difference between an effect that belongs in a scene and one that
/// is floating in front of it.
///
/// The colliders are analytic shapes given to the module rather than the
/// scene's own geometry, and deliberately so. An emitter almost always cares
/// about one or two surfaces -- the ground under it, the wall behind it --
/// and a plane test is a dot product where a mesh query is a tree walk. Ten
/// thousand particles against three planes is thirty thousand dot products a
/// step; ten thousand against a level is a frame.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:vector_math/vector_math.dart';

/// What a particle does when it hits something.
/// {@category Particles}
enum ParticleCollisionResponse {
  /// Reflects, keeping [CollisionModule.restitution] of the normal speed.
  /// Sparks, gravel, bouncing debris.
  bounce,

  /// Keeps the tangential motion and drops the normal component entirely, so
  /// the particle runs along the surface. Smoke rolling out along a ceiling.
  slide,

  /// Stops dead where it landed and stays there for the rest of its life.
  /// Splatter, settling ash, snow that lies.
  stick,

  /// Dies on contact. What a spark hitting water wants, and the cheapest
  /// response there is.
  kill,
}

/// A surface particles collide against, in the emitter's own space.
///
/// Emitter space rather than world space because that is the space particles
/// live in: a collider given in world coordinates would drift the moment the
/// emitter moved.
/// {@category Particles}
sealed class ParticleCollider {
  const ParticleCollider();

  /// How far [x], [y], [z] is outside the surface, and the outward normal
  /// there, written into [out] as `(depth, nx, ny, nz)`.
  ///
  /// A negative depth means the point is clear. Written into a caller-owned
  /// buffer rather than returned, because this runs per particle per collider
  /// per step and a record per call is the whole cost at that rate.
  void probe(double x, double y, double z, double radius, Float64List out);
}

/// An infinite plane: everything on the [normal] side is outside.
/// {@category Particles}
class ParticlePlane extends ParticleCollider {
  /// A plane with the given outward [normal], [distance] along it from the
  /// origin.
  ParticlePlane({required Vector3 normal, this.distance = 0})
    : _nx = normal.x,
      _ny = normal.y,
      _nz = normal.z {
    final length = math.sqrt(_nx * _nx + _ny * _ny + _nz * _nz);
    if (length > 1e-9) {
      _nx /= length;
      _ny /= length;
      _nz /= length;
    } else {
      _nx = 0;
      _ny = 1;
      _nz = 0;
    }
  }

  /// The ground at height [y], which is what most emitters want.
  factory ParticlePlane.ground([double y = 0]) =>
      ParticlePlane(normal: Vector3(0, 1, 0), distance: y);

  double _nx, _ny, _nz;

  /// How far along the normal the plane sits.
  final double distance;

  /// The plane's outward normal.
  Vector3 get normal => Vector3(_nx, _ny, _nz);

  @override
  void probe(double x, double y, double z, double radius, Float64List out) {
    out[0] = distance + radius - (x * _nx + y * _ny + z * _nz);
    out[1] = _nx;
    out[2] = _ny;
    out[3] = _nz;
  }
}

/// A solid sphere.
/// {@category Particles}
class ParticleSphere extends ParticleCollider {
  ParticleSphere({required Vector3 centre, required this.radius})
    : _cx = centre.x,
      _cy = centre.y,
      _cz = centre.z;

  final double _cx, _cy, _cz;

  /// The sphere's radius.
  final double radius;

  /// The sphere's centre.
  Vector3 get centre => Vector3(_cx, _cy, _cz);

  @override
  void probe(double x, double y, double z, double radius, Float64List out) {
    final dx = x - _cx, dy = y - _cy, dz = z - _cz;
    final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
    out[0] = this.radius + radius - distance;
    if (distance > 1e-9) {
      final inverse = 1 / distance;
      out[1] = dx * inverse;
      out[2] = dy * inverse;
      out[3] = dz * inverse;
    } else {
      // Dead centre has no direction to leave by; up is as good as any and
      // beats a zero normal that would push nothing anywhere.
      out[1] = 0;
      out[2] = 1;
      out[3] = 0;
    }
  }
}

/// An axis-aligned box.
/// {@category Particles}
class ParticleBox extends ParticleCollider {
  ParticleBox({required Vector3 centre, required Vector3 halfExtents})
    : _cx = centre.x,
      _cy = centre.y,
      _cz = centre.z,
      _hx = halfExtents.x.abs(),
      _hy = halfExtents.y.abs(),
      _hz = halfExtents.z.abs();

  final double _cx, _cy, _cz;
  final double _hx, _hy, _hz;

  /// The box's centre.
  Vector3 get centre => Vector3(_cx, _cy, _cz);

  /// Half the box's extent on each axis.
  Vector3 get halfExtents => Vector3(_hx, _hy, _hz);

  @override
  void probe(double x, double y, double z, double radius, Float64List out) {
    // Depth on each axis; the shallowest is the face to leave by, which is
    // what stops a particle inside a box being ejected through the far side.
    final dx = _hx + radius - (x - _cx).abs();
    final dy = _hy + radius - (y - _cy).abs();
    final dz = _hz + radius - (z - _cz).abs();
    if (dx < 0 || dy < 0 || dz < 0) {
      out[0] = dx < dy ? (dx < dz ? dx : dz) : (dy < dz ? dy : dz);
      out[1] = 0;
      out[2] = 1;
      out[3] = 0;
      return;
    }
    if (dx <= dy && dx <= dz) {
      out[0] = dx;
      out[1] = x >= _cx ? 1 : -1;
      out[2] = 0;
      out[3] = 0;
    } else if (dy <= dz) {
      out[0] = dy;
      out[1] = 0;
      out[2] = y >= _cy ? 1 : -1;
      out[3] = 0;
    } else {
      out[0] = dz;
      out[1] = 0;
      out[2] = 0;
      out[3] = z >= _cz ? 1 : -1;
    }
  }
}

/// Collides particles against [colliders] after each step's integration.
///
/// Cost is the live count times the collider count, so a handful of shapes is
/// the design point. A particle is treated as a sphere of [radius], which is
/// zero by default: a point, which is what a spark is, and which a smoke puff
/// is not.
/// {@category Particles}
class CollisionModule extends ParticleModule {
  CollisionModule({
    required this.colliders,
    this.response = ParticleCollisionResponse.bounce,
    this.restitution = 0.35,
    this.friction = 0.2,
    this.radius = 0.0,
    this.lifetimeLoss = 0.0,
  });

  /// A ground plane at [y] and nothing else, which is most of what emitters
  /// need and the cheapest thing to test.
  factory CollisionModule.ground({
    double y = 0,
    ParticleCollisionResponse response = ParticleCollisionResponse.bounce,
    double restitution = 0.35,
    double friction = 0.2,
    double radius = 0.0,
    double lifetimeLoss = 0.0,
  }) => CollisionModule(
    colliders: [ParticlePlane.ground(y)],
    response: response,
    restitution: restitution,
    friction: friction,
    radius: radius,
    lifetimeLoss: lifetimeLoss,
  );

  /// The surfaces tested, in the emitter's own space.
  final List<ParticleCollider> colliders;

  /// What a hit does.
  final ParticleCollisionResponse response;

  /// How much of the normal speed a bounce keeps, `0` to `1`.
  final double restitution;

  /// How much of the tangential speed a hit sheds, `0` to `1`. Ice at zero,
  /// gravel near one.
  final double friction;

  /// The radius a particle collides with, so a puff stops short of a wall
  /// rather than half inside it.
  final double radius;

  /// How much of a particle's remaining life a hit costs, `0` to `1`.
  ///
  /// Sparks that fade as they skitter, without needing a second module to
  /// notice they landed.
  final double lifetimeLoss;

  // One probe buffer for every particle of every collider of every step.
  final Float64List _probe = Float64List(4);

  @override
  void postIntegrate(ParticleStorage storage, double dt) {
    if (colliders.isEmpty) return;
    final n = storage.aliveCount;
    final posX = storage.posX, posY = storage.posY, posZ = storage.posZ;
    final velX = storage.velX, velY = storage.velY, velZ = storage.velZ;

    for (var i = 0; i < n; i++) {
      for (final collider in colliders) {
        collider.probe(posX[i], posY[i], posZ[i], radius, _probe);
        final depth = _probe[0];
        if (depth <= 0) continue;

        if (response == ParticleCollisionResponse.kill) {
          // Ageing out is how the system already reaps, so a killed particle
          // needs no second path through the pool.
          storage.age[i] = storage.lifetime[i];
          break;
        }

        final nx = _probe[1], ny = _probe[2], nz = _probe[3];
        // Out of the surface first: a particle left overlapping would collide
        // again next step and jitter along the face.
        posX[i] += nx * depth;
        posY[i] += ny * depth;
        posZ[i] += nz * depth;

        if (response == ParticleCollisionResponse.stick) {
          velX[i] = 0;
          velY[i] = 0;
          velZ[i] = 0;
        } else {
          final along = velX[i] * nx + velY[i] * ny + velZ[i] * nz;
          if (along < 0) {
            // Split into the part going into the surface and the part along
            // it, then rebuild: the normal part reflects (or is dropped for a
            // slide) and the tangent part is what friction bites into.
            final tangentX = velX[i] - along * nx;
            final tangentY = velY[i] - along * ny;
            final tangentZ = velZ[i] - along * nz;
            final keep = 1.0 - friction.clamp(0.0, 1.0);
            final normalSpeed = response == ParticleCollisionResponse.slide
                ? 0.0
                : -along * restitution.clamp(0.0, 1.0);
            velX[i] = tangentX * keep + nx * normalSpeed;
            velY[i] = tangentY * keep + ny * normalSpeed;
            velZ[i] = tangentZ * keep + nz * normalSpeed;
          }
        }

        if (lifetimeLoss > 0) {
          final remaining = storage.lifetime[i] - storage.age[i];
          if (remaining > 0) {
            storage.age[i] += remaining * lifetimeLoss.clamp(0.0, 1.0);
          }
        }
      }
    }
  }
}
