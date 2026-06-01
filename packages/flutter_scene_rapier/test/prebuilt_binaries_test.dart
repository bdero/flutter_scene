// Unit tests for the prebuilt-binary download helper used by the build
// hook. These exercise the download / checksum / cache logic against a
// loopback HTTP server, so they need no network and no Rust toolchain.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../hook/prebuilt_binaries.dart';

void main() {
  group('NativeBinaryManifest.parse', () {
    test('reads version, base url, tag, and per-triple entries', () {
      final manifest = NativeBinaryManifest.parse({
        'version': '1.2.3',
        'base_url': 'https://example.com/dl',
        'tag': 'flutter_scene_rapier-1.2.3',
        'binaries': {
          'aarch64-apple-ios': {'file': 'lib-ios.dylib', 'sha256': 'abc'},
          'aarch64-linux-android': {'file': 'lib-android.so', 'sha256': 'def'},
        },
      });

      expect(manifest.version, '1.2.3');
      expect(manifest.baseUrl, 'https://example.com/dl');
      expect(manifest.tag, 'flutter_scene_rapier-1.2.3');
      expect(manifest.binaries.keys, hasLength(2));
      expect(manifest.binaries['aarch64-apple-ios']!.file, 'lib-ios.dylib');
      expect(manifest.binaries['aarch64-linux-android']!.sha256, 'def');
    });

    test('tolerates a manifest with no binaries map', () {
      final manifest = NativeBinaryManifest.parse({
        'version': '0.0.1',
        'base_url': 'https://example.com',
        'tag': 't',
      });
      expect(manifest.binaries, isEmpty);
    });
  });

  group('downloadVerifiedBinary', () {
    late Directory tempDir;
    final payload = List<int>.generate(2048, (i) => i % 256);
    final payloadSha = sha256.convert(payload).toString();

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('fsr_prebuilt_test');
    });
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('downloads, verifies, caches, and returns the file', () async {
      final server = await _serve((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..add(payload);
        return request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final cacheFile = File('${tempDir.path}/nested/lib.dylib');
      final result = await downloadVerifiedBinary(
        url: _urlOf(server),
        expectedSha256: payloadSha,
        cacheFile: cacheFile,
        label: 'test lib',
      );

      expect(result.path, cacheFile.path);
      expect(result.existsSync(), isTrue);
      expect(result.readAsBytesSync(), payload);
    });

    test('throws on a checksum mismatch and does not write the file', () async {
      final server = await _serve((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..add(payload);
        return request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final cacheFile = File('${tempDir.path}/lib.dylib');
      await expectLater(
        downloadVerifiedBinary(
          url: _urlOf(server),
          expectedSha256: 'not_the_real_hash',
          cacheFile: cacheFile,
          label: 'test lib',
        ),
        throwsA(isA<Exception>()),
      );
      expect(cacheFile.existsSync(), isFalse);
    });

    test('reuses a matching cache file without downloading', () async {
      // A server that always errors: a cache hit must not hit it.
      final server = await _serve((request) {
        request.response.statusCode = HttpStatus.internalServerError;
        return request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final cacheFile = File('${tempDir.path}/lib.dylib')
        ..writeAsBytesSync(payload);

      final result = await downloadVerifiedBinary(
        url: _urlOf(server),
        expectedSha256: payloadSha,
        cacheFile: cacheFile,
        label: 'test lib',
      );
      expect(result.readAsBytesSync(), payload);
    });

    test('re-downloads when a stale cache file fails the checksum', () async {
      var hits = 0;
      final server = await _serve((request) {
        hits++;
        request.response
          ..statusCode = HttpStatus.ok
          ..add(payload);
        return request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final cacheFile = File('${tempDir.path}/lib.dylib')
        ..writeAsBytesSync([1, 2, 3]); // wrong contents

      final result = await downloadVerifiedBinary(
        url: _urlOf(server),
        expectedSha256: payloadSha,
        cacheFile: cacheFile,
        label: 'test lib',
      );
      expect(result.readAsBytesSync(), payload);
      expect(hits, 1);
    });
  });
}

Future<HttpServer> _serve(Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

Uri _urlOf(HttpServer server) =>
    Uri.parse('http://${server.address.address}:${server.port}/lib');
