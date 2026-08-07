import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../application/session.dart';

/// Password prompt. One password joins the Wi-Fi and logs in (API §1);
/// by the time the user is here they're on the AP, so the login is a
/// formality — but the token it yields authorises everything after.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({required this.state, super.key});

  final NeedsLogin state;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _failureText => switch (widget.state.failure) {
        null => null,
        Unauthorized() => 'Wrong password. It is on the card in the box.',
        LockedOut(:final retryAfter) =>
          'Too many attempts. Locked for about ${retryAfter.inMinutes} '
              'minutes.',
        RateLimited() => 'Too many requests — give it a few seconds.',
        Unreachable() => 'Lost the connection to the switch. '
            'Check that you are still on its Wi-Fi.',
        ServerFailure(:final status) => 'The switch replied with an error '
            '($status). Try again.',
      };

  @override
  Widget build(BuildContext context) {
    final locked = widget.state.failure is LockedOut;
    final error = _failureText;

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
                  Text(
                    'Sign in',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Master ${widget.state.info.uid} · '
                    'firmware ${widget.state.info.fw}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !locked,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText:
                          'The same password you used to join the Wi-Fi.',
                      errorText: error,
                      errorMaxLines: 3,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: locked ? null : (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: locked ? null : _submit,
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    // BLE recovery flow arrives with block 12 — the
                    // route exists so the affordance is discoverable
                    // from day one (API §8: must be reachable while
                    // logged out).
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password recovery is coming soon.'),
                      ),
                    ),
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    ref.read(sessionProvider.notifier).login(password);
  }
}
