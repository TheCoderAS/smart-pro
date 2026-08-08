import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../auth/application/session.dart';
import '../../auth/data/auth_repository.dart';
import '../application/theme_mode.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final session = ref.watch(sessionProvider).value;
    final info = switch (session) {
      Authenticated(:final info) => info,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
          const _SectionHeader('Security'),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            subtitle: const Text(
              'Signs out every device everywhere — including this one, '
              'briefly, while it reconnects.',
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
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters. Every token everywhere '
                    'stops working ("sign out all devices").',
                helperMaxLines: 3,
              ),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Repeat password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    final fresh = controller.text;
    final confirmed = confirmController.text;
    controller.dispose();
    confirmController.dispose();
    if (!(ok ?? false)) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (fresh.length < 8 || fresh != confirmed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Passwords must match and be at least 8 characters.'),
        ),
      );
      return;
    }

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

  Future<void> _removeMaster(
    BuildContext context,
    WidgetRef ref,
    String uid,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this master?'),
        content: const Text(
          'Its saved sign-in is deleted from this phone. The switch '
          'itself keeps working and can be added again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
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
