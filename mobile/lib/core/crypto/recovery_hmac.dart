import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// The BLE recovery response (API §8, step 4):
/// HMAC-SHA256(recovery_key, challenge) truncated to 8 bytes.
///
/// The recovery key arrives from the user as 32 hex characters
/// (16 bytes) printed on the card.
Uint8List recoveryResponse(String recoveryKeyHex, List<int> challenge) {
  final key = parseRecoveryKey(recoveryKeyHex);
  final mac = Hmac(sha256, key).convert(challenge).bytes;
  return Uint8List.fromList(mac.sublist(0, 8));
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
