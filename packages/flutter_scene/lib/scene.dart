/// 3D rendering for Flutter, built on Flutter GPU and Impeller.
///
/// The entry points most applications need are:
///
///  * [Scene], the scene graph root and renderer. Construct one, attach
///    [Node]s, and display it with the [SceneView] widget, which drives the
///    per-frame render loop for you. [Scene.render] is the lower-level path
///    for drawing into a `dart:ui` [Canvas] yourself.
///  * [Node], a transform in the scene graph (`position`, `rotation`,
///    `scale`, or the whole `localTransform` matrix) that may carry a [Mesh]
///    and child nodes. Load 3D content with [loadScene] (preprocessed
///    `.fsceneb` packages, by source path) or [Node.fromGlbBytes] /
///    [Node.fromGlbAsset] (runtime glTF binary).
///  * [Camera] / [PerspectiveCamera], view configuration passed to
///    [SceneView] or [Scene.render].
///  * [Material], [PhysicallyBasedMaterial], [UnlitMaterial] and
///    [EnvironmentMap], shading.
///  * [Animation], [AnimationClip], [AnimationPlayer], playback and
///    blending of imported animations.
///
/// Flutter Scene needs Flutter 3.47 (stable) or newer. Rendering goes through
/// the Flutter GPU API, which every platform except the web turns on once per
/// project (see the package README).
library;

export 'src/animation.dart'
    show Animation, AnimationClip, AnimationMask, AnimationPlayer;
export 'src/animation/animator.dart'
    show
        Animator,
        AnimatorComparison,
        AnimatorCondition,
        AnimatorLayer,
        AnimatorLayerWeights,
        AnimatorMotion,
        AnimatorParameters,
        AnimatorState,
        AnimatorTransition,
        BlendMotion,
        BlendMotion2D,
        BlendStop,
        BlendStop2D,
        ClipMotion;
export 'src/animation/animator_component.dart' show AnimatorComponent;
export 'src/animation/ik_constraint_component.dart' show IkConstraintComponent;
export 'src/animation/two_bone_ik.dart'
    show TwoBoneSolution, solveTwoBoneIk, twoBoneMidAfter, twoBoneTipAfter;

export 'src/geometry/billboard_geometry.dart'
    show BillboardFacing, BillboardGeometry;
export 'src/geometry/geometry.dart'
    show Geometry, GeometryBufferArena, SkinnedGeometry, UnskinnedGeometry;
export 'src/geometry/line_segments_geometry.dart' show LineSegmentsGeometry;
export 'src/geometry/vertex_layout.dart'
    show
        VertexAttributeDescriptor,
        VertexBufferDescriptor,
        VertexLayoutDescriptor;
export 'src/geometry/mesh_data.dart'
    show
        LineSegmentData,
        MeshAttributeData,
        MeshData,
        MeshTriangle,
        UnweldAttribute;
export 'src/geometry/mesh_geometry.dart'
    show GeometryBuilder, GeometryStorage, MeshGeometry;
export 'src/geometry/morph_targets.dart'
    show MorphTargetData, kMaxGpuMorphTargets;
export 'src/geometry/morphed_geometry.dart'
    show MorphedSkinnedGeometry, MorphedUnskinnedGeometry;
export 'src/geometry/primitives.dart'
    show
        CapsuleGeometry,
        CuboidGeometry,
        CylinderGeometry,
        DiscGeometry,
        IcosphereGeometry,
        PlaneGeometry,
        RingGeometry,
        SphereGeometry,
        TorusGeometry,
        WedgeGeometry;
export 'src/geometry/terrain.dart'
    show HeightField, TerrainGeometry, buildTerrainArrays;
export 'src/kit/scatter/scatter_layer.dart'
    show ScatterBrush, ScatterLayer, ScatterPlacement, scatterInBrush;
export 'src/geometry/terrain_brush.dart'
    show TerrainBrush, TerrainBrushKind, sculptTerrain;
export 'src/geometry/terrain_splat.dart'
    show TerrainSplatMap, paintTerrainSplat, terrainSplatLayers;
export 'src/geometry/polyline_geometry.dart'
    show DashPattern, PolylineCap, PolylineGeometry, PolylineWidthMode;
export 'src/geometry/swept_geometry.dart'
    show ExtrudeGeometry, RibbonAlignment, RibbonGeometry, TubeGeometry;

export 'src/environment_settings.dart' show EnvironmentSettings;
export 'src/environment_volume.dart'
    show
        BoxVolumeBounds,
        EnvironmentVolume,
        EnvironmentVolumeBounds,
        SphereVolumeBounds,
        blendEnvironmentVolumes;
