import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';
import '../permissions/scan_permissions.dart';
import 'advert.dart';
import 'recovery_service.dart' show reactiveBleProvider, BlePermissionDenied;

final bleScannerProvider = Provider<BleScanner>(BleScanner.new);

/// Scans for Unisync masters and filters by manufacturer data (BLE
/// spec §Discovery) — never by name. Optionally restricts to a mesh
/// id, so the app ignores a neighbour's system.
class BleScanner {
  BleScanner(this._ref);

  final Ref _ref;

  /// Read per use, never held. A stack reset replaces the instance, and
  /// a scanner clutching the old one would go on talking to the plugin
  /// it had just torn down.
  FlutterReactiveBle get _ble => _ref.read(reactiveBleProvider);

  /// How long a hung scan-stop is given to clear on its own before the
  /// stack is reset. Short on purpose: the old build waited 8 s and it
  /// never once helped — see [_settleHungCancel].
  static const hungCancelGrace = Duration(seconds: 2);

  /// How long a scan-stop is given before it counts as hung.
  static const cancelGrace = Duration(seconds: 2);

  /// Cap on the plugin teardown itself.
  static const resetCap = Duration(seconds: 5);

  /// Consecutive scans that hear nothing before the stack is reset on
  /// suspicion. Somebody away from home hears nothing too, so this is
  /// rate-limited by [resetCooldown] rather than trusted outright.
  static const emptyScansBeforeReset = 3;
  static const resetCooldown = Duration(minutes: 2);

  /// The longest [collect] can legitimately take for [window]. Callers
  /// derive their own timeouts from this instead of guessing: a cap
  /// below what collect can spend throws away good scans, and the
  /// previous guess sat exactly on the boundary.
  static Duration budget(Duration window) =>
      window + hungCancelGrace + resetCap + cancelGrace;

  /// A scan-stop the platform never acknowledged. Android hangs the
  /// cancel after a supervision-timeout disconnect; scanning on top of
  /// that zombie is how every following scan came back empty.
  Future<void>? _hungCancel;

  int _emptyScans = 0;
  DateTime? _lastReset;

  /// Emits the latest-seen beacon per device. [meshId] null keeps every
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
  ///
  /// Always returns what it actually heard. It owns the one deadline
  /// that matters; a caller wrapping it in a second, shorter timeout is
  /// how a perfectly good scan got discarded before the ranking ran.
  Future<List<MasterBeacon>> collect({
    int? meshId,
    Duration window = const Duration(seconds: 4),
    ScanMode mode = ScanMode.lowLatency,
  }) async {
    await _settleHungCancel();

    final best = <String, MasterBeacon>{};
    final sub = scan(meshId: meshId, mode: mode).listen((b) {
      final prev = best[b.deviceId];
      if (prev == null || b.rssi > prev.rssi) best[b.deviceId] = b;
    }, onError: (Object e) => log.w('scan error: $e'));
    await Future<void>.delayed(window);
    final cancelDone = sub.cancel();
    try {
      // Capped: the platform side can hang a scan-cancel right after an
      // unclean disconnect, and this await used to sit inside the scan
      // gate — one hang blocked every scan and reconnect after it.
      await cancelDone.timeout(cancelGrace);
      _hungCancel = null;
    } on Object catch (e) {
      log.w('scan cancel did not complete: $e');
      _hungCancel = cancelDone;
      // Log the eventual outcome so a wedged radio is visible in the log.
      unawaited(cancelDone.then(
        (_) {
          if (identical(_hungCancel, cancelDone)) _hungCancel = null;
          log.i('hung scan cancel completed late');
        },
        onError: (Object e) => log.w('hung scan cancel failed: $e'),
      ));
    }

    final heard = best.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    // The full picture, every scan: anyone reading the log can say who
    // was in the air and how loud.
    final described = heard
        .map((b) =>
            '${b.name}(mesh 0x${b.meshId.toRadixString(16)}, ${b.rssi}dBm'
            '${b.advert.clientConnected ? ', busy' : ''})')
        .join(', ');
    final filter =
        meshId != null ? ', mesh 0x${meshId.toRadixString(16)}' : '';
    log.d('ble scan (${window.inSeconds}s$filter): heard ${heard.length}'
        '${heard.isEmpty ? '' : ' → $described'}');

    // Hearing nothing over and over is the shape of a wedged scanner:
    // once the platform stops delivering results it never starts again
    // on its own, and a bench run spent an hour on 119 identical empty
    // cycles. It is also the shape of being away from home, which is
    // why this is rate-limited rather than trusted.
    if (heard.isEmpty) {
      _emptyScans++;
      if (_emptyScans >= emptyScansBeforeReset && _resetCooledDown) {
        _emptyScans = 0;
        await _resetStack('$emptyScansBeforeReset scans running heard nothing');
      }
    } else {
      _emptyScans = 0;
    }
    return heard;
  }

  bool get _resetCooledDown {
    final last = _lastReset;
    return last == null || DateTime.now().difference(last) >= resetCooldown;
  }

  /// Waits briefly for a hung scan-stop, and resets the stack if it does
  /// not clear.
  ///
  /// The previous build waited 8 s and then scanned **anyway**. That is
  /// what turned a transient platform hiccup into a permanent one: the
  /// plugin runs one scan session, so a scan started while the last one
  /// is still stopping delivers nothing at all — and leaves its own
  /// cancel hanging, arming the next cycle identically. The loop cannot
  /// exit. Resetting is the only way out, and it costs a few seconds
  /// against an outage that otherwise lasts until the app is killed.
  Future<void> _settleHungCancel() async {
    final stuck = _hungCancel;
    if (stuck == null) return;
    log.w('previous scan is still stopping — waiting for the radio');
    try {
      await stuck.timeout(hungCancelGrace);
      _hungCancel = null;
      log.i('previous scan finally stopped');
    } on Object {
      await _resetStack('a scan-stop never completed');
    }
  }

  /// Tears the Bluetooth plugin down and drops the instance, so the next
  /// scan builds a fresh one.
  ///
  /// This works because it does not go the way that is jammed. The hang
  /// is in the scan stream's own cancel (the plugin's EventChannel
  /// `onCancel`); `deinitialize` is a separate direct MethodChannel call
  /// that disposes the native scan subscription and returns — reaching
  /// the stuck machinery by a route that is not stuck.
  Future<void> _resetStack(String why) async {
    _lastReset = DateTime.now();
    log.w('ble: $why — resetting the Bluetooth stack');
    try {
      await _ble.deinitialize().timeout(resetCap);
    } on Object catch (e) {
      log.w('ble deinitialize did not complete: $e');
    }
    _hungCancel = null;
    _emptyScans = 0;
    _ref.invalidate(reactiveBleProvider);
    log.i('ble stack reset — the next scan uses a fresh client');
  }
}
