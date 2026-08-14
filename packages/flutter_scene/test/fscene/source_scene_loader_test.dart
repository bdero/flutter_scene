// Covers debug source-direct scene loading: resolving `.fscene`/`.fsceneb`
// sources under a project root, attaching payload-sidecar bytes, and rebasing
// document-relative references to project-relative keys the overlay bundle
// serves.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/source/source_scene_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('source_scenes');
    debugSetSceneSourceRoot(root.path);
  });

  tearDown(() {
    debugSetSceneSourceRoot(null);
    root.deleteSync(recursive: true);
  });

  File write(String key, List<int> bytes) => File('${root.path}/$key')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  File writeText(String key, String text) => File('${root.path}/$key')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  test('inactive without a root, active with one', () {
    debugSetSceneSourceRoot(null);
    expect(activeSceneSourceLoader(), isNull);
    expect(sceneSourceLoadingActive, isFalse);

    debugSetSceneSourceRoot(root.path);
    expect(activeSceneSourceLoader(), isNotNull);
    expect(sceneSourceLoadingActive, isTrue);

    debugSetSceneSourceRoot('${root.path}/nowhere');
    expect(activeSceneSourceLoader(), isNull);
  });

  test('resolveScene probes source spellings', () {
    writeText('scenes/level.fscene', writeFscene(SceneDocument()));
    write('imported/part.fsceneb', writeFsceneb(SceneDocument()));
    final loader = activeSceneSourceLoader()!;

    expect(loader.resolveScene('scenes/level'), 'scenes/level.fscene');
    expect(loader.resolveScene('scenes/level.fscene'), 'scenes/level.fscene');
    expect(loader.resolveScene('scenes/level.fsceneb'), 'scenes/level.fscene');
    expect(loader.resolveScene('imported/part'), 'imported/part.fsceneb');
    expect(loader.resolveScene('missing'), isNull);
    expect(loader.resolveScene('assets/foo.glb'), isNull);
  });

  test(
    'readDocument attaches payload-sidecar bytes and records files',
    () async {
      final source = SceneDocument();
      final payload = source.addPayload(
        PayloadSpec(
          source.newId(),
          encoding: PayloadEncoding.vertexBuffer,
          layout: 'unskinned',
          length: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      write('scenes/level.payloads.fsceneb', writeFsceneb(source));
      final manifest = readFscene(writeFscene(source))
        ..payloadSource = 'level.payloads.fsceneb';
      writeText('scenes/level.fscene', writeFscene(manifest));

      final loader = activeSceneSourceLoader()!;
      final dependencies = <String>{};
      final document = await loader.readDocument(
        'scenes/level.fscene',
        dependencies,
      );
      expect(document.payload(payload.id)?.bytes, [1, 2, 3, 4]);
      expect(dependencies, {
        'scenes/level.fscene',
        'scenes/level.payloads.fsceneb',
      });
    },
  );

  test('a missing payload sidecar degrades instead of failing', () async {
    final source = SceneDocument();
    final payload = source.addPayload(
      PayloadSpec(
        source.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned',
        length: 4,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
    );
    final manifest = readFscene(writeFscene(source))
      ..payloadSource = 'gone.fsceneb';
    writeText('scenes/level.fscene', writeFscene(manifest));

    final loader = activeSceneSourceLoader()!;
    final document = await loader.readDocument('scenes/level.fscene', {});
    expect(document.payload(payload.id)?.bytes, isNull);
  });

  test('rebases image and prefab references that exist on disk', () async {
    write('scenes/imported/part.fsceneb', writeFsceneb(SceneDocument()));
    write('scenes/imported/wood.png', [1]);

    final document = SceneDocument();
    document.addResource(
      TextureResource(
        document.newId(),
        asset: AssetRef('imported/wood.png'),
        content: 'normal',
      ),
    );
    document.addResource(
      TextureResource(
        document.newId(),
        asset: AssetRef('imported/missing.png'),
        content: 'normal',
      ),
    );
    final instanced = document.addNode(
      NodeSpec(id: document.newId()),
      root: true,
    );
    instanced.instance = PrefabInstanceSpec(
      source: AssetRef('imported/part.fsceneb'),
    );
    writeText('scenes/level.fscene', writeFscene(document));

    final loader = activeSceneSourceLoader()!;
    final read = await loader.readDocument('scenes/level.fscene', {});
    final refs = read.resources.values
        .whereType<TextureResource>()
        .map((texture) => texture.asset!.key)
        .toSet();
    expect(refs, {'scenes/imported/wood.png', 'imported/missing.png'});
    final instance = read.nodes.values
        .firstWhere((node) => node.instance != null)
        .instance!;
    expect(instance.source.key, 'scenes/imported/part.fsceneb');
    expect(loader.isSourceKey('scenes/imported/part.fsceneb'), isTrue);
    expect(loader.isSourceKey('imported/missing.png'), isFalse);
  });

  test(
    'rebases fmat material references, healing under-root absolutes',
    () async {
      write('materials/glass.fmat', [1]);

      final document = SceneDocument();
      final relative = document.addResource(
        MaterialResource(
          document.newId(),
          type: 'fmat',
          asset: AssetRef('../materials/glass.fmat'),
        ),
      );
      final absolute = document.addResource(
        MaterialResource(
          document.newId(),
          type: 'fmat',
          asset: AssetRef('${root.path}/materials/glass.fmat'),
        ),
      );
      final external = document.addResource(
        MaterialResource(
          document.newId(),
          type: 'fmat',
          asset: AssetRef('/elsewhere/other.fmat'),
        ),
      );
      writeText('scenes/level.fscene', writeFscene(document));

      final loader = activeSceneSourceLoader()!;
      final read = await loader.readDocument('scenes/level.fscene', {});
      String? keyOf(LocalId id) =>
          (read.resources[id] as MaterialResource?)?.asset?.key;
      expect(keyOf(relative.id), 'materials/glass.fmat');
      expect(keyOf(absolute.id), 'materials/glass.fmat');
      expect(keyOf(external.id), '/elsewhere/other.fmat');
    },
  );

  test('only a permission denial deactivates source loading for the run', () {
    final loader = activeSceneSourceLoader()!;
    expect(loader.deactivateOnAccessError(StateError('other'), 'x'), isFalse);
    expect(activeSceneSourceLoader(), isNotNull);
    // A transient failure falls this load back without deactivating.
    expect(
      loader.deactivateOnAccessError(
        const FileSystemException('Cannot open file', 'x'),
        'x',
      ),
      isTrue,
    );
    expect(activeSceneSourceLoader(), isNotNull);
    expect(sceneSourceLoadingActive, isTrue);
    // A denial (the macOS App Sandbox) deactivates for the run.
    expect(
      loader.deactivateOnAccessError(
        const FileSystemException(
          'Cannot open file',
          'x',
          OSError('Operation not permitted', 1),
        ),
        'x',
      ),
      isTrue,
    );
    expect(activeSceneSourceLoader(), isNull);
    expect(sceneSourceLoadingActive, isFalse);
  });

  test('the overlay bundle serves project files by key', () async {
    write('scenes/blob.bin', [9, 8, 7]);
    final loader = activeSceneSourceLoader()!;
    final data = await loader.bundle.load('scenes/blob.bin');
    expect(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), [
      9,
      8,
      7,
    ]);
  });
}
