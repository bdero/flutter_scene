/// Headless command and change-record core for the flutter_scene editor.
///
/// This library is GPU-free and UI-free. It turns the shipped, in-memory
/// [SceneDocument] into an editable model driven through a single command
/// layer, with undo and redo built on uniform change records. The editor UI,
/// scripting, and AI agents all drive the same command surface.
library;

// Public surface is added here as the core takes shape. Keep this an explicit
// show-list barrel, matching the flutter_scene convention.
