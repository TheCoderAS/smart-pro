import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/failure.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/connection_bar.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/widgets/wifi_guard.dart';
import '../../../core/ws/state_dto.dart' show Presence, lastSeenLabel;
import '../../firmware/domain/firmware_models.dart';
import '../../firmware/presentation/firmware_screen.dart' show manifestsProvider;
import '../data/extension_repository.dart';
import '../domain/extension_models.dart';

class ExtensionsScreen extends ConsumerWidget {
  const ExtensionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions'), bottom: const ConnectionBar()),
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
          switch (ext.presence) {
            Presence.online => Icons.extension,
            Presence.intermittent => Icons.sync_problem_outlined,
            Presence.offline => Icons.extension_off_outlined,
          },
          color: switch (ext.presence) {
            Presence.online => scheme.primary,
            Presence.intermittent => scheme.tertiary,
            Presence.offline => scheme.onSurfaceVariant,
          },
        ),
        title: Text(ext.name.isEmpty ? 'Slot ${ext.slot + 1}' : ext.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_switchNames(ext)),
            Text(_presenceLine(ext)),
            // `avail` reflects only what is already staged in THIS
            // master's library, so an image the app has downloaded but not
            // uploaded is invisible there. Availability is the app's call,
            // from its own manifest against the version actually running.
            if (_updateAvailable(ref, ext) case final version?)
              Text(
                'Update available: $version',
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
            switch (v) {
              case 'rename':
                // Rename works on either transport (firmware v11.18.0).
                await _rename(context, ref);
              case 'remove':
                // Unpairing is assignment — Wi-Fi-only (changelog §9).
                if (requireWifi(context, ref)) await _remove(context, ref);
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

  /// The newest manifest entry for this board's type, when it beats what
  /// the board is running. Null when it is up to date or the manifest
  /// hasn't loaded (offline on the master's Wi-Fi, which is normal).
  String? _updateAvailable(WidgetRef ref, ExtensionInfo ext) {
    final List<FirmwareManifest>? manifests =
        ref.watch(manifestsProvider).value;
    if (manifests == null) return null;
    String? best;
    for (final m in manifests) {
      if (m.type != ext.type) continue;
      if (!_newer(m.version, ext.fw)) continue;
      if (best == null || _newer(m.version, best)) best = m.version;
    }
    return best;
  }

  static bool _newer(String a, String b) {
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

  /// Default switch names are per-board, so every extension would otherwise
  /// read "Switch 1 · Switch 2" and the list would be a wall of identical
  /// rows. Number the defaults by slot the way the master's own web UI does.
  String _switchNames(ExtensionInfo ext) {
    final one = ext.sw1.isEmpty ? 'Switch ${ext.slot * 2 + 3}' : ext.sw1;
    final two = ext.sw2.isEmpty ? 'Switch ${ext.slot * 2 + 4}' : ext.sw2;
    return '$one · $two';
  }

  /// Presence comes from the master, with its last-seen time. "Offline"
  /// means the app can't reach it — the physical switch still works.
  String _presenceLine(ExtensionInfo ext) {
    final fw = 'Firmware ${ext.fw}';
    return switch (ext.presence) {
      Presence.online => fw,
      Presence.offline =>
        '$fw · offline · last seen ${lastSeenLabel(ext.lastSeen)}',
      Presence.intermittent =>
        '$fw · intermittent · last seen ${lastSeenLabel(ext.lastSeen)}',
    };
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
          .read(activeControlProvider)
          .renameExtension(slot: ext.slot, name: name);
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
              'Its switches disappear from every device, and its names and '
              'settings are forgotten. If this board later reappears on the '
              'bus it is adopted as new, with default names.\n\n'
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
    } on Exception catch (e) {
      final msg = e is ApiFailure
          ? e.describe()
          : "Couldn't complete that — check the connection.";
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