export 'src/material/diffuse_sh.dart'
    show
        ShDiffuseSummary,
        describeDiffuseSphericalHarmonics,
        encodeDiffuseShSidecar,
        evaluateDiffuseSphericalHarmonics,
        kDiffuseShCoefficientCount,
        kDiffuseShKtx2Key,
        kDiffuseShSidecarByteLength,
        kShBand0Basis,
        parseDiffuseShSidecar;
export 'src/material/environment.dart'
    show EnvironmentMap, environmentAssetPathOf;
export 'src/material/equirect_image.dart'
    show EquirectImageFormat, decodeEquirectHdrImage, detectEquirectImageFormat;
export 'src/material/exr_decoder.dart' show ExrFormatException, decodeOpenExr;
export 'src/material/hdr_decoder.dart'
    show DecodedHdr, HdrFormatException, decodeRadianceHdr;
export 'src/material/material.dart' show Material;
export 'src/material/material_group.dart' show MaterialGroup;
export 'src/material/material_parameters.dart' show MaterialParameters;
export 'src/material/physically_based_material.dart'
    show AlphaMode, PhysicallyBasedMaterial, TextureTransform;
export 'src/material/preprocessed_material.dart' show PreprocessedMaterial;
export 'src/material/preprocessed_sky.dart' show PreprocessedSky;
export 'src/material/shader_material.dart'
    show ShaderInstanceAttribute, ShaderInstanceAttributeType, ShaderMaterial;
export 'src/material/shader_stage.dart' show MeshVariant, ShaderStage;
export 'src/material/shadow_catcher_material.dart'
    show ShadowCatcherMaterial, ShadowCatcherMode;
export 'src/material/sprite_material.dart' show SpriteBlendMode, SpriteMaterial;
export 'src/material/unlit_material.dart' show UnlitMaterial;
export 'src/fmat/material_registry.dart'
    show
        FmatMaterialFactory,
        FmatMaterialRegistry,
        loadFmatMaterial,
        loadFmatSky;
export 'src/importer/scene_registry.dart'
    show
        SceneRegistry,
        SceneReloadCallback,
        clearSceneTemplateCache,
        loadScene,
        loadSceneSubtree,
        releaseScene;

export 'src/ambient_occlusion.dart'
    show
        AmbientOcclusionMethod,
        AmbientOcclusionSettings,
        SpecularAmbientOcclusionMode;
export 'src/auto_exposure.dart' show AutoExposureSettings;
export 'src/depth_of_field.dart' show DepthOfField, DepthOfFieldQuality;
export 'src/fog.dart' show Fog, FogMode;
export 'src/global_illumination.dart'
    show
        GlobalIlluminationSettings,
        IrradianceInjectionResolution,
        IrradianceVolumeMode;
export 'src/render/irradiance_bake.dart'
    show IrradianceFieldBake, IrradianceFieldBakeStepper;
export 'src/render/temporal_anti_aliasing.dart'
    show TemporalAntiAliasingSettings;
export 'src/god_rays.dart' show GodRaysSettings;
export 'src/screen_distortion.dart'
    show DistortionPulse, ScreenDistortionSettings;
export 'src/screen_space_reflections.dart'
    show ScreenSpaceReflectionsSettings, SsrDebugView;
export 'src/asset_helpers.dart'
    show
        gpuTextureFromAsset,
        gpuTextureFromImage,
        imageFromAsset,
        imageFromBytes;
export 'src/camera.dart'
    show
        Camera,
        CameraProjection,
        OrthographicCamera,
        OrthographicProjection,
        PerspectiveCamera,
        PerspectiveProjection;
export 'src/camera_controllers/camera_controller.dart'
    show CameraController, CameraDirectorBinding;
export 'src/camera_controllers/camera_director.dart'
    show CameraBlend, CameraDirector;
export 'src/camera_controllers/camera_path.dart' show CameraPath;
export 'src/camera_controllers/virtual_camera.dart'
    show
        CameraAim,
        CameraBinding,
        CameraBody,
        CameraSolveContext,
        ComposerAim,
        FixedAim,
        FramingTransposerBody,
        HardLookAtAim,
        OrbitalBody,
        TransposerBody,
        VirtualCamera,
        dampScalar,
        dampVector,
        lookRotation;
export 'src/camera_controllers/camera_sequence.dart'
    show CameraSequence, CameraShot;
