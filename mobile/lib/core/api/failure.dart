/// Sealed failure hierarchy for every call to the master, per
/// UNISYNC_API_REFERENCE_v1.md §2 "Failures".
///
/// The Dio interceptor maps raw transport errors and status codes into
/// these, so the rest of the app only ever pattern-matches on
/// [ApiFailure] — no DioException leaks past `core/api/`.
sealed class ApiFailure implements Exception {
  const ApiFailure();

  /// Human-readable, log-safe summary (no tokens, no passwords).
  String describe();
}

/// No route to 192.168.4.1 — the phone is (probably) not on the
/// device's Wi-Fi, or the master is down.
final class Unreachable extends ApiFailure {
  const Unreachable([this.cause]);

  final Object? cause;

  @override
  String describe() => 'Master unreachable';
}

/// 401 — no or invalid token. Per API §2 the app should prompt for the
/// password and retry once.
final class Unauthorized extends ApiFailure {
  const Unauthorized();

  @override
  String describe() => 'Not authorized (401)';
}

/// 423 — locked out after 5 wrong passwords, roughly 5 minutes.
final class LockedOut extends ApiFailure {
  const LockedOut({this.retryAfter = const Duration(minutes: 5)});

  final Duration retryAfter;

  @override
  String describe() => 'Locked out (423), retry after $retryAfter';
}

/// 429 — rate limited (40 requests / 10 s). Back off and retry.
final class RateLimited extends ApiFailure {
  const RateLimited({this.retryAfter = const Duration(seconds: 10)});

  final Duration retryAfter;

  @override
  String describe() => 'Rate limited (429), retry after $retryAfter';
}

/// Any other non-2xx from the master, body preserved for surfacing
/// specific errors (e.g. firmware upload's {"error": "..."} bodies).
final class ServerFailure extends ApiFailure {
  const ServerFailure(this.status, this.body);

  final int status;
  final String body;

  /// The `error` field of a JSON error body, when present.
  /// Kept lightweight — callers that need full parsing do it themselves.
  String? get errorMessage {
    final match = RegExp('"error"\\s*:\\s*"([^"]*)"').firstMatch(body);
    return match?.group(1);
  }

  @override
  String describe() => 'Server error $status';
}
