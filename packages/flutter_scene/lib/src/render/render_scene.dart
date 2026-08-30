import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter/foundation.dart' show ValueNotifier, internal;
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/environment_volume_component.dart';
import 'package:flutter_scene/src/components/irradiance_volume_component.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/rect_area_light_component.dart';
import 'package:flutter_scene/src/components/planar_reflector_component.dart';
import 'package:flutter_scene/src/components/reflection_probe_component.dart';
import 'package:flutter_scene/src/components/semantics_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/light.dart' show ShadowCastingMode;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/render/render_layers.dart';

/// One drawable primitive in the flat render layer.
///
/// A [RenderItem] is created when a mesh-bearing node is mounted into a
/// scene and lives until that node is unmounted or its mesh changes. The
/// scene pre-pass refreshes [visible], [frustumCulled], and
/// [worldTransform] each frame; the render passes iterate the flat
/// [RenderScene] and never walk the node tree.
class RenderItem {
  RenderItem({required this.geometry, required Material material})
    : _material = material,
      geometryIdentity = identityHashCode(geometry),
      materialIdentity = identityHashCode(material);

  /// Vertex and index data for this primitive.
  final Geometry geometry;

  /// Shader and per-material parameters.
  Material get material => _material;
  set material(Material value) {
    if (identical(_material, value)) return;
    _material = value;
    materialIdentity = identityHashCode(value);
  }

  Material _material;

  /// Identity sort keys for [geometry] and [material], cached so the batching
  /// sorts in the depth prepass and shadow encoder compare plain integers.
  /// Those comparators run O(n log n) times per pass per frame, and
  /// identityHashCode is a runtime call that installs a hash in the object
  /// header on first use. [materialIdentity] is refreshed by the setter above.
  final int geometryIdentity;
  int materialIdentity;

  /// Level-of-detail state, set by an [LodComponent] when the item is
  /// registered. When non-null the encoder picks one of its levels per view
  /// (or culls) from the item's projected screen size, instead of drawing
  /// [geometry] and [material]. Those serve as the highest-detail fallback
  /// and the source of [cullBounds].
  LodSelection? lod;

  /// The `Node` that owns this item, set once when the item is registered.
  ///
  /// Typed as `Object?` to keep the render layer free of a node import (the
  /// same reason [RenderScene.widgetComponents] is loosely typed). Consumers
  /// that need the node (the object-filtered draw's node predicate and
  /// per-node color) cast it back to `Node`.
  Object? sourceNode;

  /// Whether the owning node and all of its ancestors are visible.
  /// Refreshed each frame by the scene pre-pass.
  bool visible = false;

  /// Mirrors the owning `MeshPrimitive.visible`, refreshed each frame.
  /// Ands with [visible] to gate the color passes; independent of
  /// [castsShadows], so a primitive can be excluded from color while still
  /// casting a shadow.
  bool primitiveVisible = true;

  /// Mirrors the owning node's frustum-cull opt-in, refreshed each frame.
  bool frustumCulled = true;

  /// The owning node's render layers (a 32-bit bitmask), refreshed each
  /// frame. A render pass skips this item when its view's layer mask does
  /// not intersect (`layers & layerMask == 0`).
  int layers = kRenderLayerAll;

  /// The owning node's light channels (an 8-bit bitmask), refreshed each
  /// frame. A light shades this item only when its own channel mask
  /// intersects (`light.channelMask & lightChannelMask != 0`), and a
  /// directional light's caster mask is tested against it the same way.
  int lightChannelMask = 0xFF;

  /// Whether the owning node's world transform reverses triangle winding.
  bool nodeWindingFlipped = false;

  /// Whether this item's base geometry needs reversed native winding.
  bool get windingFlipped => windingFor(geometry);

  /// Stores the owning node's transform parity.
  @internal
  void refreshWinding(bool value) => nodeWindingFlipped = value;

