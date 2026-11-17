// Verifies transient retry backoff (up to 3 attempts at 200 ms / 500 ms) and
// immediate non-retryable 4xx failure for web generated-asset fetches.

// ignore_for_file: implementation_imports
library;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_scene/src/generated_assets/generated_asset_fetch_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isRetryableGeneratedAssetHttpStatus', () {
    test('retries 429 and 5xx statuses but rejects 404 and other 4xx', () {
      expect(isRetryableGeneratedAssetHttpStatus(429), isTrue);
      expect(isRetryableGeneratedAssetHttpStatus(500), isTrue);
      expect(isRetryableGeneratedAssetHttpStatus(502), isTrue);
      expect(isRetryableGeneratedAssetHttpStatus(503), isTrue);
      expect(isRetryableGeneratedAssetHttpStatus(504), isTrue);

      expect(isRetryableGeneratedAssetHttpStatus(400), isFalse);
      expect(isRetryableGeneratedAssetHttpStatus(401), isFalse);
      expect(isRetryableGeneratedAssetHttpStatus(403), isFalse);
      expect(isRetryableGeneratedAssetHttpStatus(404), isFalse);
      expect(isRetryableGeneratedAssetHttpStatus(410), isFalse);
    });
  });

  group('fetchGeneratedAssetWithRetry', () {
    test('succeeds on first attempt without sleeping', () async {
      final sleeps = <Duration>[];
      var calls = 0;

      final value = await fetchGeneratedAssetWithRetry<int>(
        key: 'flutter_scene_generated/manifest.json',
        delay: (d) async => sleeps.add(d),
        attempt: () async {
          calls++;
          return 42;
        },
      );

      expect(value, 42);
      expect(calls, 1);
      expect(sleeps, isEmpty);
    });

    test(
      'retries transient network/body errors and 5xx/429 with 200ms then 500ms backoff',
      () async {
        final sleeps = <Duration>[];
        var calls = 0;

        final value = await fetchGeneratedAssetWithRetry<String>(
          key: 'flutter_scene_generated/opengl_es/base.shaderbundle',
          delay: (d) async => sleeps.add(d),
          attempt: () async {
            calls++;
            if (calls == 1) {
              throw StateError('TypeError: Failed to fetch');
            }
            if (calls == 2) {
              throw const GeneratedAssetHttpStatusException(503);
            }
            return 'ok';
          },
        );

        expect(value, 'ok');
        expect(calls, 3);
        expect(sleeps, const <Duration>[
          Duration(milliseconds: 200),
          Duration(milliseconds: 500),
        ]);
      },
    );

    test(
      'retries HTTP 429 and throws FlutterError after 3 total attempts',
      () async {
        final sleeps = <Duration>[];
        var calls = 0;

        await expectLater(
          () => fetchGeneratedAssetWithRetry<void>(
            key:
                'flutter_scene_generated/opengl_es/base.shaderbundle.wgsl.json',
            delay: (d) async => sleeps.add(d),
            attempt: () async {
              calls++;
              throw const GeneratedAssetHttpStatusException(429);
            },
          ),
          throwsA(
            isA<FlutterError>().having(
              (e) => e.message,
              'message',
              contains('(HTTP 429)'),
            ),
          ),
        );

        expect(calls, 3);
        expect(sleeps, const <Duration>[
          Duration(milliseconds: 200),
          Duration(milliseconds: 500),
        ]);
      },
    );

    test('rethrows underlying network error after 3 total attempts', () async {
      final sleeps = <Duration>[];
      var calls = 0;

      await expectLater(
        () => fetchGeneratedAssetWithRetry<void>(
          key: 'flutter_scene_generated/manifest.json',
          delay: (d) async => sleeps.add(d),
          attempt: () async {
            calls++;
            throw StateError('arrayBuffer stream reset #$calls');
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'arrayBuffer stream reset #3',
          ),
        ),
      );

      expect(calls, 3);
      expect(sleeps, const <Duration>[
        Duration(milliseconds: 200),
        Duration(milliseconds: 500),
      ]);
    });

    test('does NOT retry 404 or other permanent 4xx statuses', () async {
      for (final status in const <int>[400, 403, 404]) {
        final sleeps = <Duration>[];
        var calls = 0;

        await expectLater(
          () => fetchGeneratedAssetWithRetry<void>(
            key: 'flutter_scene_generated/missing.shaderbundle',
            delay: (d) async => sleeps.add(d),
            attempt: () async {
              calls++;
              throw GeneratedAssetHttpStatusException(status);
            },
          ),
          throwsA(
            isA<FlutterError>().having(
              (e) => e.message,
              'message',
              'Unable to load asset: "flutter_scene_generated/missing.shaderbundle" (HTTP $status).',
            ),
          ),
        );

        expect(calls, 1, reason: 'HTTP $status must not retry');
        expect(sleeps, isEmpty);
      }
    });
  });
}
