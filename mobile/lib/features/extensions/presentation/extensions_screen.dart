import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/widgets/wifi_guard.dart';
import '../data/extension_repository.dart';
import '../domain/extension_models.dart';

class ExtensionsScreen extends ConsumerWidget {
  const ExtensionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(extensionsProvider.notifier).refresh(),
        child: switch (extensions) {
          AsyncValue(value: final List<ExtensionInfo> list)
              when list.isNotEmpty =>
            ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: list.length,
              itemBuilder: (context, i) => ExtensionTile(ext: list[i]),
            ),
          AsyncValue(value: final List<ExtensionInfo> _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [_EmptyExtensions()],
            ),
          AsyncValue(:final Object error) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_ErrorState(error: error)],
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _EmptyExtensions extends StatelessWidget {
  const _EmptyExtensions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(
            Icons.extension_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No extensions on this master',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Snap an Extension onto the low-voltage bus and it will '
            'ask to join here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final message =
        e is ApiFailure ? e.describe() : 'Something went wrong.';
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(Icons.error_outline,
              size: 56, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// One extension row. Public for widget tests.
class ExtensionTile extends ConsumerWidget {
  const ExtensionTile({required this.ext, super.key});

  final ExtensionInfo ext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        // Keep the icon and the ⋮ menu vertically centred against the
        // multi-line subtitle.
        titleAlignment: ListTileTitleAlignment.center,
        leading: Icon(
          ext.online ? Icons.extension : Icons.extension_off_outlined,
          color: ext.online ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(ext.name.isEmpty ? 'Slot ${ext.slot + 1}' : ext.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ext.sw1.isEmpty ? "Switch 1" : ext.sw1} · '
              '${ext.sw2.isEmpty ? "Switch 2" : ext.sw2}',
            ),
            Text('Firmware ${ext.fw}${ext.online ? "" : " · offline"}'),
            if (ext.avail != null)
              Text(
                'Update available: ${ext.avail}',
                style: TextStyle(color: scheme.primary),
              ),
            if (ext.stuck)
              Text(
                'Update failed 3 times — needs attention',
                style: TextStyle(color: scheme.error),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            // Renaming and unpairing are Wi-Fi-only (BLE spec v2 §9).
            if (!requireWifi(context, ref)) return;
            switch (v) {
              case 'rename':
                await _rename(context, ref);
              case 'remove':
                await _remove(context, ref);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: ext.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename extension'),
        content: StatefulBuilder(
          builder: (context, setState) {
            final value = controller.text.trim();
            final canSave = value.isNotEmpty && value != ext.name;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 32,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (canSave) Navigator.of(dialogContext).pop(value);
                  },
                ),
                const SizedBox(height: 8),
                FormActions(
                  canSave: canSave,
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
    if (name == null || name.isEmpty || name == ext.name) return;
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref
          .read(extensionRepositoryProvider)
          .rename(slot: ext.slot, name: name);
    });
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this extension?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Its switches disappear from every device. '
              'This cannot be undone.',
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
    if (!context.mounted) return;
    await _guard(context, ref, () async {
      await ref.read(extensionRepositoryProvider).remove(slot: ext.slot);
    });
  }

  Future<void> _guard(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      await ref.read(extensionsProvider.notifier).refresh();
    } on ApiFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.describe())));
    }
  }
}
