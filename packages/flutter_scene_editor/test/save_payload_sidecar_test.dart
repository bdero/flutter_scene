// Regression: saving an edited scene whose document carries live payload
// bytes must write the `.fscene` text WITH `payloadSource`. The sidecar
// pass records that field on the document, so it has to run before the
// text is serialized — otherwise the first save produces a sidecar no
// consumer can discover (the build hook then fails with "payload ... has
// no bytes to embed").
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  if (!_gpuAvailable()) {
    test(
      'saveFscene writes payloadSource into the text',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('saveFscene writes payloadSource into the text', () async {
    await Scene.initializeStaticResources();
    final document = SceneDocument();
    final payloadId = document.newId();
    document.addPayload(
      PayloadSpec(
        payloadId,
        encoding: PayloadEncoding.matrices,
        bytes: Float32List.fromList(
          List.filled(16, 0)..[0] = 1..[5] = 1..[10] = 1..[15] = 1,
        ).buffer.asUint8List(),
      ),
    );
    final controller = await EditorController.open(EditorSession(document));
    addTearDown(controller.dispose);

    final dir = await Directory.systemTemp.createTemp('fscene_save_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}scene.fscene';

    await saveFscene(controller, path);

    // The sidecar exists and the TEXT references it — both from a single
    // save, without needing a second pass.
    expect(File('$path.b').existsSync(), isTrue,
        reason: 'sidecar should be written next to the scene');
    final text = File(path).readAsStringSync();
    expect(text, contains('payloadSource'),
        reason: 'a save with persistable payloads must reference them');
    final restored = readFscene(text);
    expect(restored.payloadSource, isNotNull);
    expect(File('${dir.path}${Platform.pathSeparator}'
            '${restored.payloadSource}').existsSync(),
        isTrue,
        reason: 'payloadSource must resolve beside the .fscene');
  });
}