  /// Returns the winding parity for [drawnGeometry].
  ///
  /// A selected level of detail can use a different source convention from
  /// the item's base geometry.
  @internal
  bool windingFor(Geometry drawnGeometry) =>
      nodeWindingFlipped != drawnGeometry.sourceWindingFlipped;

  /// Mirrors the owning node's `shadowStatic` promise, refreshed each frame.
  /// Static casters render into cached shadow tiles; dynamic casters render
  /// every frame (see the shadow cache).
  bool shadowStatic = false;

  /// Whether this item goes into a shadow map.
  ///
  /// The node's [ShadowCastingMode] anded with the primitive's own
  /// `castsShadow`, refreshed each frame. Kept as a bool rather than derived
  /// from [shadowCastingMode] because the primitive gets a say too, and a
  /// primitive that opts out of casting does so whatever the node's mode is.
  bool castsShadows = true;

  /// The owning node's mode, for the two things the bool cannot say.
  ShadowCastingMode shadowCastingMode = ShadowCastingMode.on;

  /// Whether the shadow pass should draw both faces of it.
  ///
  /// What stops light leaking through geometry modelled as one sheet: the
  /// light looks for something facing it, finds nothing, and lights the room
  /// through the wall.
  bool get shadowDoubleSided =>
      castsShadows && shadowCastingMode == ShadowCastingMode.doubleSided;

  /// Whether this item draws in the colour image.
  ///
  /// False only for a shadows-only caster: a stand-in occluder that darkens
  /// what you can see without being seen itself.
  bool get drawsInColor => shadowCastingMode.drawsInColor;

  /// The owning node's joints texture and its edge length in texels, or
  /// null/0 for an unskinned node. Refreshed each frame from the node's
  /// [Skin]. Carried per item rather than on the geometry so nodes sharing
  /// one skinned geometry (clones of a skinned model) each draw with their
  /// own skeleton; every render pass applies it via [applyJointsTexture]
  /// just before binding a draw.
  gpu.Texture? jointsTexture;
  gpu.Texture? previousJointsTexture;
  int jointsTextureWidth = 0;

  /// Applies this item's joints texture to [drawnGeometry] (which differs
  /// from [geometry] when a level of detail was selected). No-op for
  /// unskinned items. Render passes call this immediately before the
  /// geometry's bind, so a geometry shared between skinned items holds the
  /// right skeleton for each draw.
  void applyJointsTexture(Geometry drawnGeometry) {
    final texture = jointsTexture;
    if (texture == null) return;
    drawnGeometry.setJointsTexture(texture, jointsTextureWidth);
  }

  /// The owning node's live morph target weights, or null for an unmorphed
  /// node. Refreshed each frame. Carried per item (like [jointsTexture]) so
  /// nodes sharing one morphed geometry each draw with their own weights.
  Float32List? morphWeights;

  /// Applies this item's morph weights to [drawnGeometry]. No-op for
  /// unmorphed items. Render passes call this immediately before the
  /// geometry's bind, next to [applyJointsTexture].
  void applyMorphWeights(Geometry drawnGeometry) {
    final weights = morphWeights;
    if (weights == null) return;
    drawnGeometry.setMorphWeights(weights);
  }

  /// World-space transform, refreshed each frame from the owning node.
  final Matrix4 worldTransform = Matrix4.identity();

  /// The previous frame's world-space transform, for motion vector rendering.
  final Matrix4 previousWorldTransform = Matrix4.identity();

  /// Whether this item moved, deformed, or changed instances this frame.
  bool isMoving = false;

  /// Start index of this item's punctual-light list in the shared per-frame
  /// light-index buffer, and how many lights follow. Refreshed each frame by
  /// the light culler; the shader loops that slice so a fragment only shades
  /// the lights that reach this item. `count` 0 means no punctual lights.
  int lightListOffset = 0;
  int lightListCount = 0;

  /// Scratch accumulator the light culler appends this item's light indices to
  /// before flattening them into the shared buffer. Reused across frames to
  /// avoid per-item allocation; cleared at the start of each cull.
  final List<int> lightScratch = [];

