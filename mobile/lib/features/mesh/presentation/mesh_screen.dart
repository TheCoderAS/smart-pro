import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../auth/application/session.dart';
import '../data/mesh_repository.dart';
import '../domain/mesh_models.dart';

class MeshScreen extends ConsumerWidget {
  const MeshScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(meshStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(meshStatusProvider.notifier).refresh(),
        child: switch (status) {
          AsyncValue(value: final MeshStatus s) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (s.credStale) const CredStaleTile(),
                if (!s.active) ...[
                  const _StandaloneCard(),
                ] else ...[
                  _MeshStatusCard(status: s),
                  const SizedBox(height: 12),
                  ...s.peers.map((p) => _PeerTile(peer: p)),
                ],
                const SizedBox(height: 24),
                _Actions(status: s),
              ],
            ),
          AsyncValue(:final Object error) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text(
                    error is ApiFailure
                        ? error.describe()
                        : 'Something went wrong.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// The one unrecoverable state (API §5): this master missed a
/// password change while offline. Public for widget tests.
class CredStaleTile extends StatelessWidget {
  const CredStaleTile({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_problem, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This master is out of sync',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'It missed a password change while offline and cannot '
              'catch up on its own. Remove it from the mesh, then '
              'invite it again.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandaloneCard extends StatelessWidget {
  const _StandaloneCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standalone master',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'This master is not part of a mesh. Create one to link '
              'several masters into a single home-wide network.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MeshStatusCard extends StatelessWidget {
  const _MeshStatusCard({required this.status});

  final MeshStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.hub_outlined),
        title: Text(status.meshName.isEmpty ? 'Mesh' : status.meshName),
        subtitle: Text(
          '${status.peerCount} peer master'
          '${status.peerCount == 1 ? "" : "s"}'
          '${status.syncing ? " · syncing…" : ""}',
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final MeshPeer peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          peer.credStale ? Icons.sync_problem : Icons.router_outlined,
          color: peer.credStale ? scheme.error : null,
        ),
        title: Text(peer.name),
        subtitle: Text(
          'Firmware ${peer.fw}'
          '${peer.credStale ? " · needs remove & re-add" : ""}',
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.status});

  final MeshStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!status.active) ...[
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create a mesh'),
            onPressed: () => _createMesh(context, ref),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Join a mesh (enter invite)'),
            onPressed: () => _joinMesh(context, ref),
          ),
        ] else ...[
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Invite another master'),
            onPressed: () => _invite(context, ref),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Rename mesh'),
            onPressed: () => _renameMesh(context, ref),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.password),
            label: const Text('Change mesh password'),
            onPressed: () => _changePassword(context, ref),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Leave mesh'),
            onPressed: () => _leave(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _guard(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      await ref.read(meshStatusProvider.notifier).refresh();
    } on ApiFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.describe())));
    }
  }

  Future<void> _createMesh(BuildContext context, WidgetRef ref) async {
    final name = await _promptText(context, 'Create a mesh', 'Mesh name');
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref.read(meshRepositoryProvider).create(name: name);
    });
  }

  Future<void> _renameMesh(BuildContext context, WidgetRef ref) async {
    final name = await _promptText(context, 'Rename mesh', 'Mesh name');
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref.read(meshRepositoryProvider).rename(name: name);
    });
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final MeshInvite invite;
    try {
      invite = await ref.read(meshRepositoryProvider).invite();
    } on ApiFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.describe())));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On the phone connected to the new master, choose '
              '"Join a mesh" and enter:',
            ),
            const SizedBox(height: 16),
            SelectableText('MAC:  ${invite.mac}'),
            SelectableText('PIN:  ${invite.pin}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinMesh(BuildContext context, WidgetRef ref) async {
    final macController = TextEditingController();
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join a mesh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: macController,
              decoration: const InputDecoration(labelText: 'MAC'),
              autocorrect: false,
            ),
            TextField(
              controller: pinController,
              decoration: const InputDecoration(labelText: 'PIN'),
              autocorrect: false,
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
            child: const Text('Join'),
          ),
        ],
      ),
    );
    final mac = macController.text.trim();
    final pin = pinController.text.trim();
    macController.dispose();
    pinController.dispose();
    if (!(ok ?? false) || mac.isEmpty || pin.isEmpty) return;
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref.read(meshRepositoryProvider).join(mac: mac, pin: pin);
    });
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the mesh?'),
        content: const Text(
          'This master goes back to standalone and its own device '
          'password (the one on the card). Its switches stop being '
          'reachable from other rooms.',
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
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref.read(meshRepositoryProvider).leave();
    });
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change mesh password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PasswordField(
              controller: oldController,
              label: 'Current password',
            ),
            PasswordField(
              controller: newController,
              label: 'New password',
              helper: 'At least 8 characters. Every master takes '
                  'the change; every signed-in device must sign in '
                  'again.',
              helperMaxLines: 3,
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
    final old = oldController.text;
    final fresh = newController.text;
    oldController.dispose();
    newController.dispose();
    if (!(ok ?? false) || fresh.length < 8) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final meshName = status.meshName;
    try {
      // Reply comes back BEFORE the Wi-Fi restarts (API §6).
      await ref.read(meshRepositoryProvider).changePassword(
            old: old,
            pass: fresh,
            name: meshName,
          );
    } on ApiFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.describe())));
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Password changed. Reconnecting…'),
      ),
    );
    // Best-effort Wi-Fi rejoin with the new credential, then the
    // login-retry dance.
    final wifi = ref.read(wifiServiceProvider);
    final ssid = await wifi.currentSsid();
    if (ssid != null) {
      // Fire and forget — join() may block on a system prompt.
      // The session retry loop below tolerates either outcome.
      // ignore: unawaited_futures
      wifi.join(ssid, fresh);
    }
    await ref.read(sessionProvider.notifier).handlePasswordChanged(fresh);
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title,
  String label,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 32,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
