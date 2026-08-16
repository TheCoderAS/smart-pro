import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';
import '../permissions/scan_permissions.dart';
import 'advert.dart';
import 'recovery_service.dart' show reactiveBleProvider, BlePermissionDenied;

final bleScannerProvider = Provider<BleScanner>(
  (ref) => BleScanner(ref.watch(reactiveBleProvider)),
);

/// Scans for Unisync masters and filters by manufacturer data (BLE
/// spec §Discovery) — never by name. Optionally restricts to a mesh
/// id, so the app ignores a neighbour's system.
class BleScanner {
  BleScanner(this._ble);

  final FlutterReactiveBle _ble;

  /// Emits the latest-seen beacon per device. Callers dedupe/track
  /// RSSI over time (see [RoamPolicy]). [meshId] null keeps every
  /// Unisync beacon (used at first pairing); a value keeps only that
  /// mesh (standalone pairs by device id, so pass null there).
  ///
  /// Throws [BlePermissionDenied] if the OS refuses Bluetooth
  /// permissions.
  Stream<MasterBeacon> scan({
    int? meshId,
    ScanMode mode = ScanMode.lowLatency,
  }) async* {
    if (!await ensureBlePermissions()) {
      throw const BlePermissionDenied();
    }
    // Scan everything (no service filter): the Unisync service UUID is
    // in the scan response, which some stacks omit from a service-
    // filtered scan, and we filter on manufacturer data anyway.
    // `mode` is lowLatency for a fast first connect, but the roam loop
    // passes `balanced` so continuous background scanning doesn't starve
    // the live connection.
    final stream = _ble.scanForDevices(
      withServices: const [],
      scanMode: mode,
    );
    await for (final d in stream) {
      final beacon = MasterBeacon.fromScan(
        deviceId: d.id,
        name: d.name,
        rssi: d.rssi,
        manufacturerData: d.manufacturerData,
      );
      if (beacon == null) continue;
      if (meshId != null && beacon.meshId != meshId) continue;
      yield beacon;
    }
  }

  /// Collects the strongest beacon per device over [window], filtered
  /// to [meshId] when given. Used to pick the nearest master to
  /// connect to.
  Future<List<MasterBeacon>> collect({
    int? meshId,
    Duration window = const Duration(seconds: 4),
    ScanMode mode = ScanMode.lowLatency,
  }) async {
    final best = <String, MasterBeacon>{};
    final sub = scan(meshId: meshId, mode: mode).listen((b) {
      final prev = best[b.deviceId];
      if (prev == null || b.rssi > prev.rssi) best[b.deviceId] = b;
    }, onError: (Object e) => log.w('scan error: $e'));
    await Future<void>.delayed(window);
    try {
      // Capped: the platform side can hang a scan-cancel right after an
      // unclean disconnect, and this await used to sit inside the scan
      // gate — one hang blocked every scan and reconnect after it.
      await sub.cancel().timeout(const Duration(seconds: 2));
    } on Object catch (e) {
      log.w('scan cancel did not complete: $e');
    }
    return best.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }
}
