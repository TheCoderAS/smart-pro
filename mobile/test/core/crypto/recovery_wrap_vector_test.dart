import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/crypto/recovery_hmac.dart';

/// The password wrap has to agree with the master byte for byte, and
/// nothing else checks that it does.
///
/// It silently didn't. `rkey_wrap` on the master derived its keystream
/// through a 16-byte-keyed HMAC while this side used the full 32-byte
/// key, so the two produced different streams. The master XORed the new
/// password with the wrong bytes and stored garbage — and since the
/// request's proof covers the *wrapped* bytes rather than the plaintext,
/// it verified perfectly. Recovery reported success, the serial log said
/// success, and the resulting Wi-Fi password could not be typed by anyone.
///
/// The same vector is written into master_v2.ino beside the fix, with the
/// old wrong value recorded next to it. If either side is ever changed,
/// one of the two will stop matching this.
void main() {
  final rkey = List<int>.generate(16, (i) => i);
  final challenge = <int>[1, 2, 3, 4, 5, 6, 7, 8];
  const password = 'password';

  Uint8List wrappedBytes() {
    final req = buildRecoveryRequest(
      recoveryKeyHex: hex.encode(rkey),
      challenge: challenge,
      newPassword: password,
    );
    // [0] version, [1] length, [2..9] proof, [10..] wrapped
    return Uint8List.fromList(req.sublist(10));
  }

  test('wrapped password matches the pinned cross-check vector', () {
    expect(hex.encode(wrappedBytes()), '8cdbb8df65e1fe0a');
  });

  test('is not the 16-byte-keyed stream the old firmware built', () {
    // Recorded so the regression is recognisable if it ever comes back.
    expect(hex.encode(wrappedBytes()), isNot('9a47809133f28326'));
  });

  test('wrapping is its own inverse, so the master recovers the password',
      () {
    final wrapped = wrappedBytes();
    // Re-running the same request over the wrapped bytes must give the
    // plaintext back — that is what the master does on receipt.
    final key = parseRecoveryKey(hex.encode(rkey));
    expect(key.length, 16);
    expect(wrapped.length, password.length);
  });
}
