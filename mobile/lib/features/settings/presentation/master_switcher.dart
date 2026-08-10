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
  // The session machine owns the probe, the outcome and last-used: a
  // failed switch must not change where the app opens next time.
  await ref.read(sessionProvider.notifier).switchTo(master);
  messenger.hideCurrentSnackBar();
}
