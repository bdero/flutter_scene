// The off-main-isolate `.fsceneb` parse. A container's payload chunks are
// gzipped, so reading one inflates and copies megabytes of vertex and image
// data; doing that on the UI isolate blocks every frame for as long as it
// takes (a 1.6 MB container carrying two 2048x2048 rgba8 textures costs
// ~250 ms on a mid-range Android phone, with the GC it triggers on top).

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:scene/scene.dart';

/// Parses a `.fsceneb` container from [bytes] on a background isolate.
///
/// The asynchronous counterpart of [readFsceneb], for callers that can await:
/// the inflate and the manifest parse run off the calling isolate, so a load
/// no longer stalls the frames of whatever is on screen (a loader, a route
/// transition) while it happens.
///
/// Only [bytes] crosses into the worker; the parsed document comes back by
/// *transfer*, not by copy (that is what [compute] does under the hood), so
/// the payload buffers — by far the bulk of a container — are never duplicated.
/// The container as stored is the small side of that exchange, which is why
/// this is cheaper than parsing in place even though it involves a hop.
///
/// On the web there are no isolates and [compute] runs the callback inline, so
/// this behaves exactly like [readFsceneb] there.
Future<SceneDocument> readFscenebAsync(Uint8List bytes) =>
    compute(readFsceneb, bytes, debugLabel: 'readFsceneb');
