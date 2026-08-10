import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart';
import '../../../core/storage/master_registry.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../onboarding/presentation/commissioning_screen.dart';
import '../application/session.dart';
import 'login_screen.dart';

/// Root widget behind `/` — renders whatever the session state calls
/// for. Navigation stays flat because the states are exclusive.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return switch (session.value) {
      Authenticated() => const DashboardScreen(),
      final NeedsLogin s => LoginScreen(state: s),
      final NeedsCommissioning s => CommissioningScreen(state: s),
      MasterUnreachable() => const _UnreachableScreen(),
      _ => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
    };
  }
}

class _UnreachableScreen extends ConsumerWidget {
  const _UnreachableScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Only a paired master can be reached over Bluetooth (it needs the
    // saved token) — hide the option otherwise.
    final hasPairedMaster =
        (ref.watch(masterRegistryProvider).value ?? const []).isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.unreachableTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.unreachableBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(sessionProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.tryAgain),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push(Routes.addMaster),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addASwitch),
                ),
                if (hasPairedMaster) ...[
                  const SizedBox(height: 8),
                  // Control the master over Bluetooth without joining its
                  // Wi-Fi — uses the saved token, no re-login.
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await ref
                          .read(sessionProvider.notifier)
                          .connectOverBle();
                      if (!ok) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.bleNoSavedSession)),
                        );
                      }
                    },
                    icon: const Icon(Icons.bluetooth_rounded),
                    label: Text(l10n.controlOverBluetooth),
                  ),
                ],
                const SizedBox(height: 8),
                // A user who lost the password can't join the master's
                // Wi-Fi (the password IS the Wi-Fi key), so they land
                // here rather than on the login screen. BLE recovery
                // works over Bluetooth without the password, so it must
                // be reachable from this screen too — not only from
                // login (API §8: "reachable from a logged-out app").
                TextButton.icon(
                  onPressed: () => context.push(Routes.recovery),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(l10n.forgotPasswordRecover),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
