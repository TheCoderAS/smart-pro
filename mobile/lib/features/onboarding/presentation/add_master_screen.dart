import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/platform/radios.dart';
import '../../../core/storage/master_registry.dart';
import '../../auth/application/session.dart';

/// The setup screen: get the phone onto the switch's Wi-Fi, then the
/// session flow takes over (sign-in or commissioning). Rendered as the
/// gate root when nothing is added and no master answers (NeedsSetup).
///
/// There is deliberately NO in-app join here — no network list, no SSID
/// field, no Wi-Fi password box, no QR. The app-driven join rode on
/// Android's app-scoped network request, whose system dialog routinely
/// found "no available networks" while the switch was beaconing away,
/// and the password it collected was asked again at sign-in anyway (it
/// is the same password, API §1). The path that has always worked is the
/// phone's own Wi-Fi settings; this screen now points there and gets out
/// of the way.
class AddMasterScreen extends ConsumerWidget {
  const AddMasterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your switch')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Join your switch's Wi-Fi network in your phone's Wi-Fi "
                'settings — the network name and password are on the card '
                'in the box. Then come back here.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.wifi),
                label: const Text("Open the phone's Wi-Fi settings"),
                onPressed: () => ref.read(radiosProvider).openWifiSettings(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text("I've joined the network — check again"),
                onPressed: () => ref.read(sessionProvider.notifier).refresh(),
              ),
              const SizedBox(height: 8),
              Text(
                'Signing in with the password from the card is what adds '
                'the switch to this app — no separate pairing step.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              // A reinstall wipes the app but not a forgotten password.
              // Recovery runs over Bluetooth without one, so it has to be
              // reachable from here too — this can be the only screen a
              // locked-out fresh install ever sees.
              TextButton.icon(
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Forgot the password? Recover it'),
                onPressed: () => context.push(Routes.recovery),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
