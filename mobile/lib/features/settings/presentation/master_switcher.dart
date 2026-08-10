import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/wifi/wifi_service.dart';
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
              for (final m
                  in masters.value ?? const <SavedMaster>[])
                ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: Text(m.name),
                  subtitle: Text(m.uid),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _switchTo(ref, m);
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

Future<void> _switchTo(WidgetRef ref, SavedMaster master) async {
  await ref.read(masterRegistryProvider.notifier).setLastUsed(master.uid);
  final ssid = master.ssid;
  if (ssid != null) {
    // Roaming note (API §3): if both masters are in one mesh the SSID
    // is identical and this is a no-op; distinct meshes have distinct
    // SSIDs and need the join.
    final password =
        await ref.read(secureStoreProvider).readPassword(master.uid);
    if (password != null) {
      await ref.read(wifiServiceProvider).join(ssid, password);
    }
  }
  await ref.read(sessionProvider.notifier).refresh();
}
