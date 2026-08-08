import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ws/state_dto.dart';
import '../data/switch_repository.dart';

/// Long-press affordance on a switch tile. The new name lands via
/// POST /api/switch/rename; the next snapshot repaints every consumer.
Future<void> showRenameSwitchSheet(
  BuildContext context,
  WidgetRef ref,
  SwitchState sw,
) {
  final controller = TextEditingController(text: sw.name);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rename switch',
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty || name == sw.name) {
                Navigator.of(sheetContext).pop();
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(sheetContext).pop();
              try {
                await ref
                    .read(switchRepositoryProvider)
                    .rename(id: sw.id, name: name);
              } on Exception {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Rename failed — check the connection.'),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}
