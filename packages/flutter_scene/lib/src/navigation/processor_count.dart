/// How many cores this device has, without dragging `dart:io` into the
/// dependency graph.
///
/// `package:flutter_scene/scene.dart` has to stay compilable for web and
/// wasm, and reaches the nav surface component through the document codecs,
/// which reaches the tiled baker. Web has no isolates anyway, so the stub's
/// answer of one is not a fallback there -- it is the truth.
library;

export 'processor_count_stub.dart'
    if (dart.library.io) 'processor_count_io.dart'
    show platformProcessorCount;
