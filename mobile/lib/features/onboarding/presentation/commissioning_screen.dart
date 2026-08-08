import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/storage/master_registry.dart';
import '../../auth/application/session.dart';
import '../../auth/data/auth_repository.dart';

/// Factory-fresh master (info.auth == false): the API is wide open
/// until an owner password is set, and whoever sets it first owns the
/// device (ops guide §A2/§A3) — hence the "do this now" wording.
class CommissioningScreen extends ConsumerStatefulWidget {
  const CommissioningScreen({required this.state, super.key});

  final NeedsCommissioning state;

  @override
  ConsumerState<CommissioningScreen> createState() =>
      _CommissioningScreenState();
}

class _CommissioningScreenState extends ConsumerState<CommissioningScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.new_releases_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Set up your new switch',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Master ${widget.state.info.uid} has no owner yet. '
                    'Choose its password now — until one is set, anyone '
                    'on this network can claim it.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      helperText: 'At least 8 characters.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'Repeat password',
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _commission,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Claim this switch'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _commission() async {
    final password = _password.text;
    if (password.length < 8) {
      setState(() => _error = 'The password needs at least 8 characters.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).setPassword(password);
      // Remember this master, then log straight in with the fresh
      // password (no Wi-Fi restart on first-time commissioning — the
      // AP credential is separate, ops guide §A2).
      await ref.read(masterRegistryProvider.notifier).upsert(
            SavedMaster(
              uid: widget.state.info.uid,
              name: 'Master ${widget.state.info.uid}',
            ),
          );
      await ref.read(sessionProvider.notifier).login(password);
    } on ApiFailure catch (e) {
      setState(() {
        _busy = false;
        _error = e.describe();
      });
    }
  }
}
