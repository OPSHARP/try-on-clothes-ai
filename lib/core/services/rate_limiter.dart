import 'dart:async';
import 'dart:math';

/// Rate limiter with automatic retry and exponential backoff for API calls.
///
/// Ensures requests stay within [maxRequestsPerMinute] and provides
/// transparent retry with exponential backoff when rate limits are hit.
/// Designed to be a singleton shared across the entire app so that all
/// API calls from the same device are throttled together — this keeps
/// the app safely under Google's free-tier quota (60 requests/minute).
///
/// Usage:
/// ```dart
/// await rateLimiter.waitForSlot();
/// try {
///   final result = await apiCall();
///   rateLimiter.markSuccess();
///   return result;
/// } on DioException catch (e) {
///   if (e.response?.statusCode == 429) {
///     final delay = rateLimiter.getBackoffDelay();
///     await Future.delayed(Duration(milliseconds: delay));
///     // retry...
///   }
/// }
/// ```
class RateLimiter {
  final int maxRequestsPerMinute;

  /// Minimum gap between consecutive requests (in milliseconds).
  /// Set to 1200ms ⇒ 50 requests/minute, safely under the 60 RPM limit.
  static const int _minRequestGapMs = 1200;

  /// Maximum retries before giving up on a 429 response.
  static const int maxRetries = 3;

  /// Timestamps of requests made in the last 60 seconds.
  final List<DateTime> _requestTimestamps = [];

  /// Count of consecutive 429 (or server) errors for backoff calculation.
  int _consecutiveErrors = 0;

  RateLimiter({this.maxRequestsPerMinute = 50});

  // ── Slot management ──

  /// Wait until a rate-limit slot is available, then record the slot.
  ///
  /// Blocks the caller if:
  /// 1. The per-minute quota has been reached (waits for oldest slot to expire)
  /// 2. The last request was less than [_minRequestGapMs] ago (smooths bursts)
  Future<void> waitForSlot() async {
    _cleanOldTimestamps();

    if (_requestTimestamps.length >= maxRequestsPerMinute) {
      // ── Quota exhausted — wait for the oldest slot to drop off ──
      final oldest = _requestTimestamps.first;
      final ageMs = DateTime.now().difference(oldest).inMilliseconds;
      final waitMs = Duration(minutes: 1).inMilliseconds - ageMs + 100;
      if (waitMs > 0) {
        await Future.delayed(Duration(milliseconds: waitMs));
      }
      // Re-check after waiting (should now have room)
      return waitForSlot();
    }

    // ── Inter-request gap smoothing ──
    if (_requestTimestamps.isNotEmpty) {
      final last = _requestTimestamps.last;
      final elapsed = DateTime.now().difference(last).inMilliseconds;
      if (elapsed < _minRequestGapMs) {
        await Future.delayed(
          Duration(milliseconds: _minRequestGapMs - elapsed),
        );
      }
    }

    // Record the slot
    _requestTimestamps.add(DateTime.now());
  }

  /// Remove timestamps older than 60 seconds.
  void _cleanOldTimestamps() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    _requestTimestamps.removeWhere((t) => t.isBefore(cutoff));
  }

  // ── Success / Failure tracking ──

  /// Mark a successful API call (resets the consecutive-error counter).
  void markSuccess() {
    _consecutiveErrors = 0;
  }

  /// Return the exponential-backoff delay (in milliseconds) for the next
  /// retry attempt.
  ///
  /// Sequence (after each consecutive error): 1 000, 2 000, 4 000, 8 000 …
  int getBackoffDelay() {
    _consecutiveErrors++;
    // Cap at 5 (32 s) to avoid absurdly long waits
    final exponent = _consecutiveErrors.clamp(0, 5);
    return pow(2, exponent).toInt() * 1000;
  }

  /// Reset consecutive-error counter (e.g. after a successful request).
  void resetErrors() {
    _consecutiveErrors = 0;
  }
}
