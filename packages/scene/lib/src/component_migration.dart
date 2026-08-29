/// Component types that have been renamed, and the migration that keeps old
/// documents readable.
///
/// A component whose type nothing recognizes is dropped on load, silently and
/// completely: the node survives and the behaviour on it does not. So a rename
/// of a component type is a change that eats scenes unless the old spelling
/// keeps resolving.
///
/// Migrating where a document is *read* rather than where components are
/// realized means every reader gets it once and nothing downstream has to know
/// a rename ever happened. Saving writes the current name, so a document
/// migrates the first time it is opened and saved.
library;

/// The component type a visual script is stored as.
///
/// Named rather than spelled out at the two places that need it, because the
/// codec and the migration have to agree and a typo in either is a component
/// that loads as nothing.
const String visualScriptComponentType = 'visualScript';

/// Every renamed component type, old spelling to current.
///
/// Entries are never removed. A scene saved years ago is still a scene, and
/// the cost of an entry here is one map lookup per component on load.
const Map<String, String> renamedComponentTypes = {
  // The Flow canvas became the Visual Scripter.
  'flow': visualScriptComponentType,
};

/// The current name for component [type], which is [type] itself unless it
/// was renamed.
String migrateComponentType(String type) => renamedComponentTypes[type] ?? type;
