import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/transport/transport_manager.dart';
import '../../../core/widgets/form_actions.dart';
import '../../../core/ws/state_dto.dart';

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
      child: StatefulBuilder(
        builder: (context, setState) {
          final name = controller.text.trim();
          final canSave = name.isNotEmpty && name != sw.name;
          Future<void> save() async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.of(sheetContext).pop();
            try {
              await ref
                  .read(activeControlProvider)
                  .renameSwitch(id: sw.id, name: name);
            } on Exception {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Rename failed — check the connection.'),
                ),
              );
            }
          }

          return Column(
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
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (canSave) save();
                },
              ),
              const SizedBox(height: 8),
              FormActions(
                canSave: canSave,
                onCancel: () => Navigator.of(sheetContext).pop(),
                onSave: save,
              ),
            ],
          );
        },
      ),
    ),
  ).whenComplete(controller.dispose);
}