  /// The owning node's highlight color (linear RGBA), or null when the node
  /// is not highlighted. Refreshed each frame; the selection-outline pass
  /// draws only highlighted items, using this as the mask color.
  Vector4? highlightColor;

  /// Index into [RenderScene.items] while registered, or `-1`. Maintained
  /// by [RenderScene.add] and [RenderScene.remove] so unregistering is a
  /// swap removal instead of a list scan.
  int sceneSlot = -1;

  /// Per-instance model transforms, or `null` for a non-instanced item.
  ///
  /// When set, this item draws [geometry] / [material] once per entry,
  /// each at `worldTransform * transform`. Refreshed each frame from the
  /// owning [InstancedMeshComponent].
  List<Matrix4>? instanceTransforms;

  /// Per-instance linear RGBA multipliers matching [instanceTransforms].
  List<Vector4>? instanceColors;

  /// Packed custom per-instance attribute floats, [instanceAttributeFloats]
  /// per instance in declaration order, or null when none are supplied.
  Float32List? instanceAttributeData;

  /// Custom attribute floats each instance carries, zero unless the material
  /// declares `instance_attributes`.
  int instanceAttributeFloats = 0;

  /// Per-instance local winding parity matching [instanceTransforms].
  List<bool>? instanceWindingFlipped;

  /// Whether each instance is culled after this item's aggregate BVH test.
  bool cullInstances = false;

  /// Whether translucent instances are sorted back to front within this item.
  bool sortTransparentInstances = true;

  /// Indices accepted by the current view, or null when every instance passes.
  List<int>? visibleInstanceIndices;

  final List<int> _visibleInstanceScratch = [];

  /// Packed world-space instance AABBs, six floats per instance.
  Float32List? _instanceWorldBounds;

  /// Packed world transform and color records, twenty floats per instance plus
  /// [instanceAttributeFloats] custom attribute floats.
  @internal
  Float32List? instanceWorldData;

  /// Combined node/instance winding parity matching [instanceWorldData].
  @internal
  Uint8List? instanceWorldWindingFlipped;

  static final Matrix4 _instanceWorldScratch = Matrix4.zero();
  static final Aabb3 _instanceAabbScratch = Aabb3();

  /// Rebuilds cached world-space bounds and draw data after a node, geometry,
  /// or instance change. Static groups pay this once during setup.
  @internal
  void refreshInstanceData() {
    final instances = instanceTransforms;
    final bounds = geometry.localBounds;
    final colors = instanceColors;
    if (instances == null) {
      _instanceWorldBounds = null;
      instanceWorldData = null;
      instanceWorldWindingFlipped = null;
      return;
    }
    final boundsLength = instances.length * 6;
    final packedBounds = bounds == null || !cullInstances
        ? null
        : (_instanceWorldBounds?.length == boundsLength
              ? _instanceWorldBounds!
              : Float32List(boundsLength));
    final attributes = instanceAttributeData;
    final attributeFloats = attributes == null ? 0 : instanceAttributeFloats;
    final recordFloats = 20 + attributeFloats;
    final dataLength = instances.length * recordFloats;
    final packedData = colors == null || colors.length != instances.length
        ? null
        : (instanceWorldData?.length == dataLength
              ? instanceWorldData!
              : Float32List(dataLength));
    final packedWinding =
        instanceWorldWindingFlipped?.length == instances.length
        ? instanceWorldWindingFlipped!
        : Uint8List(instances.length);
    final retainedWinding = instanceWindingFlipped;
    for (var i = 0; i < instances.length; i++) {
      _instanceWorldScratch
        ..setFrom(worldTransform)
        ..multiply(instances[i]);
      if (packedBounds != null) {
        _instanceAabbScratch
          ..copyFrom(bounds!)
          ..transform(_instanceWorldScratch);
        final offset = i * 6;
        packedBounds[offset] = _instanceAabbScratch.min.x;
        packedBounds[offset + 1] = _instanceAabbScratch.min.y;
        packedBounds[offset + 2] = _instanceAabbScratch.min.z;
        packedBounds[offset + 3] = _instanceAabbScratch.max.x;
        packedBounds[offset + 4] = _instanceAabbScratch.max.y;
        packedBounds[offset + 5] = _instanceAabbScratch.max.z;
      }
      if (packedData != null) {
        final offset = i * recordFloats;
        packedData.setAll(offset, _instanceWorldScratch.storage);
        packedData.setAll(offset + 16, colors![i].storage);
        if (attributeFloats > 0) {
          packedData.setRange(
            offset + 20,
            offset + recordFloats,
            attributes!,
            i * attributeFloats,
          );
        }
      }
      final instanceFlipped =
          retainedWinding?[i] ?? (instances[i].determinant() < 0);
      packedWinding[i] = windingFlipped != instanceFlipped ? 1 : 0;
    }
    _instanceWorldBounds = packedBounds;
    instanceWorldData = packedData;
    instanceWorldWindingFlipped = packedWinding;
  }

