import 'dart:typed_data';

/// Parsed Unisync advertising manufacturer data (BLE spec §Discovery).
///
/// 6 bytes:
///   [0..1] company id, `FF FF` little-endian
///   [2]    format version, currently 0x01
///   [3..4] mesh id, big-endian (0x0000 = standalone)
///   [5]    flags
class MasterAdvert {
  const MasterAdvert({
    required this.meshId,
    required this.inMesh,
    required this.provisioned,
    required this.clientConnected,
  });

  /// 16-bit mesh id, identical across a mesh, stable across renames /
  /// password changes / reboots. 0 = standalone.
  final int meshId;

  /// Flag bit 0.
  final bool inMesh;

  /// Flag bit 1 — provisioned with product keys.
  final bool provisioned;

  /// Flag bit 2 — a client is already connected (prefer masters where
  /// this is false; a busy one may refuse a second connection).
  final bool clientConnected;

  bool get isStandalone => meshId == 0;

  @override
  String toString() =>
      'MasterAdvert(mesh=0x${meshId.toRadixString(16).padLeft(4, '0')}, '
      'inMesh=$inMesh, provisioned=$provisioned, busy=$clientConnected)';
}

const _companyIdLo = 0xFF;
const _companyIdHi = 0xFF;
const _formatV1 = 0x01;

/// Parses Unisync manufacturer data. Returns null for anything that
/// isn't a v1 Unisync beacon (wrong company id or format), so foreign
/// advertisements are ignored. Filtering happens here, never by name.
MasterAdvert? parseManufacturerData(List<int> data) {
  if (data.length < 6) return null;
  if (data[0] != _companyIdLo || data[1] != _companyIdHi) return null;
  if (data[2] != _formatV1) return null;

  final meshId = (data[3] << 8) | data[4]; // big-endian
  final flags = data[5];
  return MasterAdvert(
    meshId: meshId,
    inMesh: flags & 0x01 != 0,
    provisioned: flags & 0x02 != 0,
    clientConnected: flags & 0x04 != 0,
  );
}

/// A discovered master: its advert plus the transport-level identity
/// and signal strength from the scan result.
class MasterBeacon {
  const MasterBeacon({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.advert,
  });

  /// Platform BLE device id (address on Android, UUID on iOS).
  final String deviceId;

  /// Advertised name, `U{UID}` — used for display, never for filtering.
  final String name;

  /// Signal strength in dBm (higher/less-negative is stronger).
  final int rssi;

  final MasterAdvert advert;

  int get meshId => advert.meshId;

  /// Builds a beacon from a scan result, or null if the manufacturer
  /// data isn't a Unisync v1 beacon.
  static MasterBeacon? fromScan({
    required String deviceId,
    required String name,
    required int rssi,
    required Uint8List manufacturerData,
  }) {
    final advert = parseManufacturerData(manufacturerData);
    if (advert == null) return null;
    return MasterBeacon(
      deviceId: deviceId,
      name: name,
      rssi: rssi,
      advert: advert,
    );
  }
}
