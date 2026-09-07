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
        AnimationInterpolation,
        AnimationProperty,
        AnimationSpec,
        AssetEnvironment,
        Attachment,
        BoundsSpec,
        ComponentSpec,
        ConstantEnvironment,
        CuboidGeometrySpec,
        TerrainGeometrySpec,
        WedgeGeometrySpec,
        DiscGeometrySpec,
        CylinderGeometrySpec,
        CapsuleGeometrySpec,
        EmptyEnvironment,
        EnvironmentEffectsSpec,
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
        MorphTargetsSpec,
        NodeSpec,
        EditorCameraSpec,
        EditorStateSpec,
        PayloadEncoding,
        PayloadEnvironment,
        PayloadSpec,
        PhysicalSkySpec,
        WeatherSkySpec,
        PlaneGeometrySpec,
        MemberComponent,
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
        SunLightSpec,
        TextureResource,
        TorusGeometrySpec,
        TransformSpec,
        TrsTransform;
export 'src/scene_document.dart' show SceneDocument, currentFsceneVersion;
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
export 'src/ui/rect_layout.dart' show RectTransformValues, UiRect, solveRect;
export 'src/ui/canvas_document_layout.dart'
    show
        SolvedRect,
        canvasComponentType,
        canvasRectOf,
        isCanvasNode,
        rectTransformComponentType,
        solveCanvasLayout;
export 'src/component_migration.dart'
    show migrateComponentType, renamedComponentTypes, visualScriptComponentType;
export 'src/mesh_grid_split.dart'
    show
        MeshGridCell,
        applyMeshSplitHints,
        countResourceReferences,
        documentWorldMatrix,
        isPayloadReferenced,
        splitTriangleMeshByGrid,
        splittableVertexLayouts;
export 'src/binary/fsceneb.dart'
    show FscenebFormatException, kFscenebVersion, readFsceneb, writeFsceneb;
export 'src/json/fscene_json.dart'
    show
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
        PrefabOverrideAspect,
        prefabOverrideAspect,
        PrefabResolver;

// Physics is an optional contract, exported from `package:scene/physics.dart`.
