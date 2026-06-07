import 'dart:async';

/// Retries [fn] up to [maxAttempts] times with exponential backoff.
/// Delays: 1s, 2s, 4s. Rethrows the last error if all attempts fail.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  Object? lastError;
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;
      if (attempt < maxAttempts - 1) {
        await Future.delayed(initialDelay * (1 << attempt));
      }
    }
  }
  throw lastError!;
}