  /// Refreshes [visibleInstanceIndices] and returns whether anything remains.
  @internal
  bool cullVisibleInstances(Frustum frustum, List<Plane> additionalPlanes) {
    final instances = instanceTransforms;
    final bounds = geometry.localBounds;
    if (!cullInstances || instances == null || bounds == null) {
      visibleInstanceIndices = null;
      return true;
    }

    final aggregate = worldBounds;
    if (aggregate != null &&
        _insidePlane(aggregate, frustum.plane0) &&
        _insidePlane(aggregate, frustum.plane1) &&
        _insidePlane(aggregate, frustum.plane2) &&
        _insidePlane(aggregate, frustum.plane3) &&
        _insidePlane(aggregate, frustum.plane4) &&
        _insidePlane(aggregate, frustum.plane5)) {
      var insideAdditionalPlanes = true;
      for (final plane in additionalPlanes) {
        if (!_insidePlane(aggregate, plane)) {
          insideAdditionalPlanes = false;
          break;
        }
      }
      if (insideAdditionalPlanes) {
        visibleInstanceIndices = null;
        return true;
      }
    }

    if (_instanceWorldBounds?.length != instances.length * 6) {
      refreshInstanceData();
    }
    final instanceWorldBounds = _instanceWorldBounds!;

    final visible = _visibleInstanceScratch..clear();
    for (var i = 0; i < instances.length; i++) {
      final offset = i * 6;
      if (_outsidePlane(instanceWorldBounds, offset, frustum.plane0) ||
          _outsidePlane(instanceWorldBounds, offset, frustum.plane1) ||
          _outsidePlane(instanceWorldBounds, offset, frustum.plane2) ||
          _outsidePlane(instanceWorldBounds, offset, frustum.plane3) ||
          _outsidePlane(instanceWorldBounds, offset, frustum.plane4) ||
          _outsidePlane(instanceWorldBounds, offset, frustum.plane5)) {
        continue;
      }
      var outside = false;
      for (final plane in additionalPlanes) {
        if (_outsidePlane(instanceWorldBounds, offset, plane)) {
          outside = true;
          break;
        }
      }
      if (!outside) visible.add(i);
    }
    visibleInstanceIndices = visible.length == instances.length
        ? null
        : visible;
    return visible.isNotEmpty;
  }

  static bool _outsidePlane(Float32List bounds, int offset, Plane plane) {
    final normal = plane.normal;
    final x = bounds[offset + (normal.x < 0 ? 0 : 3)];
    final y = bounds[offset + (normal.y < 0 ? 1 : 4)];
    final z = bounds[offset + (normal.z < 0 ? 2 : 5)];
    return normal.x * x + normal.y * y + normal.z * z + plane.constant < 0;
  }

  static bool _insidePlane(Aabb3 bounds, Plane plane) {
    final normal = plane.normal;
    final x = normal.x < 0 ? bounds.max.x : bounds.min.x;
    final y = normal.y < 0 ? bounds.max.y : bounds.min.y;
    final z = normal.z < 0 ? bounds.max.z : bounds.min.z;
    return normal.x * x + normal.y * y + normal.z * z + plane.constant >= 0;
  }

