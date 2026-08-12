/// Web/wasm stub; source-direct scene loading needs the local filesystem.
/// Mirrors the io surface so the analyzer (which resolves this default) and
/// web compiles type-check, but never activates.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:scene/scene.dart';

/// Never available on this platform.
SceneSourceLoader? activeSceneSourceLoader() => null;

/// Always false on this platform.
bool get sceneSourceLoadingActive => false;

/// No-op on this platform.
@visibleForTesting
void debugSetSceneSourceRoot(String? root) {}

/// Unavailable on this platform; [activeSceneSourceLoader] always returns
/// null, so none of these members ever run.
final class SceneSourceLoader {
  SceneSourceLoader._();

  String get root => throw UnsupportedError('source loading needs dart:io');
  AssetBundle get bundle =>
      throw UnsupportedError('source loading needs dart:io');
  String? resolveScene(String sourcePath) =>
      throw UnsupportedError('source loading needs dart:io');
  String? resolveRef(String hostKey, String refKey) =>
      throw UnsupportedError('source loading needs dart:io');
  bool isSourceKey(String key) =>
      throw UnsupportedError('source loading needs dart:io');
  bool deactivateOnAccessError(Object error, String key) =>
      throw UnsupportedError('source loading needs dart:io');
  Future<SceneDocument> readDocument(String key, Set<String> dependencies) =>
      throw UnsupportedError('source loading needs dart:io');
}
