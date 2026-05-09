// ignore: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

class ImportedScene {
  static Future<ImportedScene> fromAsset(String asset) {
    return rootBundle.loadStructuredBinaryData<ImportedScene>(asset, (data) {
      return fromFlatbuffer(data);
    });
  }

  static ImportedScene fromFlatbuffer(ByteData data) {
    final fb.Scene scene = fb.Scene(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));

    return ImportedScene._(scene);
  }

  ImportedScene._(this._scene);

  final fb.Scene _scene;

  get flatbuffer => _scene;
}
