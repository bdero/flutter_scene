/// Associates a realized live [Node] with the document-local id it was built
/// from, so scene-structure hot reload can find the live node for a given
/// document node by id (the stable key a structural diff patches against).
///
/// The id lives on the object via an [Expando], so it survives for as long as
/// the node does and adds nothing to [Node]'s own surface.
library;

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/node.dart';

final Expando<LocalId> _nodeIds = Expando<LocalId>('fscene.nodeId');

/// Stamps [node] with the document [id] it was realized from, and returns it.
Node tagNodeId(Node node, LocalId id) {
  _nodeIds[node] = id;
  return node;
}

/// The document id [node] was realized from, or null if it was not realized by
/// the fscene realizer.
LocalId? nodeFsceneId(Node node) => _nodeIds[node];
