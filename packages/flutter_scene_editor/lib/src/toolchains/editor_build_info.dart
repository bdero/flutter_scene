/// The identity the editor was built with, baked at build time by the app's
/// build hook into an `editor_build_info.json` data asset. Installation and
/// project version warnings compare against these fields; a missing asset
/// (data assets disabled) yields [EditorBuildInfo.unknown] and the warnings
/// simply do not fire.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

class EditorBuildInfo {
  const EditorBuildInfo({
    this.frameworkVersion,
    this.frameworkRevision,
    this.engineRevision,
    this.engineContentHash,
    this.dartSdkVersion,
    this.repositoryUrl,
    this.flutterSceneVersion,
  });

  static const unknown = EditorBuildInfo();

  final String? frameworkVersion;
  final String? frameworkRevision;
  final String? engineRevision;
  final String? engineContentHash;
  final String? dartSdkVersion;
  final String? repositoryUrl;
  final String? flutterSceneVersion;

  bool get isKnown => frameworkRevision != null;

  /// Loads the baked build info from [assetKey] (the hosting app's data
  /// asset, `packages/<app>/editor_build_info.json`).
  static Future<EditorBuildInfo> load(String assetKey) async {
    try {
      final decoded = jsonDecode(await rootBundle.loadString(assetKey));
      if (decoded is! Map) return unknown;
      String? read(String key) =>
          decoded[key] is String ? decoded[key] as String : null;
      return EditorBuildInfo(
        frameworkVersion: read('frameworkVersion'),
        frameworkRevision: read('frameworkRevision'),
        engineRevision: read('engineRevision'),
        engineContentHash: read('engineContentHash'),
        dartSdkVersion: read('dartSdkVersion'),
        repositoryUrl: read('repositoryUrl'),
        flutterSceneVersion: read('flutterSceneVersion'),
      );
    } catch (_) {
      return unknown;
    }
  }
}
