/// Pure-data glTF / GLB parsing primitives.
///
/// Splits the parsing layer (no engine type dependencies) from the
/// engine-type builders that live in `package:flutter_scene`. Used by
/// flutter_scene's runtime importer at runtime, and by this package's
/// build hook to convert .glb → .model offline.
library;

export 'src/gltf/accessor.dart';
export 'src/gltf/glb.dart';
export 'src/gltf/parser.dart';
export 'src/gltf/types.dart';
