/// The `.fscene` serialized scene format: an in-memory document model, JSON
/// read/write, and realization to and from a live `Node` graph.
///
/// Load a scene with [loadFsceneAsset] (or build a [SceneDocument] in code,
/// write it with [writeFscene], and read it back with [readFscene]). Realize
/// a document into a node graph with [realizeScene], or serialize a live
/// graph back with [serializeScene]. Register app-defined component types
/// with a [FsceneComponentRegistry].
library;

export 'package:scene/scene.dart'
    show writeFsceneb, readFsceneb, kFscenebVersion, FscenebFormatException;
export 'package:scene/scene.dart'
    show
        applyPrefabOverride,
        composeScene,
        composeSceneAsync,
        PrefabResolver,
        AsyncPrefabLoader;
export 'package:scene/scene.dart'
    show DocumentId, LocalId, IdAllocator, encodeBase32, decodeBase32;
export 'package:scene/scene.dart'
    show
        writeFscene,
        readFscene,
        currentFsceneVersion,
        supportedFeatures,
        FsceneFormatException,
        FsceneVersionException,
        FsceneUnsupportedFeatureException;
export 'package:scene/scene.dart'
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
export 'src/fscene/realize/audio_codecs.dart'
    show
        AudioEngineBackendFactory,
        audioEngineBackendFactory,
        registerAudioEngineBackend;
export 'src/fscene/realize/builtin_codecs.dart'
    show registerBuiltinComponentCodecs;
export 'src/fscene/realize/physics_codecs.dart'
    show PhysicsBackendFactory, physicsBackendFactory, registerPhysicsBackend;
export 'src/fscene/realize/ui_codecs.dart'
    show WidgetSlotBuilder, registerWidgetSlot, widgetSlotBuilder;
export 'package:scene/scene.dart' show diffScene, SceneDiff, NodeChange;
export 'src/fscene/reload/reload.dart' show reloadScene;
export 'src/fscene/realize/component_codec.dart'
    show
        ComponentCodec,
        FsceneComponentRegistry,
        RealizeContext,
        SerializeContext,
        universalComponentProperties;
export 'src/fscene/realize/component_schema.dart'
    show
        AngleRadians,
        AssetExtensions,
        ComponentPropertyDef,
        ComponentPropertyKind,
        ComponentSchema,
        GizmoArrow,
        GizmoColor,
        GizmoCondition,
        GizmoFrustum,
        GizmoIcon,
        GizmoLines,
        GizmoPrimitive,
        GizmoScalar,
        GizmoSpec,
        GizmoVisibility,
        GizmoWireBox,
        GizmoWireCapsule,
        GizmoWireCircle,
        GizmoWireCone,
        GizmoWireCylinder,
        GizmoWireRect,
        GizmoWireSphere,
        IntRange,
        LayerMask32,
        MinCount,
        Multiline,
        Normalized,
        PowerOfTwo,
        PropertyConstraint,
        Range,
        RgbColor,
        SoftRange,
        SortedDescending,
        Step,
        TextPattern,
        UnknownConstraint,
        decodeComponentSchemas,
        encodeComponentSchemas,
        propertyValuesEqual;
export 'src/fscene/realize/declarative_codec.dart'
    show ComponentField, DeclarativeComponentCodec, PropertyReader;
export 'src/fscene/realize/placeholder_codec.dart'
    show ForeignComponent, PlaceholderComponentCodec;
export 'src/fscene/realize/loader.dart'
    show
        loadFsceneAsset,
        loadFsceneString,
        loadFscenebAsset,
        loadFscenebBytes,
        loadFscenebBytesAsync;
export 'src/fscene/realize/property_read.dart'
    show readBool, readColor, readDouble, readInt, readString, readVec3;
export 'src/fscene/realize/ref_read.dart' show nodeRefOf, resourceRefOf;
export 'src/fscene/realize/realize.dart'
    show
        defaultComponentRegistry,
        realizeScene,
        realizeSceneAsync,
        serializeScene;
export 'src/fscene/realize/resource_realizer.dart' show ResourceRealizer;
export 'src/fscene/realize/stage.dart' show realizeStage, serializeStage;
export 'src/fscene/realize/views.dart' show realizeViews, serializeViews;
export 'package:scene/scene.dart' show SceneDocument;
export 'package:scene/scene.dart'
    show
        Attachment,
        AnimationChannelSpec,
        AnimationProperty,
        AnimationSpec,
        AssetEnvironment,
        BoundsSpec,
        ComponentSpec,
        ConstantEnvironment,
        CuboidGeometrySpec,
        EmptyEnvironment,
        EnvironmentResource,
        EnvironmentSkySpec,
        EnvironmentSpec,
        FmatSkySpec,
        GeometryResource,
        GradientSkySpec,
        IcosphereGeometrySpec,
        LoadPolicy,
        MaterialResource,
        MatrixTransform,
        NodeSpec,
        PayloadEncoding,
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
        SkyEnvironmentSpec,
        SkySourceSpec,
        SkyboxSpec,
        SphereGeometrySpec,
        StageMetadata,
        StudioEnvironment,
        SunLightSpec,
        TextureResource,
        TorusGeometrySpec,
        TransformSpec,
        TrsTransform;
export 'src/fscene/stream/stream.dart'
    show loadSubtree, unloadSubtree, isLazySubtree, isSubtreeLoaded;
