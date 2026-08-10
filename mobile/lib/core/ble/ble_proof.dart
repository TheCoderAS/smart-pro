import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Per-command proof for BLE (firmware v11.24.0, UX stories v5.1 Epic 5).
///
/// The raw token never crosses the air. Every command carries:
///   `n` — first 16 hex chars of the token (which token, not the token)
///   `k` — counter, starts at 1, +1 per command, reset every connection
///   `p` — HMAC-SHA256(token, nonce ‖ counter)[0..7] as hex
///
/// The token is used as its **ASCII bytes** for the HMAC key; the counter
/// is appended to the 8-byte session nonce as 4 bytes big-endian. The
/// nonce is read from characteristic `…38` and is different every
/// connection, so a recorded command replays against a stale nonce and
/// a spent counter — both rejected.
class BleProof {
  const BleProof({required this.n, required this.k, required this.p});

  /// Token hint — first 16 hex chars of the token.
  final String n;

  /// Monotonic per-connection counter.
  final int k;

  /// 16 hex chars — the truncated HMAC.
  final String p;

  Map<String, Object?> toFields() => {'n': n, 'k': k, 'p': p};
}

/// Computes the proof for one command. Pure — no I/O, so it is unit
/// tested against the firmware's vectors.
BleProof computeBleProof({
  required String token,
  required List<int> sessionNonce,
  required int counter,
}) {
  final message = Uint8List(sessionNonce.length + 4)
    ..setRange(0, sessionNonce.length, sessionNonce)
    ..[sessionNonce.length] = (counter >> 24) & 0xFF
    ..[sessionNonce.length + 1] = (counter >> 16) & 0xFF
    ..[sessionNonce.length + 2] = (counter >> 8) & 0xFF
    ..[sessionNonce.length + 3] = counter & 0xFF;

  final mac = Hmac(sha256, utf8.encode(token)).convert(message).bytes;
  return BleProof(
    n: token.length >= 16 ? token.substring(0, 16) : token,
    k: counter,
    p: _hex(mac.sublist(0, 8)),
  );
}

String _hex(List<int> bytes) => [
      for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
    ].join();
