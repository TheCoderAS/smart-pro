import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/recovery_service.dart';
import '../../../core/crypto/recovery_hmac.dart';
import '../../../core/widgets/password_field.dart';

/// Lost-password recovery over Bluetooth (story Epic 8). Reachable while
/// logged out, from the login screen and the disconnected screen.
///
/// The user supplies the recovery key from the card *and* the password they
/// want. The master answers plainly — accepted or rejected — and a
/// rejection carries the wait before the next attempt, which is shown as a
/// countdown on the button so the slowdown reads as security rather than
/// breakage. Scope is the master's call: recovering a meshed master
/// recovers the whole home, a standalone one recovers that device.
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
  RecoveryVerdict? _verdict;
  String? _error;
  final _keyController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmController = TextEditingController();

  /// Seconds left on the device-dictated backoff. Counted down for
  /// display only — the master refuses an early attempt regardless.
  int _waitLeft = 0;
  Timer? _waitTimer;

  @override
  void dispose() {
    _waitTimer?.cancel();
    _keyController.dispose();
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _waitTimer?.cancel();
    setState(() => _waitLeft = seconds);
    if (seconds <= 0) return;
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _waitLeft--);
      if (_waitLeft <= 0) t.cancel();
    });
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
    final name = _selected?.name ?? 'this switch';
    final locked = _waitLeft > 0;
    final canSubmit = !locked &&
        _passController.text.length >= 8 &&
        _passController.text == _confirmController.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        // Named, so a household with several cards grabs the right one —
        // and the recovery card is not the password card.
        Text(
          'Use the recovery card for $name. It is the card with the long '
          'key on it, not the one with the password.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keyController,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 39, // 32 hex + separators people may type
          decoration: const InputDecoration(
            labelText: 'Recovery key',
            helperText: '32 characters, printed on the recovery card.',
          ),
        ),
        PasswordField(
          controller: _passController,
          label: 'New password',
          helper: 'At least 8 characters. This becomes the Wi-Fi password '
              'and the sign-in.',
          helperMaxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        PasswordField(
          controller: _confirmController,
          label: 'Repeat password',
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: canSubmit ? _recover : null,
          // The countdown lives on the button, so waiting reads as the
          // switch protecting itself rather than the app hanging.
          child: Text(locked ? 'Try again in ${_waitLeft}s' : 'Recover'),
        ),
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
    final whole = _verdict?.wholeHome ?? false;
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
          whole
              ? 'Done. Your home is being recovered.'
              : 'Done. This switch is being recovered.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Text(
          whole
              ? 'Every master in the mesh is taking the new password. The '
                  'network keeps its name — join it again with the password '
                  'you just chose, then sign in.'
              : 'The switch is restarting its network. Join it again with '
                  'the password you just chose, then sign in.',
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
    } on BlePermissionDenied {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = 'Unisync needs Bluetooth permission to find your switch. '
            'Please allow it and try again — you can grant it in Settings '
            'if the prompt doesn’t appear.';
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
      final verdict = await ref.read(recoveryServiceProvider).recover(
            target: target,
            recoveryKey: _keyController.text,
            newPassword: _passController.text,
          );
      if (!mounted) return;
      if (verdict.accepted) {
        setState(() {
          _verdict = verdict;
          _phase = _Phase.done;
        });
        return;
      }
      setState(() {
        _phase = _Phase.keyEntry;
        _error = verdict.error == 'wrong recovery key'
            ? "That key doesn't match this switch. Check you have the "
                'recovery card for ${target.name}.'
            : 'The switch turned that down.';
      });
      // Straight from the device — the app never computes a backoff.
      _startCountdown(verdict.waitSeconds);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.keyEntry;
        // Silence now means a broken link, not a wrong key: the master
        // answers every attempt explicitly.
        _error = 'No answer from the switch. Move closer and try again.';
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
