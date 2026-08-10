import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/features/firmware/domain/firmware_models.dart';

void main() {
  test('StoredImage accepts the HTTP `version` key', () {
    final img = StoredImage.fromJson({'type': 1, 'version': '1.2.6', 'size': 9456});
    expect(img.version, '1.2.6');
    expect(img.type, 1);
  });

  test('StoredImage accepts the BLE `ver` key', () {
    final img = StoredImage.fromJson({'type': 1, 'ver': '1.2.6', 'size': 9456});
    expect(img.version, '1.2.6');
  });

  test('FwStatus parses the BLE fwlist reply', () {
    final s = FwStatus.fromJson({
      'fs': true,
      'master': '11.16.0',
      'images': [
        {'type': 1, 'ver': '1.2.6', 'size': 9456},
      ],
    });
    expect(s.master, '11.16.0');
    expect(s.images, hasLength(1));
    expect(s.images.single.version, '1.2.6');
  });

  test('FirmwareManifest changelog defaults empty and parses when present', () {
    expect(
      FirmwareManifest.fromJson({'type': 1, 'version': '1.2.6'}).changelog,
      '',
    );
    expect(
      FirmwareManifest.fromJson(
        {'type': 1, 'version': '1.2.6', 'changelog': 'Fixes stuck relay'},
      ).changelog,
      'Fixes stuck relay',
    );
  });
}
