import 'advert.dart';

/// One RSSI observation of a beacon at a moment.
class RssiSample {
  const RssiSample(this.rssi, this.atMillis);
  final int rssi;
  final int atMillis;
}

/// Pure roaming decision logic (BLE spec §Roaming). The radio calls
/// (scanning, connecting) are injected by the controller; this class
/// only decides *whether* and *where* to hop, so it is fully
/// unit-testable without hardware.
///
/// Rule: hop to another master of the same mesh only when it is
/// **≥ [marginDb] stronger than the current master, sustained for
/// ~[dwell]**. Prefer masters whose "client connected" flag is clear.
/// The hysteresis is mandatory — without it the app oscillates between
/// two masters at the midpoint of a house.
class RoamPolicy {
  RoamPolicy({
    this.marginDb = 10,
    this.dwell = const Duration(seconds: 5),
  });

  final int marginDb;
  final Duration dwell;

  /// Per-device rolling RSSI history, newest last.
  final Map<String, List<RssiSample>> _history = {};

  /// Records a beacon observation.
  void observe(MasterBeacon beacon, int nowMillis) {
    final list = _history.putIfAbsent(beacon.deviceId, () => []);
    list.add(RssiSample(beacon.rssi, nowMillis));
    // Keep only the dwell window plus a little slack.
    final cutoff = nowMillis - dwell.inMilliseconds - 1000;
    list.removeWhere((s) => s.atMillis < cutoff);
  }

  /// Smoothed (mean) RSSI over the dwell window for a device, or null
  /// if there isn't a full window of data yet.
  double? _windowedRssi(String deviceId, int nowMillis) {
    final list = _history[deviceId];
    if (list == null || list.isEmpty) return null;
    final windowStart = nowMillis - dwell.inMilliseconds;
    final inWindow = list.where((s) => s.atMillis >= windowStart).toList();
    if (inWindow.isEmpty) return null;
    // Require the window to actually span ~dwell before trusting it,
    // so a brief spike can't trigger a hop.
    final span = inWindow.last.atMillis - inWindow.first.atMillis;
    if (span < dwell.inMilliseconds * 0.8) return null;
    final sum = inWindow.fold<int>(0, (a, s) => a + s.rssi);
    return sum / inWindow.length;
  }

  /// Returns the device id to hop to, or null to stay put.
  ///
  /// [connectedDeviceId] is the current master; [candidates] are the
  /// beacons currently visible (same mesh — the caller filters by
  /// mesh id before calling). Standalone masters never roam.
  String? chooseHop({
    required String? connectedDeviceId,
    required List<MasterBeacon> candidates,
    required int nowMillis,
  }) {
    if (connectedDeviceId == null) return null;

    final currentRssi = _windowedRssi(connectedDeviceId, nowMillis);
    if (currentRssi == null) return null; // not enough data; hold

    MasterBeacon? best;
    double bestRssi = currentRssi + marginDb; // must beat this
    for (final c in candidates) {
      if (c.deviceId == connectedDeviceId) continue;
      if (c.advert.isStandalone) continue; // standalone never roams
      final r = _windowedRssi(c.deviceId, nowMillis);
      if (r == null) continue;
      final beatsMargin = r >= currentRssi + marginDb;
      if (!beatsMargin) continue;
      // Among qualifying candidates, prefer a stronger one, and break
      // ties toward an unoccupied master (flag bit 2 clear).
      if (best == null ||
          r > bestRssi ||
          (r == bestRssi &&
              !c.advert.clientConnected &&
              best.advert.clientConnected)) {
        best = c;
        bestRssi = r;
      }
    }
    return best?.deviceId;
  }

  /// Drops history for devices no longer seen (called on scan cleanup).
  void forget(String deviceId) => _history.remove(deviceId);

  void clear() => _history.clear();
}
