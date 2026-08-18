import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logging/log.dart';
import '../platform/radios.dart';
import '../transport/stay_alive.dart';
import '../transport/transport_coordinator.dart';

/// Runs the app-load readiness pass: every runtime permission the app
/// needs, requested upfront, and the system prompts to turn Wi-Fi and
/// Bluetooth on when they are off.
///
/// Before this existed, permissions were requested lazily — Bluetooth
/// permission at the first scan, notifications never — so a user could
/// sit on "Reconnecting…" for a permission dialog that never came, and
/// nothing ever told them a radio was simply switched off.
///
/// Wrapped around the app (MaterialApp.builder), not run from main():
/// prompts need a visible Activity, and on Android this isolate also runs
/// headless in the warm background engine where there is none. A rendered
/// frame is the proof the Activity exists.
///
/// Runs on the first frame and again whenever the app comes back to the
/// foreground, throttled so the resumes caused by our own dialogs (a
/// permission prompt pauses the app too) don't loop the prompts.
class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate>
    with WidgetsBindingObserver {
  /// Re-prompting radios sooner than this after the last pass reads as
  /// nagging (and would loop: dismissing our own prompt resumes the app).
  static const rerunAfter = Duration(minutes: 2);

  DateTime? _lastRun;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  Future<void> _run() async {
    if (_running) return;
    final last = _lastRun;
    if (last != null && DateTime.now().difference(last) < rerunAfter) return;
    _running = true;
    _lastRun = DateTime.now();
    try {
      await _requestPermissions();
      await _promptRadios();
      // Doze is part of readiness: an un-exempted process gets its network
      // suspended in the background, and every request to the master times
      // out until the app is foregrounded again. Prompts only while the
      // exemption is actually missing.
      await ref.read(stayAliveProvider).ensureBatteryExemption();
    } on Object catch (e) {
      log.w('startup readiness pass failed: $e');
    } finally {
      _running = false;
    }
    // Radios or permissions may have just appeared — let the transport
    // take advantage without waiting for the next natural reconcile.
    if (mounted) {
      unawaited(ref.read(transportCoordinatorProvider).reconcile());
    }
  }

  /// Everything the app's core loop needs, in one pass. Camera is the
  /// deliberate exception — it is only for the QR alternative during
  /// setup, and the scanner screen requests it at the moment of use.
  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      await Permission.bluetooth.request();
      return;
    }
    if (!Platform.isAndroid) return;
    // Already-granted entries resolve without a dialog; entries not
    // applicable to this OS version (location is declared maxSdk 30,
    // notification below 13 is implicit) resolve silently too.
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.location,
      Permission.notification,
    ].request();
    final denied = [
      for (final e in results.entries)
        if (!e.value.isGranted && !e.value.isLimited) e.key,
    ];
    if (denied.isNotEmpty) log.w('startup permissions denied: $denied');
  }

  Future<void> _promptRadios() async {
    if (!Platform.isAndroid) return;
    final radios = ref.read(radiosProvider);
    // Bluetooth first: it is a plain dialog, and the Wi-Fi settings
    // panel that may follow slides up over it rather than burying it.
    if (!await radios.isBluetoothOn()) {
      log.i('bluetooth is off — asking to enable');
      await radios.requestEnableBluetooth();
    }
    if (!await radios.isWifiOn()) {
      log.i('wifi is off — asking to enable');
      await radios.requestEnableWifi();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
