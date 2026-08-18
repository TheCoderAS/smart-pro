import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/log.dart';
import '../storage/master_registry.dart';
import 'link_state.dart';

/// Keeps the app's process — and so the Bluetooth link — alive between
/// uses, on Android.
///
/// The snapshot cache makes *opening* the app instant. This is what makes
/// the first *tap* instant: without it, a switch press after the app has
/// been away means a scan and a connect before anything happens. For
/// lighting someone reaches for in the dark, that is the difference that
/// matters.
///
/// Android only, and not negotiable: iOS suspends apps and terminates them
/// when swiped from the app switcher. There is no equivalent, so on iOS
/// every call here is a no-op and the app relies on the cache alone.
///
/// Even on Android this is best-effort. Xiaomi, Oppo, Vivo and Huawei kill
/// foreground services unless the user exempts the app in their own battery
/// settings — [openBatterySettings] is the only lever there is.
final stayAliveProvider = Provider<StayAlive>((ref) {
  final stayAlive = StayAlive(ref);
  // Wired here rather than in the dashboard's build. With the engine kept
  // warm there may be no widget rebuilding to hang this off — and a
  // notification still reading "Connected" hours after the link died
  // would be worse than no notification at all.
  ref.listen(linkStateProvider, (_, _) => stayAlive.refresh());
  return stayAlive;
});

class StayAlive {
  StayAlive(this._ref);

  final Ref _ref;

  static const _channel = MethodChannel('in.unisync.unisync/wifi');

  /// Persisted so the choice survives a reinstall of the habit, not just
  /// of the app: someone who turned this on wants it on.
  static const prefKey = 'stayAlive.enabled';

  bool get _supported => Platform.isAndroid;

  /// On unless the user has turned it off.
  ///
  /// The default matters: this is what "always running" means in practice,
  /// and someone reaching for a light at night has not opted into anything
  /// beforehand. BootReceiver defaults the same way — the two have to
  /// agree or the state depends on which ran first.
  Future<bool> isEnabled() async {
    if (!_supported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKey) ?? true;
  }

  Future<void> setEnabled(bool on) async {
    if (!_supported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, on);
    if (on) {
      await _start();
    } else {
      await _stop();
    }
  }

  /// Brings the service up unless the user has turned it off. Called once
  /// the app has a session worth holding open.
  ///
  /// Also asks for the battery exemption the first time, because a
  /// foreground service alone does not stop Doze throttling the process —
  /// and a throttled process is exactly the delay this exists to remove.
  Future<void> resume() async {
    if (!await isEnabled()) return;
    await _start();
    await _requestExemptionOnce();
  }

  static const _askedKey = 'stayAlive.batteryAsked';

  Future<void> _requestExemptionOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) ?? false) return;
    await prefs.setBool(_askedKey, true);
    await ensureBatteryExemption();
  }

  /// Asks the system for the Doze exemption whenever it is not already
  /// granted — no once-ever guard. Bench evidence for why: with the app
  /// backgrounded, an un-exempted process had its network suspended and
  /// every request to the master timed out for a minute at a stretch,
  /// healing the instant the app was foregrounded. The dialog only ever
  /// appears while the exemption is missing, so once granted this is a
  /// silent no-op forever.
  Future<void> ensureBatteryExemption() async {
    if (!_supported) return;
    if (!await isEnabled()) return;
    if (await isBatteryExempt()) return;
    log.i('not battery-exempt — asking (background suspends our network)');
    try {
      await _channel.invokeMethod<bool>('requestBatteryExemption');
    } on PlatformException catch (e) {
      log.w('battery exemption request refused: ${e.code}');
    }
  }

  /// Whether the system has already agreed not to doze us.
  Future<bool> isBatteryExempt() async {
    if (!_supported) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('isBatteryExempt');
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// The notification is the only part of this the user ever sees, so it
  /// says which master and whether it is actually reachable — a status
  /// line, not "app is running".
  String _statusText() {
    final link = _ref.read(linkStateProvider);
    // From the saved vault, not the live stream: the notification has to
    // say something sensible before anything has connected.
    final masters = _ref.read(masterRegistryProvider).value ?? const [];
    final name = masters.isEmpty ? 'your switches' : masters.first.name;
    return switch (link) {
      LinkState.connectedBle => 'Connected to $name over Bluetooth',
      LinkState.connectedWifi => 'Connected to $name over Wi-Fi',
      LinkState.reconnecting => 'Reconnecting to $name…',
      LinkState.outOfRange => '$name is out of range',
    };
  }

  Future<void> _start() async {
    try {
      await _channel.invokeMethod<bool>(
        'startStayAlive',
        {'text': _statusText()},
      );
    } on PlatformException catch (e) {
      log.w('stay-alive service refused: ${e.code}');
    }
  }

  Future<void> _stop() async {
    try {
      await _channel.invokeMethod<bool>('stopStayAlive');
    } on PlatformException {
      // best effort
    }
  }

  /// Refreshes the notification text. Cheap; safe to call whenever the
  /// link state changes.
  Future<void> refresh() async {
    if (await isEnabled()) await _start();
  }

  /// Opens the OS battery screen so the user can exempt the app. The only
  /// remedy for vendors that kill foreground services anyway.
  Future<bool> openBatterySettings() async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openBatterySettings');
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }
}
