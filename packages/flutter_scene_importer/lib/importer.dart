// ignore: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

/// A deserialized Flutter Scene `.model` payload.
///
/// `flutter_scene` consumes these via `Node.fromAsset` and
/// `Node.fromFlatbuffer`, but applications can also load one directly to
/// inspect or transform the underlying flatbuffer. The
/// `flutter_scene_importer` package owns the schema; the
/// [`flatbuffer.dart`](flatbuffer.dart) library re-exports the generated
/// flatbuffer types and provides a few helpful extensions on them.
class ImportedScene {
  /// Loads and deserializes a `.model` asset from the asset bundle.
  static Future<ImportedScene> fromAsset(String asset) {
    return rootBundle.loadStructuredBinaryData<ImportedScene>(asset, (data) {
      return fromFlatbuffer(data);
    });
  }

  /// Deserializes a `.model` payload from already-loaded bytes.
  static ImportedScene fromFlatbuffer(ByteData data) {
    final fb.Scene scene = fb.Scene(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );

    return ImportedScene._(scene);
  }

  ImportedScene._(this._scene);

  final fb.Scene _scene;

  /// The deserialized flatbuffer root.
  ///
  /// Returns the generated `fb.Scene` accessor; cast at the call site
  /// when type information is needed.
  get flatbuffer => _scene;
}
