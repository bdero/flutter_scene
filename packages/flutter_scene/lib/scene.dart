/// 3D rendering for Flutter, built on Flutter GPU and Impeller.
///
/// The entry points most applications need are:
///
///  * [Scene] — the scene graph root and renderer. Construct one, attach
///    [Node]s, and call [Scene.render] from a `CustomPainter` (or any
///    `dart:ui` [Canvas]).
///  * [Node] — a transform in the scene graph that may carry a [Mesh] and
///    child nodes. Load 3D content with [loadScene] (preprocessed
///    `.fsceneb` packages, by source path) or [Node.fromGlbBytes] /
///    [Node.fromGlbAsset] (runtime glTF binary).
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

export 'src/animation.dart' show Animation, AnimationClip, AnimationPlayer;

export 'src/geometry/geometry.dart'
    show Geometry, SkinnedGeometry, UnskinnedGeometry;
export 'src/geometry/mesh_geometry.dart'
    show GeometryBuilder, GeometryStorage, MeshGeometry;
export 'src/geometry/primitives.dart'
    show CuboidGeometry, PlaneGeometry, SphereGeometry, WedgeGeometry;
export 'src/geometry/polyline_geometry.dart'
    show DashPattern, PolylineCap, PolylineGeometry, PolylineWidthMode;
export 'src/geometry/swept_geometry.dart'
    show ExtrudeGeometry, RibbonAlignment, RibbonGeometry, TubeGeometry;

export 'src/material/environment.dart'
    show EnvironmentMap, environmentAssetPathOf, kDiffuseShCoefficientCount;
export 'src/material/material.dart' show Material;
export 'src/material/material_parameters.dart' show MaterialParameters;
export 'src/material/physically_based_material.dart'
    show AlphaMode, PhysicallyBasedMaterial;
export 'src/material/preprocessed_material.dart' show PreprocessedMaterial;
export 'src/material/preprocessed_sky.dart' show PreprocessedSky;
export 'src/material/shader_material.dart' show ShaderMaterial;
export 'src/material/unlit_material.dart' show UnlitMaterial;
export 'src/fmat/material_registry.dart'
    show FmatMaterialRegistry, loadFmatMaterial, loadFmatSky;
export 'src/importer/scene_registry.dart'
    show SceneRegistry, SceneReloadCallback, loadScene, loadSceneSubtree;

export 'src/ambient_occlusion.dart'
    show AmbientOcclusionSettings, SpecularAmbientOcclusionMode;
export 'src/asset_helpers.dart'
    show
        gpuTextureFromAsset,
        gpuTextureFromImage,
        imageFromAsset,
        imageFromBytes;
export 'src/camera.dart'
    show Camera, CameraProjection, PerspectiveCamera, PerspectiveProjection;
export 'src/components/camera_component.dart' show CameraComponent;
export 'src/components/component.dart' show Component;
export 'src/components/directional_light_component.dart'
    show DirectionalLightComponent;
export 'src/components/instanced_mesh_component.dart'
    show InstancedMeshComponent;
export 'src/components/mesh_component.dart' show MeshComponent;
export 'src/components/widget_component.dart' show WidgetComponent, WidgetInput;
export 'src/instanced_mesh.dart' show InstancedMesh;
export 'src/light.dart' show DirectionalLight, Lighting, ShadowCascade;
export 'src/render/render_layers.dart'
    show kRenderLayerAll, kRenderLayerDefault;
export 'src/render_texture.dart'
    show RenderTexture, RenderTextureSampling, RenderTextureUpdate;
export 'src/render_view.dart' show RenderView;
export 'src/math_extensions.dart' show QuaternionSlerp, Vector3Lerp;
export 'src/mesh.dart' show Mesh, MeshPrimitive;
export 'src/node.dart' show Node;
export 'src/physics/basic/basic_collider.dart' show BasicCollider;
export 'src/physics/basic/basic_kinematic_body.dart' show BasicKinematicBody;
export 'src/physics/basic/basic_world.dart' show BasicPhysicsWorld;
export 'src/physics/collider.dart' show Collider;
export 'src/physics/events.dart'
    show
        CollisionBegan,
        CollisionEnded,
        CollisionEvent,
        ContactPoint,
        TriggerEntered,
        TriggerExited;
export 'src/physics/joint.dart'
    show
        FixedJoint,
        GenericJoint,
        Joint,
        JointAxis,
        JointAxisConfig,
        JointAxisMotion,
        JointMotor,
        JointMotorModel,
        PrismaticJoint,
        RevoluteJoint,
        SphericalJoint;
export 'src/physics/material.dart' show CombineRule, PhysicsMaterial;
export 'src/physics/physics_world.dart' show PhysicsWorld;
export 'src/physics/queries.dart' show OverlapHit, RaycastHit, ShapeCastHit;
export 'src/physics/rigid_body.dart' show BodyType, RigidBody;
export 'src/physics/shape.dart'
    show
        BoxShape,
        CapsuleShape,
        CompoundChild,
        CompoundShape,
        ConvexHullShape,
        CylinderShape,
        HeightFieldShape,
        Shape,
        SphereShape,
        TriMeshShape;
export 'src/post_process/post_effect.dart' show PostEffect, PostInsertion;
export 'src/post_process/post_process.dart'
    show
        BloomSettings,
        ChromaticAberrationSettings,
        ColorGradingSettings,
        FilmGrainSettings,
        PostProcessSettings,
        VignetteSettings;
export 'src/render/env_prefilter.dart' show prefilterEquirectRadiance;
export 'src/runtime_importer/gltf_resources.dart' show GltfResourceResolver;
export 'src/scene_path.dart'
    show BezierPath, CatmullRomPath, PolylinePath, ScenePath, ScenePathFrame;
export 'src/raycast.dart' show SceneRaycastHit, raycastNode, raycastNodeAll;
export 'src/scene_pointer.dart' show ScenePointer;
export 'src/scene.dart' show AntiAliasingMode, Scene, SceneGraph;
export 'src/widget_texture.dart'
    show WidgetTexture, WidgetTextureController, WidgetUpdatePolicy;
export 'src/shaders.dart' show baseShaderLibrary, loadBaseShaderLibrary;
export 'src/skin.dart' show Skin;
export 'src/sky_environment.dart' show SkyEnvironment, SkyEnvironmentRefresh;
export 'src/sky_sources.dart' show GradientSkySource, PhysicalSkySource;
export 'src/skybox.dart'
    show EnvironmentSkySource, ShaderSkySource, SkySource, Skybox;
export 'src/surface.dart' show Surface;
export 'src/widgets/render_texture_view.dart' show RenderTextureView;
export 'src/widgets/scene_view.dart'
    show SceneCameraBuilder, SceneScope, SceneTickCallback, SceneView;
export 'src/tone_mapping.dart' show ToneMappingMode;
