import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/mesh.dart';

/// Registers the component codecs the format ships with (mesh, directional
/// light, camera) into [registry].
void registerBuiltinComponentCodecs(FsceneComponentRegistry registry) {
  registry
    ..register(MeshCodec())
    ..register(DirectionalLightCodec())
    ..register(CameraCodec());
}

/// Codec for [MeshComponent]. Realizes a mesh from `geometry` and `material`
/// resource references via the context's resource realizer.
// TODO(fscene): serialize meshes back to resources. A live geometry is opaque
// GPU buffers, so this needs a tracked source resource id or payload
// extraction (alongside the binary package format).
class MeshCodec extends ComponentCodec {
  @override
  String get type => 'mesh';

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final realizer = context.resources;
    if (realizer == null) {
      debugPrint('fscene: mesh component skipped (no resource realizer)');
      return null;
    }
    final geometry = spec.properties['geometry'];
    final material = spec.properties['material'];
    if (geometry is! ResourceRefValue || material is! ResourceRefValue) {
      debugPrint('fscene: mesh component missing geometry/material references');
      return null;
    }
    return MeshComponent(
      Mesh(realizer.geometry(geometry.id), realizer.material(material.id)),
    );
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is MeshComponent) {
      debugPrint('fscene: mesh serialization is not implemented yet');
    }
    return null;
  }
}

/// Codec for [DirectionalLightComponent]: serializes the light's parameters,
/// including its local direction (the node transform orients it at render
/// time).
class DirectionalLightCodec extends ComponentCodec {
  @override
  String get type => 'directionalLight';

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return DirectionalLightComponent(
      DirectionalLight(
        direction: readVec3(p, 'direction', Vector3(-0.3, -1.0, -0.2)),
        color: readVec3(p, 'color', Vector3(1, 1, 1)),
        intensity: readDouble(p, 'intensity', 3.0),
        castsShadow: readBool(p, 'castsShadow', false),
        shadowFadeRange: readDouble(p, 'shadowFadeRange', 2.0),
        shadowSoftness: readDouble(p, 'shadowSoftness', 0.08),
        shadowCascadeCount: readInt(p, 'shadowCascadeCount', 4),
        shadowMaxDistance: readDouble(p, 'shadowMaxDistance', 150.0),
        shadowCascadeSplitLambda: readDouble(
          p,
          'shadowCascadeSplitLambda',
          0.6,
        ),
        shadowMapResolution: readInt(p, 'shadowMapResolution', 1024),
        shadowDepthBias: readDouble(p, 'shadowDepthBias', 0.02),
        shadowNormalBias: readDouble(p, 'shadowNormalBias', 0.02),
      ),
    );
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! DirectionalLightComponent) return null;
    final l = component.light;
    return ComponentSpec(
      type,
      properties: {
        'direction': Vec3Value(l.direction.clone()),
        'color': Vec3Value(l.color.clone()),
        'intensity': DoubleValue(l.intensity),
        'castsShadow': BoolValue(l.castsShadow),
        'shadowFadeRange': DoubleValue(l.shadowFadeRange),
        'shadowSoftness': DoubleValue(l.shadowSoftness),
        'shadowCascadeCount': IntValue(l.shadowCascadeCount),
        'shadowMaxDistance': DoubleValue(l.shadowMaxDistance),
        'shadowCascadeSplitLambda': DoubleValue(l.shadowCascadeSplitLambda),
        'shadowMapResolution': IntValue(l.shadowMapResolution),
        'shadowDepthBias': DoubleValue(l.shadowDepthBias),
        'shadowNormalBias': DoubleValue(l.shadowNormalBias),
      },
    );
  }
}

/// Codec for [CameraComponent]. Handles perspective projections; the node
/// transform supplies the view.
// TODO(fscene): serialize orthographic and off-axis projections once they
// exist on CameraProjection.
class CameraCodec extends ComponentCodec {
  @override
  String get type => 'camera';

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return CameraComponent(
      projection: PerspectiveProjection(
        fovRadiansY: readDouble(p, 'fovRadiansY', 45 * degrees2Radians),
        near: readDouble(p, 'near', 0.1),
        far: readDouble(p, 'far', 1000.0),
      ),
    );
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! CameraComponent) return null;
    final proj = component.projection;
    if (proj is! PerspectiveProjection) {
      return ComponentSpec(type);
    }
    return ComponentSpec(
      type,
      properties: {
        'projection': const StringValue('perspective'),
        'fovRadiansY': DoubleValue(proj.fovRadiansY),
        'near': DoubleValue(proj.near),
        'far': DoubleValue(proj.far),
      },
    );
  }
}
