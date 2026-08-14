/// Read-side helpers for codecs that serialize node and resource references
/// recovered from live objects. Generated codecs bind these; hand-written
/// codecs can too.
library;

import 'package:scene/scene.dart';

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/node.dart';

/// The serialized reference for [node], or null when it was not realized
/// from a document node (a hand-built node has no document id).
/// {@category Assets and loading}
NodeRefValue? nodeRefOf(Node? node) {
  if (node == null) return null;
  final id = nodeFsceneId(node);
  return id == null ? null : NodeRefValue(id);
}

/// The serialized reference for [live] (a geometry, material, texture, or
/// environment the resource realizer produced), copying the resource into
/// [context]'s document when it originated in another one. Null for a
/// hand-built object, which has no source resource to reference.
/// {@category Assets and loading}
ResourceRefValue? resourceRefOf(Object? live, SerializeContext context) {
  if (live == null) return null;
  final origin = resourceOrigin(live);
  if (origin == null) return null;
  return ResourceRefValue(
    copyResourceInto(context.document, origin.document, origin.resourceId),
  );
}
