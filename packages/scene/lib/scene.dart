/// The engine-agnostic scene document core.
///
/// The `.fscene` document model with stable ids, JSON and binary
/// serialization, prefab composition, and structural diffing. Pure Dart,
/// renderers (flutter_scene), editors, and servers all build on it; nothing
/// here touches a GPU or the Flutter SDK.
library;

export 'src/id.dart'
    show decodeBase32, DocumentId, encodeBase32, IdAllocator, LocalId;
export 'src/specs.dart'
    show
        AnimationChannelSpec,
        AnimationProperty,
        AnimationSpec,
        AssetEnvironment,
        Attachment,
        BoundsSpec,
        ComponentSpec,
        CuboidGeometrySpec,
        EmptyEnvironment,
        EnvironmentResource,
        EnvironmentSkySpec,
        EnvironmentSpec,
        FmatSkySpec,
        GeometryResource,
        GradientSkySpec,
        Handedness,
        LoadPolicy,
        MaterialResource,
        MatrixTransform,
        NodeSpec,
        PayloadEncoding,
        PayloadEnvironment,
        PayloadSpec,
        PhysicalSkySpec,
        PlaneGeometrySpec,
        PrefabInstanceSpec,
        ProceduralGeometry,
        PropertyOverride,
        RenderTextureResource,
        RenderViewSpec,
        ResourceSpec,
        SkinSpec,
        SkyboxSpec,
        SkyEnvironmentSpec,
        SkySourceSpec,
        SphereGeometrySpec,
        StageMetadata,
        StudioEnvironment,
        TextureResource,
        TransformSpec,
        TrsTransform,
        UpAxis;
export 'src/scene_document.dart' show SceneDocument;
export 'src/property_value.dart'
    show
        AssetRef,
        BoolValue,
        ColorValue,
        DoubleValue,
        IntValue,
        ListValue,
        MapValue,
        Matrix4Value,
        NodeRefValue,
        PropertyValue,
        QuaternionValue,
        ResourceRefValue,
        StringValue,
        Vec2Value,
        Vec3Value,
        Vec4Value;
export 'src/diff.dart' show diffScene, NodeChange, SceneDiff;
export 'src/log.dart' show sceneLog;
export 'src/binary/fsceneb.dart'
    show FscenebFormatException, kFscenebVersion, readFsceneb, writeFsceneb;
export 'src/json/fscene_json.dart'
    show
        currentFsceneVersion,
        decodeDocument,
        encodeDocument,
        encodeResource,
        encodeSkySource,
        encodeStage,
        FsceneFormatException,
        FsceneMigration,
        FsceneUnsupportedFeatureException,
        FsceneVersionException,
        migrateFscene,
        readFscene,
        supportedFeatures,
        writeFscene;
export 'src/json/canonical.dart' show canonicalJson, FsceneEncodeException;
export 'src/json/jsonc.dart' show stripJsonc;
export 'src/json/property_json.dart'
    show decodePropertyValue, encodePropertyValue, IdTokenResolver;
export 'src/compose/compose.dart'
    show
        applyPrefabOverride,
        AsyncPrefabLoader,
        composeScene,
        composeSceneAsync,
        PrefabMemberOrigin,
        PrefabResolver;

export 'src/physics/basic_simulation.dart' show BasicSimulation;
export 'src/physics/joint_desc.dart'
    show
        FixedJointDesc,
        GenericJointDesc,
        JointAxis,
        JointAxisConfig,
        JointAxisMotion,
        JointDesc,
        JointMotor,
        JointMotorModel,
        PrismaticJointDesc,
        RevoluteJointDesc,
        SphericalJointDesc;
export 'src/physics/material.dart' show CombineRule, PhysicsMaterial;
export 'src/physics/pose_target.dart' show PoseTarget, SimplePoseTarget;
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
export 'src/physics/shape_queries.dart'
    show
        aabbRaycast,
        RayShapeHit,
        rayHitsShape,
        shapesOverlap,
        shapeWorldAabb,
        sphereOverlapsAabb,
        sphereOverlapsSphere;
export 'src/physics/sim_types.dart'
    show
        BodyType,
        CharacterMovement,
        ContactPoint,
        SimCollisionBegan,
        SimCollisionEnded,
        SimCollisionEvent,
        SimOverlapHit,
        SimRaycastHit,
        SimShapeCastHit,
        SimTriggerEntered,
        SimTriggerExited;
export 'src/physics/simulation.dart' show PhysicsSimulation;
