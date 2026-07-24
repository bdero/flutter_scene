// Covers inlining an authored scene's external image assets into a
// self-contained document, the build step that lets an editor-saved `.fscene`
// (which references imported images by path) become a `.fsceneb` whose textures
// travel as embedded bytes (no asset-bundle lookup at runtime).

import 'dart:io';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/importer/inline_assets.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('inline_assets'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  // Writes a solid-color PNG under imported/ and returns its scene-relative key.
  String writeImage(String name, int w, int h) {
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgba8(10, 20, 30, 255));
    final dir = Directory('${tempDir.path}/imported')
      ..createSync(recursive: true);
    File('${dir.path}/$name').writeAsBytesSync(img.encodePng(image));
    return 'imported/$name';
  }

  Uri sceneUri() => File('${tempDir.path}/scene.fscene').uri;

  test('resolves and embeds an external texture as an rgba8 payload', () {
    final key = writeImage('wood.png', 4, 2);
    final document = SceneDocument();
    final texture = document.addResource(
      TextureResource(document.newId(), asset: AssetRef(key)),
    );

    final assets = resolveExternalImageAssets(document, sceneUri());
    expect(assets.map((a) => a.key), [key]);

    inlineExternalImageAssets(document, assets);

    final embedded = document.resource(texture.id)! as TextureResource;
    expect(embedded.asset, isNull, reason: 'asset reference is replaced');
    expect(embedded.payload, isNotNull);
    final payload = document.payload(embedded.payload!)!;
    expect(payload.format, 'rgba8');
    expect(payload.width, 4);
    expect(payload.height, 2);
    expect(payload.bytes!.length, 4 * 2 * 4);

    // The container now embeds the bytes, so it serializes without the
    // "payload has no bytes" failure and round-trips them.
    final reread = readFsceneb(writeFsceneb(document));
    final rereadTexture = reread.resource(texture.id)! as TextureResource;
    expect(reread.payload(rereadTexture.payload!)!.bytes, payload.bytes);
  });

  test('textures sharing one image collapse to a single payload', () {
    final key = writeImage('shared.png', 2, 2);
    final document = SceneDocument();
    final a = document.addResource(
      TextureResource(document.newId(), asset: AssetRef(key)),
    );
    final b = document.addResource(
      TextureResource(document.newId(), asset: AssetRef(key)),
    );

    final assets = resolveExternalImageAssets(document, sceneUri());
    expect(assets, hasLength(1), reason: 'deduplicated by key');

    inlineExternalImageAssets(document, assets);

    final pa = (document.resource(a.id)! as TextureResource).payload;
    final pb = (document.resource(b.id)! as TextureResource).payload;
    expect(pa, isNotNull);
    expect(pa, pb, reason: 'both textures point at the one embedded payload');
    expect(document.payloads, hasLength(1));
  });

  test('embeds an environment HDR as an encoded payload tagged hdr', () {
    final dir = Directory('${tempDir.path}/imported')
      ..createSync(recursive: true);
    final hdrBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    File('${dir.path}/sky.hdr').writeAsBytesSync(hdrBytes);
    const key = 'imported/sky.hdr';
    final document = SceneDocument();
    final env = document.addResource(
      EnvironmentResource(
        document.newId(),
        environment: AssetEnvironment(AssetRef(key)),
      ),
    );

    final assets = resolveExternalImageAssets(document, sceneUri());
    expect(assets.map((a) => a.key), [key]);

    inlineExternalImageAssets(document, assets);

    final spec =
        (document.resource(env.id)! as EnvironmentResource).environment;
    expect(spec, isA<PayloadEnvironment>());
    // The encoded HDR bytes are embedded verbatim (no rgba8 clamp that would
    // crush the radiance range), tagged so the realizer picks the HDR decoder.
    final payload = document.payload((spec as PayloadEnvironment).payload)!;
    expect(payload.format, 'hdr');
    expect(payload.bytes, hdrBytes);

    final reread = readFsceneb(writeFsceneb(document));
    final rspec = (reread.resource(env.id)! as EnvironmentResource).environment;
    expect(rspec, isA<PayloadEnvironment>());
    expect(
      reread.payload((rspec as PayloadEnvironment).payload)!.bytes,
      hdrBytes,
    );
  });

  test('a payload environment round-trips through the json manifest', () {
    final document = SceneDocument();
    final payload = document.addPayload(
      PayloadSpec(
        document.newId(),
        encoding: PayloadEncoding.image,
        format: 'hdr',
        length: 3,
        bytes: Uint8List.fromList([9, 9, 9]),
      ),
    );
    final env = document.addResource(
      EnvironmentResource(
        document.newId(),
        environment: PayloadEnvironment(payload.id),
      ),
    );

    final reread = readFscene(writeFscene(document));
    final spec = (reread.resource(env.id)! as EnvironmentResource).environment;
    expect(spec, isA<PayloadEnvironment>());
    expect((spec as PayloadEnvironment).payload, payload.id);
  });

  test('a missing image is left as a reference, not a build failure', () {
    final document = SceneDocument();
    final texture = document.addResource(
      TextureResource(document.newId(), asset: AssetRef('imported/gone.png')),
    );

    final assets = resolveExternalImageAssets(document, sceneUri());
    expect(assets, isEmpty);

    inlineExternalImageAssets(document, assets);
    final unchanged = document.resource(texture.id)! as TextureResource;
    expect(unchanged.asset?.key, 'imported/gone.png');
    expect(unchanged.payload, isNull);
  });
}
