import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../logging/log.dart';

/// Requests the runtime permissions a BLE scan needs and reports whether
/// scanning can proceed.
///
/// The app declares the permissions in the manifest, but Android 12+
/// makes BLUETOOTH_SCAN / BLUETOOTH_CONNECT *runtime* permissions —
/// flutter_reactive_ble does not prompt for them itself, and without
/// them its scan falls back to the legacy location check and fails with
/// "Location Permission missing". Older Android (< 12) needs fine
/// location instead. iOS gates on the Bluetooth permission.
///
/// Returns true when the scan-relevant permission is granted.
Future<bool> ensureBlePermissions() async {
  if (Platform.isIOS) {
    final status = await Permission.bluetooth.request();
    return status.isGranted || status.isLimited;
  }
  if (!Platform.isAndroid) return true;

  // Android 12+ path: BLUETOOTH_SCAN is what actually matters (we declare
  // it neverForLocation, so no location is needed). Android 11 and below:
  // FINE_LOCATION. Request the whole set; the ones not applicable to this
  // OS version resolve to denied/restricted harmlessly.
  final results = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();

  final scanOk = results[Permission.bluetoothScan]?.isGranted ?? false;
  final locationOk = results[Permission.location]?.isGranted ?? false;
  final granted = scanOk || locationOk;
  if (!granted) {
    log.w('BLE permissions denied: $results');
  }
  return granted;
}

/// Requests the runtime permissions an Android Wi-Fi scan needs.
///
/// Android 13+ uses NEARBY_WIFI_DEVICES (declared neverForLocation);
/// earlier versions require fine location for a scan to return results.
/// iOS has no third-party Wi-Fi scanning, so this is Android-only.
Future<bool> ensureWifiScanPermissions() async {
  if (!Platform.isAndroid) return false;

  final results = await [
    Permission.nearbyWifiDevices,
    Permission.location,
  ].request();

  final nearbyOk = results[Permission.nearbyWifiDevices]?.isGranted ?? false;
  final locationOk = results[Permission.location]?.isGranted ?? false;
  final granted = nearbyOk || locationOk;
  if (!granted) {
    log.w('Wi-Fi scan permissions denied: $results');
  }
  return granted;
}
