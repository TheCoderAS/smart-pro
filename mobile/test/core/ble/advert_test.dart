import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/ble/advert.dart';

Uint8List mfr({
  int meshHi = 0,
  int meshLo = 0,
  int flags = 0,
  int company0 = 0xFF,
  int company1 = 0xFF,
  int format = 0x01,
}) {
  return Uint8List.fromList(
    [company0, company1, format, meshHi, meshLo, flags],
  );
}

void main() {
  group('parseManufacturerData', () {
    test('reads mesh id big-endian', () {
      final a = parseManufacturerData(mfr(meshHi: 0x12, meshLo: 0x34));
      expect(a, isNotNull);
      expect(a!.meshId, 0x1234);
      expect(a.isStandalone, isFalse);
    });

    test('0x0000 is standalone', () {
      final a = parseManufacturerData(mfr())!;
      expect(a.meshId, 0);
      expect(a.isStandalone, isTrue);
    });

    test('decodes each flag bit', () {
      final a = parseManufacturerData(mfr(flags: 0x07))!;
      expect(a.inMesh, isTrue);
      expect(a.provisioned, isTrue);
      expect(a.clientConnected, isTrue);

      final b = parseManufacturerData(mfr(flags: 0x02))!;
      expect(b.inMesh, isFalse);
      expect(b.provisioned, isTrue);
      expect(b.clientConnected, isFalse);
    });

    test('rejects wrong company id', () {
      expect(parseManufacturerData(mfr(company0: 0x4C, company1: 0x00)),
          isNull);
    });

    test('rejects wrong format version', () {
      expect(parseManufacturerData(mfr(format: 0x02)), isNull);
    });

    test('rejects short data', () {
      expect(parseManufacturerData([0xFF, 0xFF, 0x01]), isNull);
    });
  });

  group('MasterBeacon.fromScan', () {
    test('builds from a valid Unisync beacon', () {
      final b = MasterBeacon.fromScan(
        deviceId: 'AA:BB',
        name: 'UC5F77720',
        rssi: -55,
        manufacturerData: mfr(meshHi: 0xAB, meshLo: 0xCD, flags: 0x01),
      );
      expect(b, isNotNull);
      expect(b!.meshId, 0xABCD);
      expect(b.name, 'UC5F77720');
      expect(b.rssi, -55);
    });

    test('returns null for a foreign beacon', () {
      final b = MasterBeacon.fromScan(
        deviceId: 'AA:BB',
        name: 'SomeOtherThing',
        rssi: -55,
        manufacturerData: Uint8List.fromList([0x4C, 0x00, 0x02, 0, 0, 0]),
      );
      expect(b, isNull);
    });
  });
}