export 'src/camera_controllers/dolly_camera_controller.dart'
    show DollyCameraController;
export 'src/camera_controllers/first_person_camera_controller.dart'
    show FirstPersonCameraController, HeadBob;
export 'src/camera_controllers/fly_camera_controller.dart'
    show FlyCameraController;
export 'src/camera_controllers/follow_camera_controller.dart'
    show FollowCameraController;
export 'src/camera_controllers/orbit_camera_controller.dart'
    show OrbitCameraController;
export 'src/camera_controllers/rts_camera_controller.dart'
    show EdgeScroll, RtsCameraController;
export 'src/camera_pose.dart' show CameraPose;
export 'src/components/camera_component.dart' show CameraComponent, NodeCamera;
export 'src/components/component.dart' show Component;
export 'src/components/directional_light_component.dart'
    show DirectionalLightComponent;
export 'src/components/environment_volume_component.dart'
    show EnvironmentVolumeComponent, EnvironmentVolumeShape;
export 'src/components/irradiance_volume_component.dart'
    show IrradianceVolumeComponent;
export 'src/components/planar_reflector_component.dart'
    show PlanarReflectorComponent;
export 'src/components/reflection_probe_component.dart'
    show ReflectionProbeComponent;
export 'src/components/image_based_light_component.dart'
    show ImageBasedLightComponent;
export 'src/components/instanced_mesh_component.dart'
    show InstancedMeshComponent;
export 'src/components/lod_component.dart' show LodComponent;
export 'src/components/mesh_component.dart' show MeshComponent;
export 'src/components/materials_variants_component.dart'
    show MaterialsVariantsComponent;
export 'src/components/point_light_component.dart' show PointLightComponent;
export 'src/components/rect_area_light_component.dart'
    show RectAreaLightComponent;
export 'src/components/semantics_component.dart' show SemanticsComponent;
export 'src/components/splat_component.dart' show SplatComponent;
export 'src/components/spot_light_component.dart' show SpotLightComponent;
export 'src/render/lod.dart' show LodLevel;
export 'src/components/widget_component.dart' show WidgetComponent, WidgetInput;
export 'src/components/particle_emitter_component.dart'
    show ParticleEmitterComponent;
export 'src/components/mesh_particle_emitter_component.dart'
    show MeshParticleEmitterComponent, MeshParticleFacing;
export 'src/components/trail_component.dart' show TrailComponent;
export 'src/particles/particle_system.dart' show ParticleSystem;
export 'src/particles/vfx_presets.dart'
    show VfxCategory, VfxPreset, vfxPresetById, vfxPresets, vfxPresetsIn;
export 'src/particles/particle_storage.dart' show ParticleStorage;
export 'src/particles/particle_collision.dart'
    show
        CollisionModule,
        ParticleBox,
        ParticleCollider,
        ParticleCollisionResponse,
        ParticlePlane,
        ParticleSphere;
export 'src/particles/particle_module.dart'
    show
        AccelerationModule,
        ColorOverLifeModule,
        FlipbookModule,
        LinearDragModule,
        ParticleModule,
        RotationModule,
        SizeOverLifeModule,
        TurbulenceModule,
        WindModule;
export 'src/particles/emitter_shape.dart'
    show
        BoxEmitterShape,
        ConeEmitterShape,
        EmitterShape,
        PointEmitterShape,
        SphereEmitterShape;
export 'src/particles/distribution.dart'
    show
        ColorDistribution,
        ColorGradient,
        ColorStop,
        ConstantColor,
        ConstantFloat,
        CurveFloat,
        FloatDistribution,
        GradientColor,
        ParticleCurve,
        ParticleKeyframe,
        UniformColor,
        UniformCurveFloat,
        UniformFloat;
export 'src/particles/spawner.dart' show ParticleBurst, Spawner;
export 'src/geometry/splat_geometry.dart' show SplatCropMode;
export 'src/splats/gaussian_splats.dart' show GaussianSplats;
export 'src/splats/splat_codec.dart' show SplatFormat;
export 'src/splats/splat_data.dart' show SplatColorSpace, SplatData;
export 'src/instanced_mesh.dart' show InstancedMesh;
export 'src/light.dart'
    show
        DirectionalLight,
        DirectionalShadowFilter,
        Lighting,
        PointLight,
        RectAreaLight,
        ShadowCascade,
        ShadowCasterFaces,
        ShadowCastingMode,
        SpotLight;
export 'src/render/custom_render_pass.dart'
    show CustomRenderPass, RenderInput, RenderPassContext, RenderStage;
