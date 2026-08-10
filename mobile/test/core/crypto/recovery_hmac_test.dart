import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/crypto/recovery_hmac.dart';

void main() {
  group('parseRecoveryKey', () {
    test('accepts clean 32-hex', () {
      final key = parseRecoveryKey('000102030405060708090a0b0c0d0e0f');
      expect(key, hasLength(16));
      expect(key[0], 0);
      expect(key[15], 0x0f);
    });

    test('accepts uppercase, spaces, dashes', () {
      final key =
          parseRecoveryKey('0001-0203 0405-0607 0809-0A0B 0C0D-0E0F');
      expect(hex.encode(key), '000102030405060708090a0b0c0d0e0f');
    });

    test('rejects wrong length', () {
      expect(
        () => parseRecoveryKey('00010203'),
        throwsFormatException,
      );
    });

    test('rejects non-hex characters', () {
      expect(
        () => parseRecoveryKey('zz0102030405060708090a0b0c0d0e0f'),
        throwsFormatException,
      );
    });
  });

  group('buildRecoveryRequest', () {
    const key = '000102030405060708090a0b0c0d0e0f';
    final challenge = hex.decode('0001020304050607');

    test('has the v2 header and the wrapped password after the proof', () {
      final req = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: challenge,
        newPassword: 'hunter2hunter2',
      );
      expect(req[0], 0x02);
      expect(req[1], 14);
      expect(req, hasLength(10 + 14));
    });

    test('the password is never on the wire in the clear', () {
      // The whole reason this format exists: the Bluetooth link is open
      // and this carries the next whole-home password.
      const password = 'correcthorse';
      final req = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: challenge,
        newPassword: password,
      );
      final onWire = req.sublist(10);
      expect(onWire, isNot(utf8.encode(password)));
    });

    test('the same password under a different challenge looks different', () {
      // Otherwise a recorded exchange would leak by comparison.
      final a = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: challenge,
        newPassword: 'correcthorse',
      );
      final b = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: hex.decode('0706050403020100'),
        newPassword: 'correcthorse',
      );
      expect(a.sublist(10), isNot(b.sublist(10)));
    });

    test('the proof covers the wrapped password, not just the challenge', () {
      // If it didn't, a recorded request could be replayed with someone
      // else's password grafted on.
      final a = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: challenge,
        newPassword: 'passwordone',
      );
      final b = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: challenge,
        newPassword: 'passwordtwo',
      );
      expect(a.sublist(2, 10), isNot(b.sublist(2, 10)));
    });

    test('is key-sensitive', () {
      final a = buildRecoveryRequest(
        recoveryKeyHex: key,
        challenge: challenge,
        newPassword: 'hunter2hunter2',
      );
      final b = buildRecoveryRequest(
        recoveryKeyHex: 'f00102030405060708090a0b0c0d0e0f',
        challenge: challenge,
        newPassword: 'hunter2hunter2',
      );
      expect(a, isNot(b));
    });

    test('rejects a password the firmware would refuse', () {
      expect(
        () => buildRecoveryRequest(
          recoveryKeyHex: key,
          challenge: challenge,
          newPassword: 'short',
        ),
        throwsFormatException,
      );
    });
  });

  group('RecoveryVerdict', () {
    test('an accepted mesh recovery says the whole home', () {
      final v = RecoveryVerdict.fromJson(const {
        'v': 2,
        'ok': true,
        'scope': 'mesh',
      });
      expect(v.accepted, isTrue);
      expect(v.wholeHome, isTrue);
    });

    test('a rejection carries the wait the device dictated', () {
      // The app renders this countdown; it never computes a backoff.
      final v = RecoveryVerdict.fromJson(const {
        'v': 2,
        'ok': false,
        'wait': 8,
        'err': 'wrong recovery key',
      });
      expect(v.accepted, isFalse);
      expect(v.waitSeconds, 8);
      expect(v.error, 'wrong recovery key');
    });
  });
}
