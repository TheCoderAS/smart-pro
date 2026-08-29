import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart';
import '../../../core/api/failure.dart';
import '../application/session.dart';
import 'setup_escape.dart';

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

  String? _failureText(AppLocalizations l10n) =>
      switch (widget.state.failure) {
        null => null,
        Unauthorized() => l10n.errorWrongPassword,
        LockedOut(:final retryAfter) =>
          l10n.errorLockedOut(retryAfter.inMinutes),
        RateLimited() => l10n.errorRateLimited,
        Unreachable() => l10n.errorUnreachable,
        ServerFailure(:final status) => l10n.errorServer(status),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locked = widget.state.failure is LockedOut;
    final error = _failureText(l10n);

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
                    l10n.signInTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.masterIdentity(
                      widget.state.info.uid,
                      widget.state.info.fw,
                    ),
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
                      labelText: l10n.passwordLabel,
                      helperText: l10n.passwordHelper,
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
                    child: Text(l10n.signInButton),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    // Reachable while logged out, per API §8.
                    onPressed: () => context.push(Routes.recovery),
                    child: Text(l10n.forgotPassword),
                  ),
                  // Always present, by decree: no screen is a dead end.
                  const SetupEscapeButton(),
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
