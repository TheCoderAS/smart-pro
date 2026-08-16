import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/storage/master_registry.dart';
import '../../auth/application/session.dart';

/// Bottom sheet listing saved masters. Selecting one tries to join its
/// Wi-Fi (when the SSID is known) and re-probes the session; iOS shows
/// its NEHotspotConfiguration prompt during the join.
Future<void> showMasterSwitcher(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final masters = sheetRef.watch(masterRegistryProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Your switches',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final m in _switcherEntries(
                  masters.value ?? const <SavedMaster>[]))
                ListTile(
                  leading: Icon(
                    m.meshId != null && m.meshId != 0
                        ? Icons.hub_outlined
                        : Icons.router_outlined,
                  ),
                  title: Text(m.name),
                  // Typed, never ambiguous: a mesh is one home, a
                  // standalone master is one box.
                  subtitle: Text(
                    m.meshId != null && m.meshId != 0
                        ? 'Mesh · ${m.ssid ?? m.uid}'
                        : 'Standalone · ${m.uid}',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _switchTo(context, ref, m);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add a switch'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push(Routes.addMaster);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

/// Masters that share a mesh id are one home and get one entry — the
/// story is explicit that a meshed master never appears as its own
/// switchable entry.
List<SavedMaster> _switcherEntries(List<SavedMaster> masters) {
  final seenMesh = <int>{};
  final out = <SavedMaster>[];
  for (final m in masters) {
    final mesh = m.meshId;
    if (mesh != null && mesh != 0) {
      if (!seenMesh.add(mesh)) continue;
    }
    out.add(m);
  }
  return out;
}

Future<void> _switchTo(
  BuildContext context,
  WidgetRef ref,
  SavedMaster master,
) async {
  // Crossing networks is slow and the OS interposes its own prompts, so
  // the wait gets a name rather than a bare spinner (story Epic 6).
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text('Connecting to ${master.ssid ?? master.name}…'),
      duration: const Duration(seconds: 8),
    ),
  );
  // The session machine owns the probe, the outcome and last-used. A
  // failed attempt leaves the current session running — so the message
  // has to say that, or the user will assume they just lost both.
  final result = await ref.read(sessionProvider.notifier).switchTo(master);
  messenger.hideCurrentSnackBar();
  final text = switch (result) {
    SwitchAttempt.arrived => null,
    SwitchAttempt.unreachable =>
      "Couldn't reach ${master.name} — staying where you are.",
    SwitchAttempt.wrongNetwork =>
      "You're on a different switch's network — staying where you are.",
    SwitchAttempt.needsWifiLogin =>
      'Sign in to ${master.name} over Wi-Fi once before using Bluetooth.',
  };
  if (text != null) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
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
