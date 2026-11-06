import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Thrown when the backend does not answer in time. Extends
/// [http.ClientException] so gotrue treats it as a retryable network error
/// (it keeps the session instead of signing the user out).
class RequestTimeoutException extends http.ClientException {
  RequestTimeoutException(super.message, [super.uri]);
}

/// HTTP client handed to Supabase so a struggling API gateway can never leave
/// a screen waiting indefinitely.
///
/// - Every request gets a deadline for the response headers. Storage uploads
///   and edge functions (payment checkout) get a longer one.
/// - Reads (GET/HEAD) are retried a few times on transient gateway errors,
///   with exponential backoff and jitter.
/// - Writes and RPCs (POST/PATCH/PUT/DELETE) are never retried here: an order
///   that timed out may still have been created. Checkout handles that with
///   its idempotency key.
/// - Auth is not retried here either; gotrue has its own refresh retries.
class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({
    http.Client? inner,
    this.defaultTimeout = const Duration(seconds: 20),
    this.longTimeout = const Duration(seconds: 90),
    Future<void> Function(Duration)? sleep,
    Random? random,
  }) : _inner = inner ?? http.Client(),
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random();

  static const maxRetries = 2;
  static const _retryBase = Duration(milliseconds: 400);

  /// Gateway and upstream-unreachable statuses worth one more try.
  static const _transientStatuses = {502, 503, 504, 520, 521, 522, 523, 524};

  final http.Client _inner;
  final Duration defaultTimeout;
  final Duration longTimeout;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final timeout =
        path.startsWith('/storage/') || path.startsWith('/functions/')
        ? longTimeout
        : defaultTimeout;
    // Only plain requests can be rebuilt for another attempt; a streamed or
    // multipart body is consumed by the first send.
    final canRetry =
        request is http.Request &&
        (request.method == 'GET' || request.method == 'HEAD') &&
        !path.startsWith('/auth/');

    var attempt = 0;
    var current = request;
    while (true) {
      try {
        final response = await _inner
            .send(current)
            .timeout(
              timeout,
              onTimeout: () => throw RequestTimeoutException(
                'Request timeout after ${timeout.inSeconds}s: '
                '${request.method} $path',
                request.url,
              ),
            );
        if (!canRetry ||
            attempt >= maxRetries ||
            !_transientStatuses.contains(response.statusCode)) {
          return response;
        }
        await response.stream.drain<void>();
      } on RequestTimeoutException {
        // It already waited the full deadline; retrying would only double
        // the wait and the load on the gateway.
        rethrow;
      } on http.ClientException {
        if (!canRetry || attempt >= maxRetries) rethrow;
      }

      await _sleep(_backoff(attempt));
      attempt++;
      current = _copy(request);
    }
  }

  Duration _backoff(int attempt) {
    final base = _retryBase * pow(2, attempt).toInt();
    final jitter = _random.nextInt(base.inMilliseconds ~/ 2 + 1);
    return base + Duration(milliseconds: jitter);
  }

  static http.Request _copy(http.Request original) =>
      http.Request(original.method, original.url)
        ..headers.addAll(original.headers)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection
        ..bodyBytes = original.bodyBytes;

  @override
  void close() => _inner.close();
}
