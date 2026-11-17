import 'package:flutter/foundation.dart' show FlutterError;

/// Default backoff delays between transient generated-asset fetch attempts
/// (3 total attempts: initial attempt, +200 ms retry, +500 ms retry).
const List<Duration> defaultGeneratedAssetRetryDelays = <Duration>[
  Duration(milliseconds: 200),
  Duration(milliseconds: 500),
];

/// Whether a non-OK HTTP [status] from a generated-asset `fetch` is transient
/// and eligible for retry (`429 Too Many Requests` or `5xx` server/edge error).
///
/// Client errors such as `404 Not Found` or `403 Forbidden` are permanent and
/// fail immediately without retrying.
bool isRetryableGeneratedAssetHttpStatus(int status) =>
    status == 429 || status >= 500;

/// Carries a non-OK HTTP response [status] from a generated-asset `fetch` so
/// [fetchGeneratedAssetWithRetry] can distinguish HTTP responses from
/// lower-level `fetch` / `arrayBuffer` stream errors.
final class GeneratedAssetHttpStatusException implements Exception {
  const GeneratedAssetHttpStatusException(this.status);

  final int status;
}

/// Runs [attempt] up to `retryDelays.length + 1` times, retrying transient
/// network/stream errors and retryable HTTP statuses (`429`, `>= 500`) while
/// failing immediately on permanent HTTP statuses (`404` and other `4xx`).
Future<T> fetchGeneratedAssetWithRetry<T>({
  required String key,
  required Future<T> Function() attempt,
  List<Duration> retryDelays = defaultGeneratedAssetRetryDelays,
  Future<void> Function(Duration delay) delay = Future<void>.delayed,
}) async {
  for (var index = 0; ; index++) {
    try {
      return await attempt();
    } on GeneratedAssetHttpStatusException catch (error) {
      final hasMoreAttempts = index < retryDelays.length;
      if (!hasMoreAttempts ||
          !isRetryableGeneratedAssetHttpStatus(error.status)) {
        throw FlutterError(
          'Unable to load asset: "$key" (HTTP ${error.status}).',
        );
      }
    } catch (_) {
      if (index >= retryDelays.length) {
        rethrow;
      }
    }
    await delay(retryDelays[index]);
  }
}
