/// Headless command and change-record core for the flutter_scene editor.
///
/// This library is GPU-free and UI-free. It turns the shipped, in-memory
/// `SceneDocument` into an editable model driven through a single command
/// layer, with undo and redo built on uniform change records. The editor UI,
/// scripting, and AI agents all drive the same command surface.
///
/// Start with [EditorSession], which wires a document, its [EditHistory], the
/// [CommandRegistry] (pre-loaded with [builtinCommands]), the [Selection], and
/// the read-only [SceneQuery] together. Run edits with [EditorSession.run].
///
/// This is an explicit show-list barrel, matching the flutter_scene
/// convention. The document types these APIs operate on (`SceneDocument`,
/// `NodeSpec`, `LocalId`, `PropertyValue`, ...) live in `flutter_scene`;
/// in-repo consumers import them from there.
library;

// Change-record substrate.
export 'src/change.dart'
    show
        ChangeValue,
        StringChange,
        BoolChange,
        IntChange,
        TransformChange,
        LocalIdChange,
        PrefabInstanceChange,
        NodeChange,
        ResourceChange,
        SkinChange,
        AnimationChange,
        PayloadChange,
        StageMetadataChange,
        ComponentListChange,
        IdListChange,
        ChangeSlot,
        ChangeRecord,
        Transaction,
        DocumentMutator;

// Undo/redo.
export 'src/history.dart' show EditHistory;

// Command framework.
export 'src/command.dart'
    show
        ParamType,
        ParamSpec,
        CommandContext,
        CommandException,
        CommandEntry,
        CommandKind,
        CommandRegistry,
        UiFieldDescriptor,
        mcpToolSchema,
        paramJsonSchema,
        uiDescriptors;

// Many commands as one undo step.
export 'src/batch.dart' show CommandCall, BatchException, BatchComposer;

// The read half of the protocol.
export 'src/queries.dart'
    show
        QueryBlob,
        QueryResult,
        QueryContext,
        QueryException,
        QueryEntry,
        QueryRegistry,
        querySchema;
export 'src/builtin_queries.dart' show builtinQueries, registerBuiltinQueries;

// Events and per-client subscriptions.
export 'src/events.dart'
    show EditorEvent, EditorEventType, EventBus, EventSubscription;

// The protocol's own version and capabilities.
export 'src/protocol.dart' show EditorProtocol;

// Parameter coercion helpers (for command authors).
export 'src/params.dart'
    show
        requireString,
        optionalString,
        requireBool,
        optionalBool,
        requireInt,
        optionalInt,
        requireDouble,
        optionalDouble,
        requireVec3,
        optionalVec3,
        requireQuaternion,
        optionalQuaternion,
        requireNodeId,
        optionalNodeId,
        requireNodeIdList,
        requireResourceId,
        optionalResourceId,
        requireAssetRef,
        requireBytes,
        optionalPropertyMap,
        optionalOverrides,
        coercePropertyValue;

// The built-in command set.
export 'src/app_commands.dart' show applicationCommands;

export 'src/view_commands.dart'
    show
        clearSelection,
        frameNodes,
        selectNodes,
        setViewportCamera,
        viewCommands;

export 'src/builtin_commands.dart'
    show
        builtinCommands,
        environmentResourceWithProperties,
        environmentResourceWithSunProperties,
        registerBuiltinCommands;

// Subtree cloning (duplicate, copy, paste).
export 'src/clone.dart' show NodeSubtree, captureSubtree, instantiateSubtree;

// Cross-document graft (import one document's content into another).
export 'src/graft.dart' show graftDocumentRecords, wrapRootsUnderGroup;

// Selection, queries, and the session that ties it all together.
export 'src/selection.dart' show Selection;
export 'src/editor_host.dart' show EditorHost;
export 'src/view_host.dart' show ViewHost;
export 'src/query.dart' show SceneQuery;
export 'src/session.dart' show EditorSession;