export 'src/render/frame_transients.dart' show TransientWriter;
export 'src/render/render_graph_capture.dart'
    show
        CapturedPass,
        CapturedResource,
        RenderGraphCaptureRequest,
        RenderGraphCaptureResult;
export 'src/render/object_filter.dart' show NodeFilter;
export 'src/render/render_layers.dart'
    show kRenderLayerAll, kRenderLayerDefault;
export 'src/render/selection_outline_pass.dart' show HighlightStyle;
export 'src/render_texture.dart'
    show RenderTexture, RenderTextureSampling, RenderTextureUpdate;
export 'src/render_view.dart' show RenderView;
export 'src/math_extensions.dart'
    show QuaternionRotate, QuaternionSlerp, Vector3Lerp;
export 'src/mesh.dart' show Mesh, MeshPrimitive;
export 'src/decal.dart' show DecalNode;
export 'src/node.dart' show Node;
export 'src/sprite.dart' show Sprite;
export 'src/texture_atlas.dart'
    show TextureAtlas, generateSolidColorAtlasPixels;
export 'src/texture/external_texture.dart'
    show ExternalTexture, ExternalTextureSampling, ExternalTextureUpdate;
export 'src/texture/texture2d.dart'
    show Texture2D, TextureSource, TextureSampling, GpuTextureSource;
export 'src/memory_report.dart'
    show MemoryCategory, MemoryReport, takeMemoryReport;
export 'src/texture/texture_registry.dart'
    show clearTextureCache, loadTexture, releaseTexture;
export 'src/texture/mipmap.dart' show TextureContent;
// Audio is an optional contract, exported from
// `package:flutter_scene/audio.dart`.
// Physics is an optional contract, exported from
// `package:flutter_scene/physics.dart`.
export 'src/post_process/post_effect.dart' show PostEffect, PostInsertion;
export 'src/post_process/color_lut.dart' show ColorLut;
export 'src/post_process/post_process.dart'
    show
        BloomSettings,
        ChromaticAberrationSettings,
        ColorGradingSettings,
        FilmGrainSettings,
        LensFlareSettings,
        PostProcessSettings,
        VignetteSettings;
export 'src/importer/gltf.dart'
    show
        GltfImportWarning,
        GltfWarningCallback,
        UnsupportedRequiredExtensionException;
export 'src/render/env_prefilter.dart'
    show
        kPrefilterBandCount,
        prefilterEquirectRadiance,
        prefilterEquirectRadianceToCube;
export 'src/texture/ktx2/ktx2.dart' show Ktx2FormatException;
export 'src/runtime_importer/gltf_resources.dart' show GltfResourceResolver;
export 'src/scene_path.dart'
    show BezierPath, CatmullRomPath, PolylinePath, ScenePath, ScenePathFrame;
export 'src/raycast.dart' show SceneRaycastHit, raycastNode, raycastNodeAll;
export 'src/resource_group.dart' show ResourceGroup;
export 'src/scene_pointer.dart' show ScenePointer;
export 'src/scene.dart' show AntiAliasingMode, Scene, SceneGraph;
export 'src/widget_texture.dart'
    show WidgetTexture, WidgetTextureController, WidgetUpdatePolicy;
export 'src/shaders.dart' show baseShaderLibrary, loadBaseShaderLibrary;
export 'src/skin.dart' show Skin;
export 'src/sky_environment.dart' show SkyEnvironment, SkyEnvironmentRefresh;
export 'src/sky_sources.dart'
    show GradientSkySource, PhysicalSkySource, WeatherSkySource;
export 'src/skybox.dart'
    show EnvironmentSkySource, ShaderSkySource, SkySource, Skybox, SunSky;
export 'src/sun_light.dart' show SunLight;
export 'src/surface.dart' show Surface;
export 'src/widgets/declarative.dart'
    show
        AssetModelSource,
        MemoryModelSource,
        SceneAnimationSpec,
        SceneMesh,
        SceneModel,
        SceneModelSource,
        SceneNode,
        SceneNodeController,
        SceneNodeHost,
        SceneSubtree;
export 'src/widgets/camera_controls.dart' show CameraControls;
export 'src/widgets/render_texture_view.dart' show RenderTextureView;
export 'src/widgets/scene_view.dart'
    show
        SceneCameraBuilder,
        SceneLoadingBuilder,
        SceneScope,
        SceneTickCallback,
        SceneView,
        SceneViewsBuilder;
export 'src/tone_mapping.dart' show ToneMappingMode;
