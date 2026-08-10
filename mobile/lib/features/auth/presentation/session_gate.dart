import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../onboarding/presentation/commissioning_screen.dart';
import '../../onboarding/presentation/welcome_screen.dart';
import '../../settings/presentation/master_switcher.dart';
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
      NeedsWelcome() => const WelcomeScreen(),
      final WrongNetwork s => _WrongNetworkScreen(state: s),
      final AccessReset s => _AccessResetScreen(state: s),
      MasterUnreachable() => const _UnreachableScreen(),
      _ => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
    };
  }
}

/// Someone reset access while this phone was on Bluetooth.
///
/// An instruction, not a login form. Login is Wi-Fi-only by design, so a
/// password field here would be a dead end — the way back is the master's
/// network. Bluetooth stays unusable until that happens, and saying so is
/// kinder than letting the user hunt for it.
class _AccessResetScreen extends ConsumerWidget {
  const _AccessResetScreen({required this.state});

  final AccessReset state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final network = state.network;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_reset_rounded,
                    size: 56, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'Your access was reset',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  network == null
                      ? 'Someone changed the password, so every device was '
                          "signed out. Connect to your switch's Wi-Fi and "
                          'sign in again with the new password.'
                      : 'Someone changed the password, so every device was '
                          'signed out. Connect to "$network" and sign in '
                          'again with the new password.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bluetooth carries a session — it cannot create one, so '
                  'it stays unavailable until you have signed in.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(transportCoordinatorProvider)
                        .choose(TransportPreference.wifi);
                    await ref.read(sessionProvider.notifier).refresh();
                  },
                  icon: const Icon(Icons.wifi),
                  label: const Text("I'm on the Wi-Fi — sign in"),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.push(Routes.recovery),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text("I don't know the new password"),
                ),
                const MasterSwitcherButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone answered — just not the master the user asked for.
///
/// Deliberately not the disconnected screen and emphatically not a login
/// form: "join this network" is something the user can act on, and being on
/// the wrong network has nothing to do with credentials.
class _WrongNetworkScreen extends ConsumerWidget {
  const _WrongNetworkScreen({required this.state});

  final WrongNetwork state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final wanted = state.wanted;
    final network = wanted.ssid ?? wanted.name;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded,
                    size: 56, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'Wrong network',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  state.found == null
                      ? "You're connected to a different switch's network. "
                          'Join "$network" to reach ${wanted.name}.'
                      : "You're connected to ${state.found}. "
                          'Join "$network" to reach ${wanted.name}.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(sessionProvider.notifier).switchTo(wanted),
                  icon: const Icon(Icons.wifi),
                  label: Text('Connect to $network'),
                ),
                const SizedBox(height: 8),
                // Bluetooth reaches it without crossing networks at all,
                // which is usually faster than fighting the OS.
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await ref
                        .read(sessionProvider.notifier)
                        .connectOverBle();
                    if (!ok) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Sign in to that switch over Wi-Fi once first.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.bluetooth_rounded),
                  label: const Text('Use Bluetooth instead'),
                ),
                const SizedBox(height: 8),
                const MasterSwitcherButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The switcher, reachable from any dead end. Being locked out of one
/// master must never trap the user away from the others — so this appears
/// on the login screen and every disconnected screen, not just the
/// dashboard, whenever more than one master is set up.
class MasterSwitcherButton extends ConsumerWidget {
  const MasterSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masters = ref.watch(masterRegistryProvider).value ?? const [];
    if (masters.length < 2) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => showMasterSwitcher(context, ref),
      icon: const Icon(Icons.swap_horizontal_circle_outlined),
      label: const Text('Switch to another switch'),
    );
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
                const MasterSwitcherButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
