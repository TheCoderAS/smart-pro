import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_coordinator.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/connection_bar.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/wifi_guard.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../../core/ws/state_socket.dart';
import '../../auth/application/session.dart';
import '../../auth/data/auth_repository.dart';
import '../application/theme_mode.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final transportPref = ref.watch(transportPreferenceProvider);
    final session = ref.watch(sessionProvider).value;
    final info = switch (session) {
      Authenticated(:final info) => info,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), bottom: const ConnectionBar()),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (mode) {
              if (mode != null) {
                ref.read(themeModeProvider.notifier).set(mode);
              }
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('Follow system'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Connection'),
          RadioGroup<TransportPreference>(
            groupValue: transportPref,
            onChanged: (pref) {
              if (pref != null) {
                ref.read(transportCoordinatorProvider).choose(pref);
              }
            },
            child: const Column(
              children: [
                RadioListTile<TransportPreference>(
                  value: TransportPreference.auto,
                  title: Text('Automatic'),
                  subtitle: Text(
                    "Wi-Fi when you're on the switch's network, "
                    'Bluetooth otherwise.',
                  ),
                ),
                RadioListTile<TransportPreference>(
                  value: TransportPreference.wifi,
                  title: Text('Wi-Fi only'),
                  subtitle: Text(
                    "Always use the switch's Wi-Fi. Unlocks setup and updates.",
                  ),
                ),
                RadioListTile<TransportPreference>(
                  value: TransportPreference.bluetooth,
                  title: Text('Bluetooth'),
                  subtitle: Text(
                    'Control over Bluetooth so your phone keeps its own '
                    'network.',
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Security'),
          ListTile(
            leading: const Icon(Icons.group_off_outlined),
            // Named for what it does. There are no guest tiers and no
            // per-person identity, so "remove someone" does not exist —
            // pretending otherwise would be the lie (story Epic 4).
            title: const Text('Reset access'),
            subtitle: const Text(
              'Sets a new password. Everyone who had the old one loses '
              'access, including you on your other devices — this is the '
              'only way to un-share.',
            ),
            enabled: info != null,
            onTap: () => _changePassword(context, ref),
          ),
          const Divider(),
          const _SectionHeader('This master'),
          if (info != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('Master ${info.uid}'),
              subtitle: Text('Firmware ${info.fw}'),
            ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename this master'),
            subtitle: const Text('The name shown at the top of the dashboard.'),
            enabled: info != null,
            onTap: info == null ? null : () => _renameMaster(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: const Text('Only on this phone.'),
            enabled: info != null,
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Remove this master from the app',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            enabled: info != null,
            onTap: info == null
                ? null
                : () => _removeMaster(context, ref, info.uid),
          ),
          const Divider(),
          const _SectionHeader('Sharing'),
          const ListTile(
            leading: Icon(Icons.people_outline),
            title: Text('Everyone with the password has full control'),
            subtitle: Text(
              'Sharing the password is the whole model — it joins the '
              'network and signs in. There are no guest accounts and no '
              'per-person access, so anyone you tell can do anything you '
              'can. Any number of people can control the home at once.',
              maxLines: 5,
            ),
            isThreeLine: true,
          ),
          const Divider(),
          const _SectionHeader('If you get stuck'),
          const ListTile(
            leading: Icon(Icons.restart_alt),
            title: Text('Factory reset'),
            subtitle: Text(
              'Hold the reset button on the back of the box for 9 seconds. '
              'That returns it to its out-of-box network name and card '
              'password and forgets every name, setting and extension. It '
              'cannot be done from the app — a shorter press does nothing.',
              maxLines: 5,
            ),
            isThreeLine: true,
          ),
          const Divider(),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.phone_iphone),
            title: Text('Unisync'),
            subtitle: Text('Version 0.1.0'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    // Changing the password is a Wi-Fi-only flow (BLE spec v2 §9).
    if (!requireWifi(context, ref)) return;
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset access'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final fresh = controller.text;
            final canSave = fresh.length >= 8 && fresh == confirmController.text;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PasswordField(
                  controller: controller,
                  label: 'New password',
                  helper: 'At least 8 characters. Every token everywhere '
                      'stops working ("sign out all devices").',
                  helperMaxLines: 3,
                ),
                PasswordField(
                  controller: confirmController,
                  label: 'Repeat password',
                ),
                const SizedBox(height: 16),
                FormActions(
                  saveLabel: 'Change',
                  canSave: canSave,
                  onCancel: () => Navigator.of(dialogContext).pop(false),
                  onSave: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ),
      ),
    );
    final fresh = controller.text;
    controller.dispose();
    confirmController.dispose();
    if (!(ok ?? false)) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Reply first, Wi-Fi restart ~400 ms later (API §6).
      await ref.read(authRepositoryProvider).setPassword(fresh);
    } on ApiFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.describe())));
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Password changed. Reconnecting…')),
    );
    final wifi = ref.read(wifiServiceProvider);
    final ssid = await wifi.currentSsid();
    if (ssid != null) {
      // ignore: unawaited_futures
      wifi.join(ssid, fresh);
    }
    await ref.read(sessionProvider.notifier).handlePasswordChanged(fresh);
  }

  Future<void> _renameMaster(BuildContext context, WidgetRef ref) async {
    // Rename works on either transport (firmware v11.18.0).
    final current = switch (ref.read(sessionProvider).value) {
      Authenticated(:final info) => info,
      _ => null,
    };
    final controller = TextEditingController(
      text: ref.read(stateSocketProvider).value?.masterName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename master'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final value = controller.text.trim();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                FormActions(
                  canSave: value.isNotEmpty,
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  onSave: () => Navigator.of(dialogContext).pop(value),
                ),
              ],
            );
          },
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || current == null) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(activeControlProvider).renameMaster(name);
      messenger.showSnackBar(const SnackBar(content: Text('Master renamed.')));
    } on Exception catch (e) {
      final msg = e is ApiFailure
          ? e.describe()
          : "Couldn't rename — check the connection.";
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _removeMaster(
    BuildContext context,
    WidgetRef ref,
    String uid,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this master?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Its saved sign-in is deleted from this phone. The switch '
              'itself keeps working and can be added again any time.',
            ),
            const SizedBox(height: 16),
            FormActions(
              saveLabel: 'Remove',
              destructive: true,
              onCancel: () => Navigator.of(dialogContext).pop(false),
              onSave: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (!(confirmed ?? false)) return;
    await ref.read(secureStoreProvider).purgeMaster(uid);
    await ref.read(masterRegistryProvider.notifier).remove(uid);
    await ref.read(sessionProvider.notifier).signOut();
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