  /// Node-local aggregate AABB covering every instance, used to
  /// frustum-cull an instanced item as a single unit.
  ///
  /// `null` means the instanced item is unbounded and always drawn.
  /// Ignored for non-instanced items.
  Aabb3? instanceBounds;

  /// The local-space AABB this item is frustum-culled against, or `null`
  /// when it should be treated as always visible.
  ///
  /// An instanced item uses its [instanceBounds]; a regular item uses its
  /// geometry's local bounds.
  Aabb3? get cullBounds =>
      instanceTransforms != null ? instanceBounds : geometry.localBounds;

  /// World-space AABB ([cullBounds] transformed by [worldTransform]), or
  /// `null` when the item is unbounded.
  ///
  /// Refreshed each frame by [refreshWorldBounds] and consumed by the
  /// scene's spatial structure.
  Aabb3? worldBounds;

  // Reused across [refreshWorldBounds] calls so a steady-state refresh
  // allocates nothing.
  static final Aabb3 _worldBoundsScratch = Aabb3();

  /// Recomputes [worldBounds] from [cullBounds] and [worldTransform], and
  /// returns whether the value changed since the previous call.
  ///
  /// Call after refreshing [worldTransform]. The owning component uses
  /// the return value to know when the spatial structure is stale.
  bool refreshWorldBounds() {
    final local = cullBounds;
    if (local == null) {
      if (worldBounds == null) return false;
      worldBounds = null;
      return true;
    }
    _worldBoundsScratch
      ..copyFrom(local)
      ..transform(worldTransform);
    final current = worldBounds;
    if (current == null) {
      worldBounds = Aabb3.copy(_worldBoundsScratch);
      return true;
    }
    if (current.min == _worldBoundsScratch.min &&
        current.max == _worldBoundsScratch.max) {
      return false;
    }
    current.copyFrom(_worldBoundsScratch);
    return true;
  }
}

/// The retained render layer for a `Scene`: every [RenderItem], plus a
/// spatial structure the render passes cull against.
///
/// The node graph registers and unregisters items as mesh-bearing nodes
/// are mounted into and out of the scene. Bounded items are placed in a
/// [Bvh]; unbounded items (no [RenderItem.worldBounds], or
/// [RenderItem.frustumCulled] off) are always visited.
class RenderScene {
  /// The scene that owns this, set by [Scene] at construction.
  ///
  /// The back-reference a component needs to reach scene-wide state its own
  /// node cannot see: the skybox a storm driver flashes, the environment a
  /// look depends on. Null only for a render scene built outside a [Scene]
  /// (the tests' stub graphs).
  Object? owner;

  /// Every registered render item, in no particular order.
  final List<RenderItem> items = [];

  /// The directional lights contributed by mounted
  /// [DirectionalLightComponent]s, in registration order.
  final List<DirectionalLightComponent> directionalLights = [];

  /// Selects the directional light used by features that currently accept one
  /// light, including cascaded shadows and sun scattering.
  ///
  /// Higher explicit priority wins. Equal priorities use emitted luminance,
  /// matching the usual dominant-light fallback. Registration order is only
  /// the final tie breaker for otherwise equivalent lights.
  // TODO(directional-shadows): allocate cascade atlas slots per light so more
  // than one directional light can cast shadows in the same view.
  DirectionalLightComponent? get primaryDirectionalLight {
    DirectionalLightComponent? best;
    var bestPriority = 0;
    var bestStrength = 0.0;
    for (final component in directionalLights) {
      // A hidden node's light does not contribute.
      if (!component.node.internalEffectiveVisible) continue;
      final light = component.light;
      final strength =
          light.intensity *
          (light.color.x * 0.2126 +
              light.color.y * 0.7152 +
              light.color.z * 0.0722);
      if (best == null ||
          light.priority > bestPriority ||
          (light.priority == bestPriority && strength > bestStrength)) {
        best = component;
        bestPriority = light.priority;
        bestStrength = strength;
      }
    }
    return best;
  }

