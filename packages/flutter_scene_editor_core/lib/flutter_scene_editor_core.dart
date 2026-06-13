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
        CommandRegistry,
        UiFieldDescriptor,
        mcpToolSchema,
        uiDescriptors;

// Parameter coercion helpers (for command authors).
export 'src/params.dart'
    show
        requireString,
        optionalString,
        requireBool,
        requireInt,
        requireDouble,
        requireVec3,
        optionalVec3,
        requireQuaternion,
        optionalQuaternion,
        requireNodeId,
        optionalNodeId,
        requireResourceId,
        optionalResourceId,
        requireAssetRef,
        optionalPropertyMap,
        optionalOverrides,
        coercePropertyValue;

// The built-in command set.
export 'src/builtin_commands.dart' show builtinCommands, registerBuiltinCommands;

// Selection, queries, and the session that ties it all together.
export 'src/selection.dart' show Selection;
export 'src/query.dart' show SceneQuery;
export 'src/session.dart' show EditorSession;
