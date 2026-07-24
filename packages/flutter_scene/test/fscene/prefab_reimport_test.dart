// The crux of linked-asset re-import: an imported model's local ids are
// positional, so re-importing an edited model keeps node ids stable and a
// prefab override created against the first import still binds after the
// re-import. Editing buffer content (same glTF structure) is simulated by
// building the same parsed document over different buffer bytes.
//
// Runs only when the source GLB corpus is present (CI without it skips).

import 'dart:io';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a prefab override survives a content-edited re-import', () {
    final path = _resolve('examples/assets_src/fcar.glb');
    if (!File(path).existsSync()) {
      // ignore: avoid_print
      print('Test data missing ($path) - skipping.');
      return;
    }

    // Two imports of the same structure over different buffer content (a flipped
    // byte) stand in for editing the source model.
    final container = parseGlb(File(path).readAsBytesSync());
    final gltf = parseGltfJson(container.json);
    final original = buildSceneDocument(gltf, container.binaryChunk);
    final editedBytes = Uint8List.fromList(container.binaryChunk);
    editedBytes[0] ^= 0xFF;
    final reimported = buildSceneDocument(gltf, editedBytes);

    // Node ids are positional, so the re-import keeps the same node ids.
    expect(
      reimported.nodes.keys.map((id) => id.toToken()).toSet(),
      original.nodes.keys.map((id) => id.toToken()).toSet(),
    );
    // But the content (payload bytes) did change.
    expect(
      reimported.payloads.values.first.bytes,
      isNot(original.payloads.values.first.bytes),
    );

    // An override created against the original import, targeting an internal
    // node by id, renames it.
    final target = original.nodes.keys.firstWhere(
      (id) => !original.roots.contains(id),
    );
    final host = SceneDocument(allocator: IdAllocator(session: 99));
    host.addNode(
      NodeSpec(
        id: host.newId(),
        name: 'Instance',
        instance: PrefabInstanceSpec(
          source: const AssetRef('model'),
          overrides: [
            PropertyOverride(
              target: target,
              path: 'name',
              value: const StringValue('OVERRIDE_SENTINEL'),
            ),
          ],
        ),
      ),
      root: true,
    );

    // The override binds against the original import...
    final composedOriginal = composeScene(host, resolve: (_) => original);
    expect(
      composedOriginal.nodes.values.where((n) => n.name == 'OVERRIDE_SENTINEL'),
      hasLength(1),
    );
    // ...and still binds against the re-imported (edited) model.
    final composedReimported = composeScene(host, resolve: (_) => reimported);
    expect(
      composedReimported.nodes.values.where(
        (n) => n.name == 'OVERRIDE_SENTINEL',
      ),
      hasLength(1),
    );
  });
}

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync()) return candidate;
  }
  return relative;
}
