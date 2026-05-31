/// 3D rendering for Flutter, built on Flutter GPU and Impeller.
///
/// The entry points most applications need are:
///
///  * [Scene] — the scene graph root and renderer. Construct one, attach
///    [Node]s, and call [Scene.render] from a `CustomPainter` (or any
///    `dart:ui` [Canvas]).
///  * [Node] — a transform in the scene graph that may carry a [Mesh] and
///    child nodes. Load 3D models with [Node.fromAsset] (preprocessed
///    `.model` files) or [Node.fromGlbBytes] / [Node.fromGlbAsset]
///    (runtime glTF binary).
///  * [Camera] / [PerspectiveCamera] — view configuration passed to
///    [Scene.render].
///  * [Material], [PhysicallyBasedMaterial], [UnlitMaterial],
///    [Environment] — shading.
///  * [Animation], [AnimationClip], [AnimationPlayer] — playback and
///    blending of imported animations.
///
/// Flutter Scene currently requires the Flutter master channel because it
/// depends on the Flutter GPU API.
library;

export 'src/animation.dart';

export 'src/geometry/geometry.dart';
export 'src/geometry/mesh_geometry.dart'
    show GeometryBuilder, GeometryStorage, MeshGeometry;
export 'src/geometry/primitives.dart'
    show CuboidGeometry, PlaneGeometry, SphereGeometry;
export 'src/geometry/polyline_geometry.dart'
    show DashPattern, PolylineCap, PolylineGeometry, PolylineWidthMode;
export 'src/geometry/swept_geometry.dart'
    show ExtrudeGeometry, RibbonAlignment, RibbonGeometry, TubeGeometry;

export 'src/material/environment.dart';
export 'src/material/material.dart';
export 'src/material/material_parameters.dart';
export 'src/material/physically_based_material.dart';
export 'src/material/preprocessed_material.dart';
export 'src/material/shader_material.dart';
export 'src/material/unlit_material.dart';
export 'src/fmat/material_registry.dart'
    show FmatMaterialRegistry, loadFmatMaterial;

export 'src/asset_helpers.dart';
export 'src/camera.dart';
export 'src/components/component.dart';
export 'src/components/instanced_mesh_component.dart';
export 'src/components/mesh_component.dart';
export 'src/instanced_mesh.dart';
export 'src/light.dart';
export 'src/math_extensions.dart';
export 'src/mesh.dart';
export 'src/node.dart';
export 'src/physics/collider.dart';
export 'src/physics/events.dart';
export 'src/physics/joint.dart';
export 'src/physics/material.dart';
export 'src/physics/physics_world.dart';
export 'src/physics/queries.dart';
export 'src/physics/rigid_body.dart';
export 'src/physics/shape.dart';
export 'src/post_process/post_effect.dart';
export 'src/post_process/post_process.dart';
export 'src/render/env_prefilter.dart';
export 'src/runtime_importer/gltf_resources.dart' show GltfResourceResolver;
export 'src/scene_encoder.dart';
export 'src/scene_path.dart';
export 'src/scene.dart';
export 'src/shaders.dart';
export 'src/skin.dart';
export 'src/surface.dart';
export 'src/tone_mapping.dart';
