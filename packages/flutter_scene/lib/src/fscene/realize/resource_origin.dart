/// Tracks where a live, GPU-backed resource was realized from, so the scene
/// serializer can recover the originating resource (and its payload chunks)
/// without reading bytes back off the GPU.
///
/// When the [ResourceRealizer] builds a [Geometry], [Material], or texture, it
/// stamps the live object with the source document and resource id. The mesh
/// codec reads that stamp back at serialize time and copies the resource into
/// the destination document. The stamp lives on the object itself (via an
/// [Expando]), so it survives for as long as the realized object does.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';

/// The document and resource id a live object was realized from.
class ResourceOrigin {
  /// Records that a live object came from [resourceId] in [document].
  ResourceOrigin(this.document, this.resourceId);

  /// The document the resource was realized from.
  final SceneDocument document;

  /// The realized resource's id within [document].
  final LocalId resourceId;
}

final Expando<ResourceOrigin> _origins = Expando<ResourceOrigin>(
  'fscene.resourceOrigin',
);

/// Stamps [live] (a realized geometry, material, or texture) with the
/// [document] and [resourceId] it was built from, and returns it.
T tagResourceOrigin<T extends Object>(
  T live,
  SceneDocument document,
  LocalId resourceId,
) {
  _origins[live] = ResourceOrigin(document, resourceId);
  return live;
}

/// The origin stamped on [live] by [tagResourceOrigin], or null if it was not
/// produced by the realizer.
ResourceOrigin? resourceOrigin(Object live) => _origins[live];