  /// Registers [light] as an active directional light. Called by a
  /// [DirectionalLightComponent] when its owning node mounts.
  void addDirectionalLight(DirectionalLightComponent light) {
    directionalLights.add(light);
  }

  /// The mounted widget components, in registration order. `SceneView`
  /// listens to [widgetComponentsChanged] and hosts each component's widget
  /// subtree invisibly.
  final List<Object> widgetComponents = [];

  /// Bumped whenever [widgetComponents] changes.
  final ValueNotifier<int> widgetComponentsChanged = ValueNotifier<int>(0);

  /// Registers a mounted widget component (typed as Object to keep this
  /// render-layer file free of a widgets dependency).
  void addWidgetComponent(Object component) {
    widgetComponents.add(component);
    widgetComponentsChanged.value++;
  }

  /// Unregisters an unmounted widget component.
  void removeWidgetComponent(Object component) {
    widgetComponents.remove(component);
    widgetComponentsChanged.value++;
  }

  /// The mounted [SemanticsComponent]s, in registration order. `SceneView`
  /// projects each one's node bounds into its semantics tree while
  /// assistive technology is active.
  final List<SemanticsComponent> semanticsComponents = [];

  /// Bumped whenever [semanticsComponents] changes.
  final ValueNotifier<int> semanticsComponentsChanged = ValueNotifier<int>(0);

  /// Registers a mounted semantics component. Called by a
  /// [SemanticsComponent] when its owning node mounts.
  void addSemanticsComponent(SemanticsComponent component) {
    semanticsComponents.add(component);
    semanticsComponentsChanged.value++;
  }

  /// Unregisters an unmounted semantics component.
  void removeSemanticsComponent(SemanticsComponent component) {
    semanticsComponents.remove(component);
    semanticsComponentsChanged.value++;
  }

  /// Unregisters [light]. Called when its owning node unmounts.
  void removeDirectionalLight(DirectionalLightComponent light) {
    directionalLights.remove(light);
  }

  /// The point lights contributed by mounted [PointLightComponent]s, in
  /// registration order. Collected into the per-frame punctual light buffer.
  final List<PointLightComponent> pointLights = [];

  /// Registers [light] as an active point light. Called by a
  /// [PointLightComponent] when its owning node mounts.
  void addPointLight(PointLightComponent light) {
    pointLights.add(light);
  }

  /// Unregisters [light]. Called when its owning node unmounts.
  void removePointLight(PointLightComponent light) {
    pointLights.remove(light);
  }

  /// The rect area lights contributed by mounted [RectAreaLightComponent]s,
  /// in registration order. Collected into the per-frame punctual light
  /// buffer.
  final List<RectAreaLightComponent> rectAreaLights = [];

  /// Registers [light] as an active rect area light. Called by a
  /// [RectAreaLightComponent] when its owning node mounts.
  void addRectAreaLight(RectAreaLightComponent light) {
    rectAreaLights.add(light);
  }

  /// Unregisters [light]. Called when its owning node unmounts.
  void removeRectAreaLight(RectAreaLightComponent light) {
    rectAreaLights.remove(light);
  }

  /// The spot lights contributed by mounted [SpotLightComponent]s, in
  /// registration order. Collected into the per-frame punctual light buffer.
  final List<SpotLightComponent> spotLights = [];

  /// Registers [light] as an active spot light. Called by a
  /// [SpotLightComponent] when its owning node mounts.
  void addSpotLight(SpotLightComponent light) {
    spotLights.add(light);
  }

  /// Unregisters [light]. Called when its owning node unmounts.
  void removeSpotLight(SpotLightComponent light) {
    spotLights.remove(light);
  }

  /// The environment volumes contributed by mounted
  /// [EnvironmentVolumeComponent]s, in registration order. Folded into the
  /// scene's environment blend by camera position each frame.
  final List<EnvironmentVolumeComponent> environmentVolumeComponents = [];

