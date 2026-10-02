import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:scene/scene.dart';

/// Parses a `.fsceneb` container from [bytes] on a background isolate.
///
/// The asynchronous counterpart of [readFsceneb]. Payload chunks are gzipped,
/// so a texture-heavy container can take hundreds of milliseconds to inflate;
/// this keeps that off the calling isolate's frames. Only [bytes] is copied in,
/// and the parsed document is transferred back rather than copied.
///
/// On the web [compute] runs inline, so this behaves like [readFsceneb].
/// {@category Assets and loading}
Future<SceneDocument> readFscenebAsync(Uint8List bytes) =>
    compute(readFsceneb, bytes, debugLabel: 'readFsceneb');
