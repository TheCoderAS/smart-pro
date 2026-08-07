import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../api/endpoints.dart';
import '../logging/log.dart';

final wifiServiceProvider = Provider<WifiService>((ref) => WifiService());

/// Platform Wi-Fi operations: join the master's AP, read the current
/// SSID, and (Android only) scan for Unisync networks during
/// onboarding.
///
/// Roaming caveat (API §3): in a mesh every master serves the same
/// SSID at the same IP, so "connected to the right SSID" is the
/// strongest signal available — the app cannot and must not care
/// which physical master answers.
class WifiService {
  /// Joins [ssid] with [password]. Resolves once the platform reports
  /// the connection attempt finished; the caller should then verify
  /// reachability with GET /api/info rather than trusting the OS.
  ///
  /// On iOS this triggers the NEHotspotConfiguration system prompt.
  /// On Android it uses WifiNetworkSuggestion under the hood.
  Future<bool> join(String ssid, String password) async {
    log.i('joining Wi-Fi "$ssid"');
    // security must be WPA (plugin default is NONE) and joinOnce
    // false so the configuration persists beyond one association.
    final ok = await WiFiForIoTPlugin.connect(
      ssid,
      password: password,
      security: NetworkSecurity.WPA,
      joinOnce: false,
    );
    if (ok) {
      // Route traffic to the AP even though it has no internet.
      await WiFiForIoTPlugin.forceWifiUsage(true);
    }
    return ok;
  }

  /// The SSID the phone is currently associated with, or null when
  /// not on Wi-Fi / not determinable (iOS restricts SSID access —
  /// treat null as "unknown", not "wrong network").
  Future<String?> currentSsid() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') {
        return null;
      }
      return ssid;
    } on Exception catch (e) {
      log.w('currentSsid failed: $e');
      return null;
    }
  }

  /// Quick reachability probe — can we open a TCP socket to the
  /// master? Cheaper and more truthful than trusting SSID strings.
  Future<bool> masterReachable({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final socket = await Socket.connect(Api.host, 80, timeout: timeout);
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// Android-only scan for access points. Unisync masters are
  /// filtered by [ssidPrefix] when given. Throws [UnsupportedError]
  /// on iOS — the platform provides no third-party Wi-Fi scanning;
  /// onboarding falls back to manual SSID entry there.
  Future<List<String>> scanSsids({String? ssidPrefix}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Wi-Fi scanning is Android-only');
    }
    final can = await WiFiScan.instance.canStartScan();
    if (can != CanStartScan.yes) {
      log.w('cannot start Wi-Fi scan: $can');
      return const [];
    }
    await WiFiScan.instance.startScan();
    final results = await WiFiScan.instance.getScannedResults();
    final ssids = results
        .map((r) => r.ssid)
        .where((s) => s.isNotEmpty)
        .where((s) => ssidPrefix == null || s.startsWith(ssidPrefix))
        .toSet()
        .toList()
      ..sort();
    return ssids;
  }
}
