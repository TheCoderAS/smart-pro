import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/router.dart';
import '../../../core/logging/log.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../auth/application/session.dart';

/// The setup screen: join the switch's Wi-Fi, then land in the normal
/// session flow (login or commissioning). Rendered as the gate root when
/// nothing is paired and no master answers (NeedsSetup) — a fresh
/// install's second screen — and reachable as a route as well. Entry
/// paths:
///  - the user already joined the network from the phone's settings
///    (the welcome screen's instructions) → "check again"
///  - QR on the device card (assumed scheme
///    `unisync://<uid>?s=<ssid>&p=<pw>`; PLAN.md open question #3)
///  - Android: pick the SSID from a scan
///  - both platforms: type the SSID + password from the card
class AddMasterScreen extends ConsumerStatefulWidget {
  const AddMasterScreen({super.key});

  @override
  ConsumerState<AddMasterScreen> createState() => _AddMasterScreenState();
}

class _AddMasterScreenState extends ConsumerState<AddMasterScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _scanningQr = false;
  String? _error;
  List<String> _nearbySsids = const [];

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One device per app. Adding while one is set up is not allowed --
    // the current one has to be removed first, deliberately, in Settings.
    final masters = ref.watch(masterRegistryProvider).value ?? const [];
    if (masters.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add a switch')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.looks_one_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('One switch per app',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'This app is set up with "${masters.first.name}". To use '
                    'a different switch, remove this one in Settings first.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_scanningQr) return _qrScanner();

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your switch')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Join your switch's Wi-Fi network — the name and password "
                'are on the card in the box.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              // The welcome screen tells the user to join from the
              // phone's own Wi-Fi settings and come back — so coming
              // back must have a button.
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text("I've joined the network — check again"),
                onPressed: _busy
                    ? null
                    : () => ref.read(sessionProvider.notifier).refresh(),
              ),
              const SizedBox(height: 24),
              Text(
                'Or set it up from here:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan the card’s QR code'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _scanningQr = true),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Find nearby switch networks'),
                  onPressed: _busy ? null : _scanWifi,
                ),
              ],
              for (final ssid in _nearbySsids)
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text(ssid),
                  onTap: () => setState(() => _ssid.text = ssid),
                ),
              const SizedBox(height: 24),
              TextField(
                controller: _ssid,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Network name (SSID)',
                  helperText: 'Printed on the card in the box.',
                ),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                enabled: !_busy,
                label: 'Wi-Fi password',
                errorText: _error,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _join,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),
              const SizedBox(height: 8),
              // A reinstall wipes the app but not a forgotten password.
              // Recovery runs over Bluetooth without one, so it has to be
              // reachable from here too — this can be the only screen a
              // locked-out fresh install ever sees.
              TextButton.icon(
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Forgot the password? Recover it'),
                onPressed:
                    _busy ? null : () => context.push(Routes.recovery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qrScanner() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the card'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _scanningQr = false),
        ),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw == null) continue;
            final parsed = parseCardQr(raw);
            if (parsed != null) {
              setState(() {
                _scanningQr = false;
                if (parsed.ssid != null) _ssid.text = parsed.ssid!;
                if (parsed.password != null) {
                  _password.text = parsed.password!;
                }
              });
              return;
            }
          }
        },
      ),
    );
  }

  Future<void> _scanWifi() async {
    try {
      final ssids = await ref.read(wifiServiceProvider).scanSsids();
      setState(() => _nearbySsids = ssids);
    } on Exception catch (e) {
      log.w('wifi scan failed: $e');
      setState(() => _error = 'Wi-Fi scan failed — type the network '
          'name from the card instead.');
    }
  }

  Future<void> _join() async {
    final ssid = _ssid.text.trim();
    final password = _password.text;
    if (ssid.isEmpty || password.isEmpty) {
      setState(() => _error = 'Both fields are needed — they are on '
          'the card.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final wifi = ref.read(wifiServiceProvider);
    final joined = await wifi.join(ssid, password);
    if (!joined) {
      setState(() {
        _busy = false;
        _error = 'Could not join "$ssid". Check the password on the card.';
      });
      return;
    }
    // Give routing a moment, verify we can actually reach the master,
    // then let the session flow take over (login or commissioning).
    final reachable = await wifi.masterReachable(
      timeout: const Duration(seconds: 5),
    );
    if (!mounted) return;
    if (!reachable) {
      setState(() {
        _busy = false;
        _error = 'Joined the network but the switch is not answering. '
            'Move closer and try again.';
      });
      return;
    }
    await ref.read(sessionProvider.notifier).refresh();
    // As the gate root (NeedsSetup) there is nothing to pop — the gate
    // re-renders to login/commissioning on its own.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

/// Parsed contents of the card QR. Public for tests.
class CardQr {
  const CardQr({this.uid, this.ssid, this.password});

  final String? uid;
  final String? ssid;
  final String? password;
}

/// Accepts the assumed scheme `unisync://<uid>?s=<ssid>&p=<password>`
/// (open question #3 in PLAN.md); returns null for foreign QR codes so
/// the scanner keeps looking.
CardQr? parseCardQr(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'unisync') return null;
  final uid = uri.host.isEmpty ? null : uri.host.toUpperCase();
  final ssid = uri.queryParameters['s'];
  final password = uri.queryParameters['p'];
  if (uid == null && ssid == null && password == null) return null;
  return CardQr(uid: uid, ssid: ssid, password: password);
}
