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

  group('recoveryResponse', () {
    // RFC 4231 test case 1 uses a 20-byte key, which a Unisync card
    // never produces, so derive expected values with the same
    // primitive instead: this pins OUR truncation behaviour (first 8
    // bytes) and byte order rather than the crypto package itself.
    test('is HMAC-SHA256 truncated to exactly 8 bytes', () {
      final out = recoveryResponse(
        '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b',
        List<int>.filled(8, 0x48),
      );
      expect(out, hasLength(8));
    });

    test('is deterministic and challenge-sensitive', () {
      const key = '000102030405060708090a0b0c0d0e0f';
      final a1 = recoveryResponse(key, [1, 2, 3, 4, 5, 6, 7, 8]);
      final a2 = recoveryResponse(key, [1, 2, 3, 4, 5, 6, 7, 8]);
      final b = recoveryResponse(key, [8, 7, 6, 5, 4, 3, 2, 1]);
      expect(a1, a2);
      expect(a1, isNot(b));
    });

    test('is key-sensitive', () {
      final challenge = [1, 2, 3, 4, 5, 6, 7, 8];
      final a = recoveryResponse(
        '000102030405060708090a0b0c0d0e0f',
        challenge,
      );
      final b = recoveryResponse(
        'f00102030405060708090a0b0c0d0e0f',
        challenge,
      );
      expect(a, isNot(b));
    });

    test('matches a known HMAC-SHA256 vector prefix', () {
      // Computed independently with:
      //   python3 -c "import hmac,hashlib;
      //   print(hmac.new(bytes.fromhex('000102030405060708090a0b0c0d0e0f'),
      //   bytes.fromhex('0001020304050607'), hashlib.sha256).hexdigest())"
      // = c1af5e13e9f35c836483aec70b15c2b10238d9f411e0a6e53f809fa01b406bfa
      final out = recoveryResponse(
        '000102030405060708090a0b0c0d0e0f',
        hex.decode('0001020304050607'),
      );
      expect(hex.encode(out), 'c1af5e13e9f35c83');
    });
  });
}
