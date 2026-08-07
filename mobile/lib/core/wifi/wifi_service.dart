import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../api/endpoints.dart';
import '../logging/log.dart';

final wifiServiceProvider = Provider<WifiService>((ref) => WifiService());

/// Platform Wi-Fi operations: join the master's AP, read the current
/// SSID, and (Android only) scan for Unisync networks during
/// onboarding.
///
/// Join/read run over a hand-rolled platform channel
/// (`in.unisync.unisync/wifi`, implemented in MainActivity.kt and
/// AppDelegate.swift) because wifi_iot's Android build is incompatible
/// with modern AGP and no maintained plugin covers app-scoped AP
/// joining. On Android 10+ the join uses WifiNetworkSpecifier and the
/// process is bound to the resulting network, so all app sockets route
/// to the internet-less AP; iOS uses NEHotspotConfiguration.
///
/// Roaming caveat (API §3): in a mesh every master serves the same
/// SSID at the same IP, so "connected to the right SSID" is the
/// strongest signal available — the app cannot and must not care
/// which physical master answers.
class WifiService {
  static const _channel = MethodChannel('in.unisync.unisync/wifi');

  /// Joins [ssid] with [password]. Resolves once the platform reports
  /// the attempt finished; callers should then verify reachability
  /// with GET /api/info rather than trusting the OS. On iOS this
  /// triggers the NEHotspotConfiguration system prompt.
  Future<bool> join(String ssid, String password) async {
    log.i('joining Wi-Fi "$ssid"');
    try {
      final ok = await _channel.invokeMethod<bool>('join', {
        'ssid': ssid,
        'password': password,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      log.w('wifi join failed: ${e.code}');
      return false;
    }
  }

  /// The SSID the phone is currently associated with, or null when
  /// not determinable. Both platforms restrict SSID reads without
  /// certain permissions/entitlements — treat null as "unknown",
  /// never "wrong network".
  Future<String?> currentSsid() async {
    try {
      final ssid = await _channel.invokeMethod<String>('currentSsid');
      if (ssid == null || ssid.isEmpty) return null;
      return ssid;
    } on PlatformException catch (e) {
      log.w('currentSsid failed: ${e.code}');
      return null;
    }
  }

  /// Undoes the app-scoped network binding (Android; iOS no-op).
  Future<void> release() async {
    try {
      await _channel.invokeMethod<bool>('release');
    } on PlatformException {
      // best-effort
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
