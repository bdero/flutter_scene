/// Marks a realized live [Node] as a lazy prefab placeholder: its prefab
/// content has not been loaded yet (level streaming). `loadSubtree` expands it
/// on demand and `unloadSubtree` releases it again.
///
/// The placeholder carries the [PrefabInstanceSpec] it was realized from (via
/// an [Expando]) so the streaming layer knows what to instantiate when the
/// subtree is loaded.
library;

import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/node.dart';

final Expando<PrefabInstanceSpec> _lazyInstances = Expando<PrefabInstanceSpec>(
  'fscene.lazyInstance',
);

/// Marks [node] as the placeholder for the lazy prefab instance [spec], and
/// returns it.
Node tagLazyInstance(Node node, PrefabInstanceSpec spec) {
  _lazyInstances[node] = spec;
  return node;
}

/// The lazy prefab instance [node] is a placeholder for, or null if it is not a
/// lazy placeholder.
PrefabInstanceSpec? lazyInstanceOf(Node node) => _lazyInstances[node];
