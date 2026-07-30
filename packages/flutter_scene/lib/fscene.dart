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
export 'src/fscene/realize/builtin_codecs.dart'
    show registerBuiltinComponentCodecs;
export 'package:scene/scene.dart' show diffScene, SceneDiff, NodeChange;
export 'src/fscene/reload/reload.dart' show reloadScene;
export 'src/fscene/realize/component_codec.dart'
    show
        ComponentCodec,
        FsceneComponentRegistry,
        RealizeContext,
        SerializeContext;
export 'src/fscene/realize/component_schema.dart'
    show ComponentPropertyDef, ComponentPropertyKind;
export 'src/fscene/realize/loader.dart'
    show
        loadFsceneAsset,
        loadFsceneString,
        loadFscenebAsset,
        loadFscenebBytes,
        loadFscenebBytesAsync;
export 'src/fscene/realize/property_read.dart'
    show readBool, readColor, readDouble, readInt, readString, readVec3;
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
        TextureResource,
        TransformSpec,
        TrsTransform,
        UpAxis;
export 'src/fscene/stream/stream.dart'
    show loadSubtree, unloadSubtree, isLazySubtree, isSubtreeLoaded;
