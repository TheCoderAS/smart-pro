import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/features/onboarding/presentation/add_master_screen.dart';

void main() {
  test('parses the full unisync scheme', () {
    final qr = parseCardQr('unisync://c5f77720?s=Unisync-C5F7&p=a1b2c3d4e5f6');
    expect(qr, isNotNull);
    expect(qr!.uid, 'C5F77720');
    expect(qr.ssid, 'Unisync-C5F7');
    expect(qr.password, 'a1b2c3d4e5f6');
  });

  test('parses partial payloads', () {
    final qr = parseCardQr('unisync://c5f77720');
    expect(qr, isNotNull);
    expect(qr!.uid, 'C5F77720');
    expect(qr.ssid, isNull);
  });

  test('rejects foreign QR codes', () {
    expect(parseCardQr('https://example.com'), isNull);
    expect(parseCardQr('WIFI:S:Home;T:WPA;P:pw;;'), isNull);
    expect(parseCardQr('hello world'), isNull);
  });
}
