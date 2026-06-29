import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/sprite_material.dart';
import 'package:flutter_scene/src/mesh.dart';

import 'package:vector_math/vector_math.dart';

/// A single camera-facing textured quad, ready to attach to a [Node].
///
/// A `Sprite` wraps a one-instance [BillboardGeometry] and a [SpriteMaterial]
/// into a [Mesh] you assign to a node (`node.mesh = sprite.mesh`). The owning
/// node's transform positions and scales it in the world; [width]/[height]
/// are the quad's size in world units before that transform. Mutating any
/// property updates the quad in place.
///
/// For many sprites (impostor forests, particle-like effects), drive a
/// [BillboardGeometry] with a higher capacity directly instead of one
/// `Sprite` per quad.
/// {@category Geometry}
class Sprite {
  /// Creates a sprite, optionally textured.
  Sprite({
    gpu.Texture? texture,
    double width = 1.0,
    double height = 1.0,
    Vector4? color,
    double rotation = 0.0,
    BillboardFacing facing = BillboardFacing.spherical,
    SpriteBlendMode blendMode = SpriteBlendMode.alpha,
  }) : _width = width,
       _height = height,
       _color = color ?? Vector4(1, 1, 1, 1),
       _rotation = rotation {
    material = SpriteMaterial(colorTexture: texture)..blendMode = blendMode;
    geometry.facing = facing;
    mesh = Mesh(geometry, material);
    _refresh();
  }

  /// The backing billboard batch (a single instance).
  final BillboardGeometry geometry = BillboardGeometry(capacity: 1);

  /// The sprite's material; set its `colorTexture`, `tint`, or `blendMode`.
  late final SpriteMaterial material;

  /// The mesh to attach to a node (`node.mesh = sprite.mesh`).
  late final Mesh mesh;

  double _width;
  double _height;
  Vector4 _color;
  double _rotation;

  /// Quad width in world units (before the node transform).
  double get width => _width;
  set width(double value) {
    _width = value;
    _refresh();
  }

  /// Quad height in world units (before the node transform).
  double get height => _height;
  set height(double value) {
    _height = value;
    _refresh();
  }

  /// Linear RGBA color multiplied with the texture.
  Vector4 get color => _color;
  set color(Vector4 value) {
    _color = value;
    _refresh();
  }

  /// In-plane rotation in radians (ignored for
  /// [BillboardFacing.velocityStretched]).
  double get rotation => _rotation;
  set rotation(double value) {
    _rotation = value;
    _refresh();
  }

  /// How the quad orients toward the camera.
  BillboardFacing get facing => geometry.facing;
  set facing(BillboardFacing value) {
    geometry.facing = value;
  }

  void _refresh() {
    geometry.setInstance(
      0,
      center: Vector3.zero(),
      width: _width,
      height: _height,
      rotation: _rotation,
      color: _color,
    );
    geometry.commit(1);
  }
}