  /// Registers [volume] as an active environment volume. Called by an
  /// [EnvironmentVolumeComponent] when its owning node mounts.
  void addEnvironmentVolumeComponent(EnvironmentVolumeComponent volume) {
    environmentVolumeComponents.add(volume);
  }

  /// Unregisters [volume]. Called when its owning node unmounts.
  void removeEnvironmentVolumeComponent(EnvironmentVolumeComponent volume) {
    environmentVolumeComponents.remove(volume);
  }

  /// The irradiance volumes contributed by mounted
  /// [IrradianceVolumeComponent]s, in registration order. At most one is
  /// active per frame, chosen by priority among those containing the camera.
  final List<IrradianceVolumeComponent> irradianceVolumeComponents = [];

  /// Registers [volume] as an active irradiance volume. Called by an
  /// [IrradianceVolumeComponent] when its owning node mounts.
  void addIrradianceVolumeComponent(IrradianceVolumeComponent volume) {
    irradianceVolumeComponents.add(volume);
  }

  /// Unregisters [volume]. Called when its owning node unmounts.
  void removeIrradianceVolumeComponent(IrradianceVolumeComponent volume) {
    irradianceVolumeComponents.remove(volume);
  }

  /// The reflection probes contributed by mounted
  /// [ReflectionProbeComponent]s, in registration order. Each contributes
  /// its captured environment to the image-based-lighting cross-fade by
  /// camera position, and pending captures render before the frame's views.
  final List<ReflectionProbeComponent> reflectionProbeComponents = [];

  /// Registers [probe] as an active reflection probe. Called by a
  /// [ReflectionProbeComponent] when its owning node mounts.
  void addReflectionProbeComponent(ReflectionProbeComponent probe) {
    reflectionProbeComponents.add(probe);
  }

  /// Unregisters [probe]. Called when its owning node unmounts.
  void removeReflectionProbeComponent(ReflectionProbeComponent probe) {
    reflectionProbeComponents.remove(probe);
  }

  /// The planar reflectors contributed by mounted
  /// [PlanarReflectorComponent]s, in registration order. Each visible one
  /// renders a per-frame mirrored scene capture before the primary view's
  /// scene pass.
  final List<PlanarReflectorComponent> planarReflectorComponents = [];

  /// Registers [reflector] as an active planar reflector. Called by a
  /// [PlanarReflectorComponent] when its owning node mounts.
  void addPlanarReflectorComponent(PlanarReflectorComponent reflector) {
    planarReflectorComponents.add(reflector);
  }

  /// Unregisters [reflector]. Called when its owning node unmounts.
  void removePlanarReflectorComponent(PlanarReflectorComponent reflector) {
    planarReflectorComponents.remove(reflector);
  }

  /// The mounted [CameraComponent]s, in mount order. The first is the
  /// auto-promoted primary when no [cameraOverride] is set.
  final List<CameraComponent> cameras = [];

  /// An explicit primary-camera override, set through `Scene.camera`. When
  /// non-null it wins over auto-promotion; when null the primary resolves to
  /// the first mounted [CameraComponent], or null when there are none.
  Camera? cameraOverride;

  /// Registers [camera] as a mounted camera. Called by a [CameraComponent]
  /// when its owning node mounts.
  void addCamera(CameraComponent camera) {
    cameras.add(camera);
  }

  /// Unregisters [camera]. Called when its owning node unmounts.
  void removeCamera(CameraComponent camera) {
    cameras.remove(camera);
  }

  /// The scene's primary camera: the explicit [cameraOverride] if set, else
  /// the first mounted [CameraComponent]'s camera, else null.
  Camera? get primaryCamera =>
      cameraOverride ?? (cameras.isEmpty ? null : cameras.first.toCamera());

  Bvh _bvh = Bvh.build([]);
  int _structureRevision = 0;
  int _staticShadowRevision = 0;

  /// Changes when render items are added or removed.
  int get structureRevision => _structureRevision;

  /// Changes when a retained static shadow caster changes.
  int get staticShadowRevision => _staticShadowRevision;

