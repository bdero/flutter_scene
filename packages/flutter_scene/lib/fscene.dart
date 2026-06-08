/// The `.fscene` serialized scene format: an in-memory document model, JSON
/// read/write, and realization to and from a live `Node` graph.
///
/// Load a scene with [loadFsceneAsset] (or build a [SceneDocument] in code,
/// write it with [writeFscene], and read it back with [readFscene]). Realize
/// a document into a node graph with [realizeScene], or serialize a live
/// graph back with [serializeScene]. Register app-defined component types
/// with a [FsceneComponentRegistry].
library;

export 'src/fscene/binary/fsceneb.dart'
    show writeFsceneb, readFsceneb, kFscenebVersion, FscenebFormatException;
export 'src/fscene/compose/compose.dart'
    show composeScene, composeSceneAsync, PrefabResolver, AsyncPrefabLoader;
export 'src/fscene/id.dart'
    show DocumentId, LocalId, IdAllocator, encodeBase32, decodeBase32;
export 'src/fscene/json/fscene_json.dart'
    show
        writeFscene,
        readFscene,
        currentFsceneVersion,
        supportedFeatures,
        FsceneFormatException,
        FsceneVersionException,
        FsceneUnsupportedFeatureException;
export 'src/fscene/property_value.dart';
export 'src/fscene/realize/builtin_codecs.dart';
export 'src/fscene/realize/component_codec.dart';
export 'src/fscene/realize/loader.dart';
export 'src/fscene/realize/property_read.dart';
export 'src/fscene/realize/realize.dart';
export 'src/fscene/realize/resource_realizer.dart';
export 'src/fscene/scene_document.dart';
export 'src/fscene/specs.dart';
