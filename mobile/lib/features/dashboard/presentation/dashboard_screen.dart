import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/ws/state_dto.dart';
import '../../../core/ws/state_socket.dart';
import '../../settings/presentation/master_switcher.dart';
import '../../switches/data/switch_repository.dart';
import '../../switches/presentation/rename_sheet.dart';
import '../application/switch_overrides.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(stateSocketProvider);
    final status = ref.watch(socketStatusProvider);

    // Every snapshot is authoritative (API §4) — clear optimistic
    // overrides the moment one lands, confirmed or contradicted.
    ref.listen(stateSocketProvider, (prev, next) {
      if (next.hasValue) {
        ref.read(switchOverridesProvider.notifier).clearAll();
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Your switches',
          icon: const Icon(Icons.home_work_outlined),
          onPressed: () => showMasterSwitcher(context, ref),
        ),
        title: Text(
          snapshot.value?.masterName.isNotEmpty ?? false
              ? snapshot.value!.masterName
              : 'Unisync',
        ),
        actions: [
          if (status != SocketStatus.connected)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: _ReconnectingChip(),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'reorder':
                  unawaited(context.push(Routes.reorder));
                case 'extensions':
                  unawaited(context.push(Routes.extensions));
                case 'mesh':
                  unawaited(context.push(Routes.mesh));
                case 'firmware':
                  unawaited(context.push(Routes.firmware));
                case 'audit':
                  unawaited(context.push(Routes.audit));
                case 'settings':
                  unawaited(context.push(Routes.settings));
                case 'killall':
                  await _confirmKillAll(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reorder',
                child: Text('Reorder switches'),
              ),
              PopupMenuItem(value: 'extensions', child: Text('Extensions')),
              PopupMenuItem(value: 'mesh', child: Text('Mesh')),
              PopupMenuItem(value: 'firmware', child: Text('Firmware')),
              PopupMenuItem(value: 'audit', child: Text('Activity log')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(
                value: 'killall',
                child: Text('Turn everything off'),
              ),
            ],
          ),
        ],
      ),
      body: switch (snapshot) {
        AsyncValue(value: final StateSnapshot snap) when snap.switches.isNotEmpty =>
          _SwitchGrid(switches: snap.switches),
        AsyncValue(value: final StateSnapshot _) => const _EmptyState(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _confirmKillAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn everything off?'),
        content: const Text(
          'Every switch on every master in the mesh will turn off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(switchRepositoryProvider).killAll();
    }
  }
}

class _ReconnectingChip extends StatelessWidget {
  const _ReconnectingChip();

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      label: const Text('Reconnecting'),
      labelStyle: Theme.of(context).textTheme.labelSmall,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.power_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No switches yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Snap an Extension onto the bus next to your Master '
              'and it will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchGrid extends ConsumerWidget {
  const _SwitchGrid({required this.switches});

  final List<SwitchState> switches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 96,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: switches.length,
      itemBuilder: (context, i) => SwitchTile(sw: switches[i]),
    );
  }
}

/// One relay. Renders the optimistic override when present, else the
/// snapshot state. Public for widget tests.
class SwitchTile extends ConsumerWidget {
  const SwitchTile({required this.sw, super.key});

  final SwitchState sw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(switchOverridesProvider);
    final on = overrides[sw.id] ?? sw.on;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: on ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: sw.online ? () => _toggle(ref, on) : null,
        onLongPress: () => showRenameSwitchSheet(context, ref, sw),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    on ? Icons.toggle_on : Icons.toggle_off_outlined,
                    color: on ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const Spacer(),
                  if (!sw.online)
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 16,
                      color: scheme.error,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                sw.name.isEmpty ? sw.id : sw.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                sw.online ? (on ? 'On' : 'Off') : 'Offline',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, bool currentlyOn) async {
    final next = !currentlyOn;
    final overrides = ref.read(switchOverridesProvider.notifier);
    overrides.set(sw.id, next);
    try {
      await ref.read(switchRepositoryProvider).setRelay(
            id: sw.id,
            on: next,
            ch: sw.ch,
          );
      // Leave the override in place; the next snapshot clears it.
    } on Exception {
      // Command failed — snap back to the snapshot state.
      overrides.clear(sw.id);
    }
  }
}
