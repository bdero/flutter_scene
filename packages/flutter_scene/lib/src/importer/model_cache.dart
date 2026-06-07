import 'package:flutter_scene/src/node.dart';

/// Caches imported model templates by asset key so a model is parsed and
/// uploaded to the GPU only once per session.
///
/// The first [load] of a key imports a template [Node] via the supplied
/// callback; that template is cached and never handed out directly. Every
/// [load] (including the first) returns a fresh [Node.clone] of the template.
/// Clones share the underlying mesh, geometry, and GPU resources, so repeated
/// loads of the same model are cheap (no re-parse, no re-upload), while each
/// caller still gets its own attachable node subtree.
///
/// Concurrent loads of the same key share a single import. A failed import is
/// not cached, so the next [load] retries.
class ModelImportCache {
  final Map<String, Future<Node>> _templates = <String, Future<Node>>{};

  /// Returns a fresh clone of the template for [key], importing it via [import]
  /// on the first request (and on the first request after an [evict]).
  Future<Node> load(String key, Future<Node> Function() import) async {
    final pending = _templates[key] ??= import();
    final Node template;
    try {
      template = await pending;
    } catch (_) {
      // Do not cache a failed import; allow the next call to retry.
      if (identical(_templates[key], pending)) {
        _templates.remove(key);
      }
      rethrow;
    }
    return template.clone();
  }

  /// Evicts [key] (or the entire cache when [key] is null) so the next [load]
  /// re-imports it. Used by tests and by model hot reload.
  void evict([String? key]) {
    if (key == null) {
      _templates.clear();
    } else {
      _templates.remove(key);
    }
  }

  /// Whether a template for [key] is currently cached or being imported.
  bool contains(String key) => _templates.containsKey(key);
}