  /// Invalidates the cached static-caster fingerprint.
  void markStaticShadowDirty() {
    _staticShadowRevision++;
  }

  /// The spatial structure over the bounded items, current after
  /// [rebuildIfDirty]. Used by the light culler to scatter each light onto the
  /// items it reaches.
  Bvh get bvh => _bvh;

  final List<RenderItem> _alwaysVisible = [];

  // The BVH needs a full rebuild: an item was added or removed, or an
  // item's BVH membership changed.
  bool _structureDirty = true;

  // A bounded item moved; the BVH can refit instead of rebuilding.
  bool _boundsDirty = false;

  void add(RenderItem item) {
    item.sceneSlot = items.length;
    items.add(item);
    _structureRevision++;
    _structureDirty = true;
  }

  void remove(RenderItem item) {
    final slot = item.sceneSlot;
    if (slot < 0) return;
    final last = items.removeLast();
    if (!identical(last, item)) {
      items[slot] = last;
      last.sceneSlot = slot;
    }
    item.sceneSlot = -1;
    _structureRevision++;
    _structureDirty = true;
  }

  /// Flags the BVH for a full rebuild. Called when an item's BVH
  /// membership changed (its `frustumCulled` flag toggled, or it became
  /// bounded or unbounded).
  void markBvhStructureDirty() {
    _structureDirty = true;
  }

  /// Flags the BVH for a refit. Called when a bounded item moved but the
  /// item set and membership are unchanged.
  void markBvhBoundsDirty() {
    _boundsDirty = true;
  }

  /// Brings the spatial structure up to date with the current items.
  /// Call once per frame, after the pre-pass and before the render
  /// passes. Rebuilds on a structural change, otherwise refits when an
  /// item moved, otherwise does nothing.
  void rebuildIfDirty() {
    if (_structureDirty) {
      _structureDirty = false;
      _boundsDirty = false;
      _alwaysVisible.clear();
      final bounded = <RenderItem>[];
      for (final item in items) {
        if (item.frustumCulled && item.worldBounds != null) {
          bounded.add(item);
        } else {
          _alwaysVisible.add(item);
        }
      }
      _bvh = Bvh.build(bounded);
    } else if (_boundsDirty) {
      _boundsDirty = false;
      _bvh.refit();
    }
  }

  /// Visits every item potentially visible to [frustum]: the bounded
  /// items whose world AABB intersects it, plus every always-visible
  /// item.
  void cull(
    Frustum frustum,
    void Function(RenderItem) visit, {
    List<Plane> additionalPlanes = const [],
  }) {
    _bvh.query(frustum, visit, additionalPlanes: additionalPlanes);
    for (final item in _alwaysVisible) {
      visit(item);
    }
  }

  /// Collects material inputs requested by this view's frustum candidates.
  Set<RenderInput> collectMaterialInputs(
    Frustum frustum, {
    int layerMask = kRenderLayerAll,
    List<Plane> additionalPlanes = const [],
    bool includeOffscreen = false,
  }) {
    final inputs = <RenderInput>{};
    void collect(RenderItem item) {
      if (!item.visible ||
          !item.primitiveVisible ||
          !item.drawsInColor ||
          (item.layers & layerMask) == 0) {
        return;
      }
      inputs.addAll(item.material.sceneInputs);
      final lod = item.lod;
      if (lod != null) {
        for (final level in lod.levels) {
          inputs.addAll(level.material.sceneInputs);
        }
      }
    }

    if (includeOffscreen) {
      for (final item in items) {
        collect(item);
      }
    } else {
      cull(frustum, collect, additionalPlanes: additionalPlanes);
    }
    return inputs;
  }

  /// Collects material inputs without view-dependent culling.
  Set<RenderInput> collectAllMaterialInputs() {
    final inputs = <RenderInput>{};
    for (final item in items) {
      inputs.addAll(item.material.sceneInputs);
      final lod = item.lod;
      if (lod != null) {
        for (final level in lod.levels) {
          inputs.addAll(level.material.sceneInputs);
        }
      }
    }
    return inputs;
  }
}
