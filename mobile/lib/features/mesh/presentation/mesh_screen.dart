import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/widgets/connection_bar.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../../core/ws/state_dto.dart' show Presence, lastSeenLabel;
import '../../auth/application/session.dart';
import '../../onboarding/application/first_run.dart';
import '../data/mesh_repository.dart';
import '../domain/mesh_models.dart';
import 'add_to_mesh_flow.dart';

class MeshScreen extends ConsumerStatefulWidget {
  const MeshScreen({super.key});

  @override
  ConsumerState<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends ConsumerState<MeshScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTip());
  }

  /// One sentence, once, on first mesh entry: roaming between masters is the
  /// phone's own Wi-Fi doing the handoff, and it only works if the phone is
  /// allowed to reconnect on its own. Shown once, findable again in
  /// Settings — a tip, not a nag.
  Future<void> _maybeShowTip() async {
    final status = await ref.read(meshStatusProvider.future);
    if (!status.active || !mounted) return;
    final flags = await ref.read(firstRunProvider.future);
    if (flags.meshTipSeen || !mounted) return;
    await ref.read(firstRunProvider.notifier).markMeshTipSeen();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('One thing for smooth roaming'),
        content: Text(
          'Keep auto-connect switched on for "${status.meshName}" in your '
          "phone's Wi-Fi settings. That's what lets you walk through the "
          'house without the app skipping a beat.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(meshStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh'),
        bottom: const ConnectionBar(),
      ),
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
                  ...s.peers.map(
                    (p) => _PeerTile(peer: p, rolloutTarget: _newest(s)),
                  ),
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

/// The newest firmware version anywhere in the mesh — this master or any
/// peer. Everything behind it is still catching up.
String _newest(MeshStatus s) {
  var best = s.fw;
  for (final p in s.peers) {
    if (p.fw.isEmpty) continue;
    if (best.isEmpty || _fwNewer(p.fw, best)) best = p.fw;
  }
  return best;
}

bool _fwNewer(String a, String b) {
  List<int> parse(String v) => [
        for (final part in v.split('.'))
          int.tryParse(part.replaceAll(RegExp('[^0-9]'), '')) ?? 0,
      ];
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y;
  }
  return false;
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

/// One member master. Every member is listed, reachable or not — a card
/// that vanishes when a master goes quiet is exactly the flapping the story
/// rules out, and the user has to see the state before acting on it.
class _PeerTile extends ConsumerWidget {
  const _PeerTile({required this.peer, this.rolloutTarget = ''});

  final MeshPeer peer;

  /// The newest version anywhere in the mesh. A peer behind it is mid
  /// rollout, not broken.
  final String rolloutTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, colour) = peer.credStale
        ? (Icons.sync_problem, scheme.error)
        : switch (peer.presence) {
            Presence.online => (Icons.router_outlined, scheme.primary),
            Presence.intermittent =>
              (Icons.signal_wifi_statusbar_null_outlined, scheme.tertiary),
            Presence.offline => (Icons.router_outlined, scheme.onSurfaceVariant),
          };

    final line = StringBuffer('Firmware ${peer.fw}');
    // Mid-rollout a mesh legitimately runs several versions: one push
    // propagates master-to-master and each applies at its own pace. That
    // is progress, not a fault, so it reads as "updating" rather than a
    // mismatch warning.
    if (rolloutTarget.isNotEmpty && peer.fw != rolloutTarget) {
      line.write(' · updating to $rolloutTarget');
    }
    if (peer.presence != Presence.online) {
      line
        ..write(' · ${peer.presence.label.toLowerCase()}')
        ..write(' · last seen ${lastSeenLabel(peer.lastSeen)}');
    }
    if (peer.credStale) line.write(' · needs remove & re-add');

    return Card(
      child: ListTile(
        leading: Icon(icon, color: colour),
        title: Text(peer.name.isEmpty ? peer.uid : peer.name),
        subtitle: Text(line.toString()),
        trailing: peer.uid.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.person_remove_outlined),
                // Removal needs the target to delete its own credentials
                // and confirm, so an unreachable master cannot be removed.
                onPressed: peer.removable
                    ? () => _remove(context, ref)
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${peer.name.isEmpty ? "That master" : peer.name} '
                              'has to be reachable before it can be removed. '
                              'Power it on and try again.',
                            ),
                          ),
                        ),
                color: peer.removable ? scheme.error : scheme.onSurfaceVariant,
                tooltip: peer.removable
                    ? 'Remove from mesh'
                    : 'Offline — cannot be removed',
              ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final name = peer.name.isEmpty ? peer.uid : peer.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $name from the mesh?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$name restarts as a standalone switch, using the network name '
              'and password it had before it joined. Its switches leave this '
              'dashboard.\n\n' 
              'It keeps everything of its own — its extensions, names, order '
              'and settings are untouched. Every other master carries on '
              'without interruption.',
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
    if (!(confirmed ?? false) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(meshRepositoryProvider).kick(uid: peer.uid);
      messenger.showSnackBar(
        SnackBar(content: Text('$name left the mesh.')),
      );
    } on ApiFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.describe())));
    }
    await ref.read(meshStatusProvider.notifier).refresh();
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
            label: const Text('Join an existing mesh'),
            onPressed: () => _joinMesh(context, ref),
          ),
        ] else ...[
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add a switch to this mesh'),
            // The invite is fetched and used inside the flow; the PIN
            // never reaches the screen (v5.1 Epic 7).
            onPressed: () => runAddToMeshFlow(context, ref),
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
    final nameController = TextEditingController();
    final passController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create a mesh'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final name = nameController.text.trim();
            final canSave = name.isNotEmpty && passController.text.length >= 8;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 31,
                  decoration: const InputDecoration(labelText: 'Mesh name'),
                  onChanged: (_) => setState(() {}),
                ),
                PasswordField(
                  controller: passController,
                  label: 'Mesh password',
                  helper: 'At least 8 characters. This becomes the Wi-Fi '
                      'password and the sign-in for the whole home.',
                  helperMaxLines: 3,
                ),
                const SizedBox(height: 12),
                // Pre-announce the drop: the network restarts the moment
                // the mesh is created (v5.1 Epic 7).
                Text(
                  'Your network will restart under the new mesh name. '
                  'You will be asked to rejoin it with this password.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FormActions(
                  saveLabel: 'Create',
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
    final name = nameController.text.trim();
    final pass = passController.text;
    nameController.dispose();
    passController.dispose();
    if (!(ok ?? false) || name.isEmpty || pass.length < 8) return;
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref.read(meshRepositoryProvider).create(name: name, pass: pass);
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

  Future<void> _joinMesh(BuildContext context, WidgetRef ref) async {
    final macController = TextEditingController();
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join an existing mesh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The easy way round is from the other side: open the app on '
              'the mesh you already have and choose "Add a switch to this '
              'mesh". It carries the invite across for you.\n\n'
              'This form is the manual fallback if that cannot reach this '
              'switch.',
            ),
            const SizedBox(height: 16),
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
        content: StatefulBuilder(
          builder: (context, setState) {
            final canSave = newController.text.length >= 8 &&
                oldController.text.isNotEmpty;
            return Column(
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
