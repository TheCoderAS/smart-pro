import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// Recovery request, v2 (story Epic 8).
///
/// The app chooses the new password and it never crosses Bluetooth in the
/// clear. The link is open and this carries the next whole-home password,
/// so it travels wrapped with a key derived from the recovery key, and the
/// proof covers the wrapped bytes as well as the challenge — a recorded
/// exchange yields neither the recovery key nor the password, and cannot be
/// replayed with a different password grafted on.
///
///   [0]      version, 0x02
///   [1]      password length, 8..63
///   [2..9]   HMAC-SHA256(key, challenge ‖ ver ‖ len ‖ wrapped)[0..7]
///   [10..]   the password, wrapped
Uint8List buildRecoveryRequest({
  required String recoveryKeyHex,
  required List<int> challenge,
  required String newPassword,
}) {
  final key = parseRecoveryKey(recoveryKeyHex);
  final clear = utf8.encode(newPassword);
  if (clear.length < 8 || clear.length > 63) {
    throw const FormatException('password must be 8 to 63 characters');
  }
  if (challenge.length != 8) {
    throw const FormatException('challenge must be 8 bytes');
  }

  final wrapped = Uint8List.fromList(clear);
  _wrap(key, challenge, wrapped);

  // The proof is taken over challenge ‖ ver ‖ len ‖ wrapped — it starts
  // with the challenge, not with the request header.
  final msg = Uint8List(8 + 2 + wrapped.length)
    ..setRange(0, 8, challenge)
    ..[8] = 0x02
    ..[9] = wrapped.length
    ..setRange(10, 10 + wrapped.length, wrapped);
  final proof = Hmac(sha256, key).convert(msg).bytes.sublist(0, 8);

  return Uint8List(10 + wrapped.length)
    ..[0] = 0x02
    ..[1] = wrapped.length
    ..setRange(2, 10, proof)
    ..setRange(10, 10 + wrapped.length, wrapped);
}

/// Keystream from the recovery key and the challenge. XOR is its own
/// inverse, so this both wraps and unwraps — the firmware runs the same
/// construction.
void _wrap(Uint8List key, List<int> challenge, Uint8List buf) {
  final stream = Hmac(sha256, key).convert(challenge).bytes;
  final streamKey = Uint8List.fromList(stream);
  for (var off = 0; off < buf.length; off += 32) {
    final ctr = Uint8List(36)
      ..setRange(0, 32, streamKey)
      ..[32] = (off >> 24) & 0xFF
      ..[33] = (off >> 16) & 0xFF
      ..[34] = (off >> 8) & 0xFF
      ..[35] = off & 0xFF;
    final ks = Hmac(sha256, streamKey).convert(ctr).bytes;
    for (var k = 0; k < 32 && off + k < buf.length; k++) {
      buf[off + k] ^= ks[k];
    }
  }
}

/// The master's verdict. Explicit by design: the old firmware went silent
/// on a wrong key, which is indistinguishable from a dead link.
class RecoveryVerdict {
  const RecoveryVerdict({
    required this.accepted,
    required this.scope,
    required this.waitSeconds,
    this.error,
  });

  factory RecoveryVerdict.fromJson(Map<String, dynamic> json) =>
      RecoveryVerdict(
        accepted: json['ok'] == true,
        scope: json['scope'] as String? ?? '',
        waitSeconds: (json['wait'] as num?)?.toInt() ?? 0,
        error: json['err'] as String?,
      );

  final bool accepted;

  /// "mesh" or "device" — the master decides, never the app.
  final String scope;

  /// Seconds before another attempt is allowed. Comes from the device;
  /// the app renders this countdown and never computes a backoff itself.
  final int waitSeconds;

  final String? error;

  bool get wholeHome => scope == 'mesh';
}

/// Parses and validates the card's recovery key. Accepts upper/lower
/// case and stray spaces or dashes (people type what they see).
/// Throws [FormatException] unless exactly 32 hex chars remain.
Uint8List parseRecoveryKey(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
  if (cleaned.length != 32 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(cleaned)) {
    throw const FormatException('recovery key must be 32 hex characters');
  }
  return Uint8List.fromList(hex.decode(cleaned));
}
