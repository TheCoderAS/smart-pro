import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/router.dart';
import '../../../core/platform/radios.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/transport/access_reset.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../../../core/ws/snapshot_cache.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../onboarding/presentation/add_master_screen.dart';
import '../../onboarding/presentation/commissioning_screen.dart';
import '../../onboarding/presentation/welcome_screen.dart';
import '../application/session.dart';
import 'login_screen.dart';
import 'setup_escape.dart';

/// Root widget behind `/` — renders whatever the session state calls
/// for. Navigation stays flat because the states are exclusive.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    // The password was changed while we were on Bluetooth, so the token
    // died. BLE has no login — show the instruction screen, never a
    // login form, until a Wi-Fi sign-in succeeds (v5.1 Epic 5).
    if (ref.watch(accessResetProvider)) return const _AccessResetScreen();

    return switch (session.value) {
      Authenticated() => const DashboardScreen(),
      final NeedsLogin s => LoginScreen(state: s),
      final NeedsCommissioning s => CommissioningScreen(state: s),
      NeedsWelcome() => const WelcomeScreen(),
      // Nothing paired and no master answering: setup, not an outage.
      // The unreachable screen here was a dead end on a fresh install —
      // no way to add anything, nothing to try again against.
      NeedsSetup() => const AddMasterScreen(),
      final WrongNetwork s => _WrongNetworkScreen(state: s),
      MasterUnreachable() => const _UnreachableScreen(),
      // Still probing. If we have a house to show and a session to show it
      // with, show it now rather than a spinner — someone reaching for
      // their phone in an emergency should not wait on a network probe.
      // The controls stay disabled until the link confirms, so this is a
      // head start, not a lie about the state.
      _ => ref.watch(snapshotCacheProvider) != null
          ? const DashboardScreen()
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    };
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
                // The phone's own Wi-Fi picker, not an app-driven join:
                // the user chooses "$network" themselves, which is
                // deterministic — the old in-app join here could land on
                // whichever box answered and loop right back to this
                // screen.
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(radiosProvider).openWifiSettings(),
                  icon: const Icon(Icons.wifi),
                  label: const Text("Open the phone's Wi-Fi settings"),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(sessionProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("I've joined — check again"),
                ),
                const SizedBox(height: 8),
                // No identity screen is allowed to be a dead end.
                TextButton.icon(
                  onPressed: () => confirmSetupDifferentSwitch(context, ref),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Set up a different switch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a master rejected our session over Bluetooth: the password
/// changed, so every token everywhere died. Bluetooth mode is unusable
/// until a Wi-Fi sign-in completes, so this is an instruction — not a
/// login form and not a generic error (v5.1 Epic 5).
class _AccessResetScreen extends ConsumerWidget {
  const _AccessResetScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Name the network the user has to join, when we know it.
    final masters = ref.watch(masterRegistryProvider).value ?? const [];
    final ssid = masters
        .map((m) => m.ssid)
        .firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_reset_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.accessResetTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  ssid == null
                      ? l10n.accessResetBodyGeneric
                      : l10n.accessResetBody(ssid),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    // Back to Wi-Fi, clear the flag, re-probe: the normal
                    // login screen takes it from here.
                    await ref
                        .read(transportCoordinatorProvider)
                        .choose(TransportPreference.wifi);
                    ref.read(accessResetProvider.notifier).clear();
                    await ref.read(sessionProvider.notifier).refresh();
                  },
                  icon: const Icon(Icons.wifi_rounded),
                  label: Text(l10n.joinWifi),
                ),
                const SizedBox(height: 8),
                // Always an exit, by decree: no screen is a dead end.
                const SetupEscapeButton(),
              ],
            ),
          ),
        ),
      ),
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
                // The escape hatch when the paired switch is gone for
                // good (died, sold, moved out). Settings lives behind the
                // dashboard and the dashboard needs the master — without
                // this, a dead master bricks the app forever.
                TextButton.icon(
                  onPressed: () => confirmSetupDifferentSwitch(context, ref),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Set up a different switch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

