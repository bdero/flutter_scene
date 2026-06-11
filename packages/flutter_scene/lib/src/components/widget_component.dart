import 'package:flutter/widgets.dart' show Size, Widget;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/widget_texture.dart';
import 'dart:typed_data';

/// How a [WidgetComponent] receives pointer input.
enum WidgetInput {
  /// `SceneView` forwards platform pointer events automatically: presses
  /// and drags raycast into the scene, and when this component's surface is
  /// the nearest hit, events forward at the hit UV. Occluded surfaces are
  /// blocked.
  automatic,

  /// No automatic forwarding; drive input through
  /// [WidgetComponent.controller] or a `ScenePointer`.
  manual,
}

/// A live widget subtree on a scene surface.
///
/// The component owns the capture pipeline (through a [WidgetTextureController])
/// and the binding of the captured texture to a material; `SceneView` hosts
/// the widget subtree invisibly (state, tickers, and animations run normally)
/// and re-captures it per the [update] policy.
///
/// Three setup tiers share this one component:
///
/// 1. Zero config: the component creates an aspect-correct unlit
///    alpha-blended quad ([worldHeight] world units tall).
/// 2. Your [geometry] (any surface with 0..1 UVs): the component still owns
///    the material and mesh.
/// 3. Your [material] and/or a [bind] callback: the component only calls
///    [bind] when the texture changes. With [WidgetComponent.bindOnly] no
///    mesh is created at all (for surfaces that already exist, like a screen
///    inside an imported model).
///
/// The texture object is stable across captures (overwritten in place) and
/// replaced only when the capture size changes; [bind] re-fires exactly on
/// replacement.
// TODO(widget-component): WidgetInput.automatic via ScenePointer (phase 3).
// TODO(fscene): serialize the component spec (size, policy, geometry) with a
// named slot the app binds the widget tree to at runtime.
class WidgetComponent extends Component {
  /// Creates a widget surface. With no [geometry] an aspect-correct quad is
  /// created; with no [material] and no [bind], an unlit alpha-blended
  /// material bound to the capture is created.
  WidgetComponent({
    required Widget child,
    required Size size,
    double pixelRatio = 1.0,
    double worldHeight = 1.0,
    WidgetUpdatePolicy update = WidgetUpdatePolicy.onRepaint,
    this.input = WidgetInput.automatic,
    Geometry? geometry,
    Material? material,
    void Function(gpu.Texture texture)? bind,
  }) : _child = child,
       _size = size,
       _pixelRatio = pixelRatio,
       _worldHeight = worldHeight,
       _update = update,
       _geometry = geometry,
       _material = material,
       _bind = bind,
       _createsSurface = true;

  /// Creates a capture-and-bind-only component: no geometry or mesh is
  /// created, and every texture change is delivered to [bind] (which
  /// typically assigns a texture slot on an existing material).
  WidgetComponent.bindOnly({
    required Widget child,
    required Size size,
    required void Function(gpu.Texture texture) bind,
    double pixelRatio = 1.0,
    WidgetUpdatePolicy update = WidgetUpdatePolicy.onRepaint,
    this.input = WidgetInput.automatic,
  }) : _child = child,
       _size = size,
       _pixelRatio = pixelRatio,
       _worldHeight = 1.0,
       _update = update,
       _geometry = null,
       _material = null,
       _bind = bind,
       _createsSurface = false;

  /// How this surface receives pointer input.
  final WidgetInput input;

  final Widget _child;
  final Size _size;
  final double _pixelRatio;
  final double _worldHeight;
  final WidgetUpdatePolicy _update;
  final Geometry? _geometry;
  final Material? _material;
  final void Function(gpu.Texture)? _bind;
  final bool _createsSurface;

  /// The capture controller: read [WidgetTextureController.texture], listen
  /// for changes, forward pointer input, or trigger manual captures.
  final WidgetTextureController controller = WidgetTextureController();

  /// The widget subtree this component shows (hosted by `SceneView`).
  Widget get child => _child;

  /// The child's logical layout size.
  Size get size => _size;

  /// Texels per logical pixel.
  double get pixelRatio => _pixelRatio;

  /// The capture policy (see [WidgetUpdatePolicy]).
  WidgetUpdatePolicy get updatePolicy => _update;

  MeshComponent? _meshComponent;
  UnlitMaterial? _ownedMaterial;
  gpu.Texture? _boundTexture;

  @override
  void onAttach() {
    controller.addListener(_onCapture);
  }

  @override
  void onDetach() {
    controller.removeListener(_onCapture);
    final meshComponent = _meshComponent;
    if (meshComponent != null && meshComponent.isAttached) {
      node.removeComponent(meshComponent);
      _meshComponent = null;
    }
  }

  @override
  void onMount() {
    node.internalRenderScene?.addWidgetComponent(this);
  }

  @override
  void onUnmount() {
    node.internalRenderScene?.removeWidgetComponent(this);
  }

  void _onCapture() {
    final texture = controller.texture;
    if (texture == null || identical(texture, _boundTexture)) return;
    _boundTexture = texture;

    _bind?.call(texture);
    if (!_createsSurface) return;

    final material = _material;
    if (material == null) {
      // Fully owned: unlit, alpha-blended.
      final owned = _ownedMaterial ??= UnlitMaterial()
        ..alphaMode = AlphaMode.blend;
      owned.baseColorTexture = texture;
    } else if (_bind == null) {
      // Implicit binding for the known built-in materials; anything else
      // needs an explicit `bind` callback (typed material fields mean there
      // is no generic slot to assign).
      switch (material) {
        case UnlitMaterial():
          material.baseColorTexture = texture;
        case PhysicallyBasedMaterial():
          material.baseColorTexture = texture;
        default:
          throw StateError(
            'WidgetComponent cannot bind a ${material.runtimeType} '
            'implicitly; pass a `bind:` callback that assigns the texture '
            'to the right slot.',
          );
      }
    }
    _ensureSurface();
  }

  void _ensureSurface() {
    if (_meshComponent != null) return;
    final material = _material ?? _ownedMaterial!;
    final geometry = _geometry ?? _quadGeometry();
    _meshComponent = MeshComponent(Mesh(geometry, material));
    node.addComponent(_meshComponent!);
  }

  /// An aspect-correct quad facing +Z, [_worldHeight] world units tall,
  /// with v = 0 at the top (the glTF convention). Vertex order, winding,
  /// and UVs mirror the +Z face of the cuboid primitive, so the quad front
  /// faces the engine's front-face convention.
  Geometry _quadGeometry() {
    final height = _worldHeight;
    final width = height * (_size.width / _size.height);
    final hw = width / 2;
    final hh = height / 2;
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList([
        hw,
        -hh,
        0,
        -hw,
        -hh,
        0,
        -hw,
        hh,
        0,
        hw,
        hh,
        0,
      ]),
      texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
      indices: [0, 1, 3, 3, 1, 2],
    );
  }
}
