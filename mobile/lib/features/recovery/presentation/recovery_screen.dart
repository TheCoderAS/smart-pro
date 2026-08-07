import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/recovery_service.dart';
import '../../../core/crypto/recovery_hmac.dart';

/// Lost-password recovery over Bluetooth (API §8). Reachable while
/// logged out, from the login screen. Standalone recovery returns the
/// card password; mesh recovery generates a new mesh password and
/// pushes it to every master — one master recovers the whole house.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

enum _Phase { idle, scanning, keyEntry, working, done }

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  _Phase _phase = _Phase.idle;
  List<RecoveryDevice> _devices = const [];
  RecoveryDevice? _selected;
  String? _password;
  String? _error;
  int _failures = 0;
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recover password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              switch (_phase) {
                _Phase.idle => _intro(),
                _Phase.scanning => _scanning(),
                _Phase.keyEntry => _keyEntry(),
                _Phase.working => _working(),
                _Phase.done => _done(),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Stand near the switch and have its card ready — you will '
          'need the recovery key printed on it.',
        ),
        const SizedBox(height: 8),
        const Text(
          'For a mesh, recovering any one master resets the password '
          'for the whole house.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Find nearby switches'),
          onPressed: _scan,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _scanning() {
    return Column(
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        const Text('Scanning for switches…'),
        const SizedBox(height: 24),
        for (final d in _devices)
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_remote_outlined),
              title: Text(d.name),
              subtitle: const Text('Tap to recover this switch'),
              onTap: () => setState(() {
                _selected = d;
                _phase = _Phase.keyEntry;
              }),
            ),
          ),
      ],
    );
  }

  Widget _keyEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _selected?.name ?? '',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keyController,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 39, // 32 hex + separators people may type
          decoration: InputDecoration(
            labelText: 'Recovery key',
            helperText: '32 characters, printed on the card in the box.',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _recover,
          child: const Text('Recover'),
        ),
        if (_failures >= 3) ...[
          const SizedBox(height: 16),
          Text(
            'Careful: five wrong attempts lock recovery for 15 minutes.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _working() {
    return const Column(
      children: [
        LinearProgressIndicator(),
        SizedBox(height: 16),
        Text('Talking to the switch…'),
      ],
    );
  }

  Widget _done() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Password recovered',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _password ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Join the switch’s Wi-Fi with this password, then sign in '
          'with it.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Future<void> _scan() async {
    setState(() {
      _phase = _Phase.scanning;
      _error = null;
      _devices = const [];
    });
    try {
      final devices = await ref.read(recoveryServiceProvider).scan();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        if (devices.isEmpty) {
          _phase = _Phase.idle;
          _error = 'No switches found nearby. Move closer and try again.';
        }
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = 'Bluetooth scan failed: $e';
      });
    }
  }

  Future<void> _recover() async {
    final target = _selected;
    if (target == null) return;

    // Validate the key shape before any radio traffic.
    try {
      parseRecoveryKey(_keyController.text);
    } on FormatException {
      setState(() =>
          _error = 'The key is 32 letters/digits (0-9, a-f) — check the card.');
      return;
    }

    setState(() {
      _phase = _Phase.working;
      _error = null;
    });
    try {
      final password = await ref
          .read(recoveryServiceProvider)
          .recover(target, _keyController.text);
      if (!mounted) return;
      setState(() {
        _password = password;
        _phase = _Phase.done;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _failures++;
        _phase = _Phase.keyEntry;
        // Silence is the failure signal (API §8).
        _error = 'No answer from the switch. That usually means the key '
            'is wrong — check it against the card.';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.keyEntry;
        _error = 'Recovery failed: $e';
      });
    }
  }
}
